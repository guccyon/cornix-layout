# frozen_string_literal: true

require 'json'
require 'open3'
require 'tmpdir'
require_relative 'hid_bridge'

module Cornix
  module Device
    # Vial / VIA プロトコルのコマンド層
    #
    # Cornix のファームウェアは RMK 0.8 系で、vial-qmk と違い範囲検査がほとんどない
    # （範囲外の layer/row/col やマクロのオフセットでファームウェアがパニックする）。
    # そのため書き込み系はすべてここで範囲を検査してから送る。
    #
    # 使わない（送らない）コマンド:
    #   0x06 キーマップ全消去 / 0x0A EEPROM リセット / 0x0B bootloader 移行 / 0x10 マクロ全消去
    #   0x13 キーマップ一括書き込み（RMK 0.8 ではバッファ外を読んでパニックする）
    #   0xFE 0x06/0x07 アンロック / 0xFE 0x0C 設定リセット
    class Protocol
      CHUNK = 28
      BOOT_KEYCODES = (0x7C00..0x7C0F) # QK_BOOT, QK_REBOOT, QK_CLEAR_EEPROM など

      # Vial GUI の qmk_settings.json の幅（バイト数）。ここにある ID だけ読み書きする。
      SETTING_WIDTHS = { 2 => 2, 6 => 2, 7 => 2, 18 => 2, 19 => 2, 22 => 1, 23 => 1, 26 => 1, 27 => 2 }.freeze

      attr_reader :transport

      # dangerous_keycode: 書き込みを拒否するキーコードか（Integer → 真偽）。省略時は BOOT_KEYCODES
      # setting_widths: 読み書きする設定 ID → 幅（バイト数）。省略時は SETTING_WIDTHS
      # （新しいコードは Mapping::KeycodeCatalog#dangerous? と Mapping::QmkSettingCatalog の幅を渡す）
      def initialize(transport, dangerous_keycode: nil, setting_widths: SETTING_WIDTHS)
        @transport = transport
        @dangerous_keycode = dangerous_keycode || BOOT_KEYCODES.method(:cover?)
        @setting_widths = setting_widths
      end

      attr_reader :setting_widths

      # ---- 読み取り ----

      def via_protocol_version
        r = via(0x01)
        (r[1] << 8) | r[2]
      end

      def firmware_version
        r = via(0x02, 0x04)
        r[2..5].pack('C4').unpack1('N')
      end

      def keyboard_id
        r = vial(0x00)
        { vial_protocol: r[0..3].pack('C4').unpack1('V'), uid: r[4..11].pack('C8').unpack1('Q<') }
      end

      def definition
        size = vial(0x01)[0..3].pack('C4').unpack1('V')
        raise DeviceError, "キーボード定義のサイズが不正: #{size}" unless size.between?(1, 64 * 1024)

        data = (0...((size + 31) / 32)).flat_map { |page| vial(0x02, page & 0xFF, page >> 8) }
        JSON.parse(lzma_decompress(data.first(size).pack('C*')))
      end

      def unlock_status
        r = vial(0x05)
        keys = r[2..].each_slice(2).take_while { |row, col| row != 0xFF && col != 0xFF }
        { unlocked: r[0] == 1, in_progress: r[1] == 1, unlock_keys: keys }
      end

      def layer_count
        via(0x11)[1]
      end

      # キーマップ全体（layer → row → col の順の 16bit 値）。ブロックを渡すと 1 回読むごとに呼ぶ（進み具合）
      def keymap_buffer(layers, rows, cols)
        total = layers * rows * cols * 2
        bytes = []
        (0...total).step(CHUNK) do |offset|
          size = [CHUNK, total - offset].min
          r = via(0x12, offset >> 8, offset & 0xFF, size)
          expect_echo!(r, [0x12, offset >> 8, offset & 0xFF, size])
          bytes.concat(r[4, size])
          yield if block_given?
        end
        bytes.pack('C*').unpack('n*')
      end

      # [counter_clockwise, clockwise]
      def encoder(layer, index)
        r = vial(0x03, layer, index)
        [(r[0] << 8) | r[1], (r[2] << 8) | r[3]]
      end

      def macro_count
        via(0x0C)[1]
      end

      def macro_buffer_size
        r = via(0x0D)
        (r[1] << 8) | r[2]
      end

      # マクロバッファ（count 個の NUL を読んだ時点で打ち切る。size を超えては読まない）。
      # ブロックを渡すと 1 回読むごとに呼ぶ（進み具合）
      def macro_buffer(size, count)
        bytes = []
        (0...size).step(CHUNK) do |offset|
          len = [CHUNK, size - offset].min
          r = via(0x0E, offset >> 8, offset & 0xFF, len)
          expect_echo!(r, [0x0E, offset >> 8, offset & 0xFF, len])
          bytes.concat(r[4, len])
          yield if block_given?
          break if bytes.count(0) > count
        end
        bytes.pack('C*')
      end

      def dynamic_entry_counts
        r = vial(0x0D, 0x00)
        { tap_dance: r[0], combo: r[1], key_override: r[2] }
      end

      # { keys: [tap, hold, double_tap, tap_hold], term: ms }
      def tap_dance(index)
        r = vial(0x0D, 0x01, index)
        v = r[1..10].pack('C*').unpack('v5')
        { keys: v[0, 4], term: v[4] }
      end

      # { keys: [k1, k2, k3, k4], output: kc }
      def combo(index)
        r = vial(0x0D, 0x03, index)
        v = r[1..10].pack('C*').unpack('v5')
        { keys: v[0, 4], output: v[4] }
      end

      def supported_settings
        ids = []
        greater_than = 0
        loop do
          r = vial(0x09, greater_than & 0xFF, greater_than >> 8)
          batch = r.each_slice(2).map { |lo, hi| lo | (hi << 8) }.take_while { |id| id != 0xFFFF }
          new_ids = batch.select { |id| id > greater_than } - ids
          break if new_ids.empty?

          ids.concat(new_ids)
          greater_than = new_ids.max
        end
        ids.sort
      end

      def setting(id)
        width = setting_widths.fetch(id) { raise DeviceError, "未対応の設定 ID: #{id}" }
        r = vial(0x0A, id & 0xFF, id >> 8)
        raise DeviceError, "設定 #{id} の取得に失敗しました" unless r[0].zero?

        r[1, width].each_with_index.sum { |b, i| b << (8 * i) }
      end

      # ---- 書き込み（範囲検査つき） ----

      def set_keycode(layer, row, col, code, dims:)
        check_range!('layer', layer, dims[:layers])
        check_range!('row', row, dims[:rows])
        check_range!('col', col, dims[:cols])
        check_keycode!(code)
        via(0x05, layer, row, col, code >> 8, code & 0xFF)
      end

      def set_encoder(layer, index, clockwise, code, dims:)
        check_range!('layer', layer, dims[:layers])
        check_range!('encoder', index, dims[:encoders])
        check_keycode!(code)
        vial(0x04, layer, index, clockwise ? 1 : 0, code >> 8, code & 0xFF)
      end

      def set_tap_dance(index, keys, term, count:)
        check_range!('tap dance', index, count)
        raise ArgumentError, 'tap dance のキーは 4 個' unless keys.size == 4

        keys.each { |k| check_keycode!(k) }
        check_u16!('tapping term', term)
        vial(0x0D, 0x02, index, *[*keys, term].pack('v5').bytes)
      end

      def set_combo(index, keys, output, count:)
        check_range!('combo', index, count)
        raise ArgumentError, 'combo のキーは 4 個' unless keys.size == 4

        [*keys, output].each { |k| check_keycode!(k) }
        vial(0x0D, 0x04, index, *[*keys, output].pack('v5').bytes)
      end

      def set_setting(id, value)
        width = setting_widths.fetch(id) { raise ArgumentError, "未対応の設定 ID: #{id}" }
        max = width == 1 ? 1 : (1 << (8 * width)) - 1
        raise ArgumentError, "設定 #{id} の値が範囲外: #{value}" unless value.is_a?(Integer) && value.between?(0, max)

        vial(0x0B, id & 0xFF, id >> 8, *Array.new(width) { |i| (value >> (8 * i)) & 0xFF })
      end

      # マクロバッファ全体を書き込む（Vial GUI と同じく先頭から 28 バイトずつ）
      def set_macro_buffer(data, size:)
        bytes = data.b.bytes
        raise ArgumentError, "マクロが大きすぎます: #{bytes.size} > #{size}" if bytes.size > size
        raise ArgumentError, 'マクロが空です' if bytes.empty?

        bytes.each_slice(CHUNK).with_index do |chunk, i|
          offset = i * CHUNK
          raise ArgumentError, 'マクロの範囲外' if offset + chunk.size > size

          via(0x0F, offset >> 8, offset & 0xFF, chunk.size, *chunk)
        end
      end

      private

      def via(*bytes)
        transport.transfer(bytes)
      end

      def vial(*bytes)
        transport.transfer([0xFE, *bytes])
      end

      def expect_echo!(response, prefix)
        return if response[0, prefix.size] == prefix

        raise DeviceError, "想定外の応答: #{response.first(8).map { |b| format('%02x', b) }.join(' ')}"
      end

      def check_range!(name, value, limit)
        return if value.is_a?(Integer) && value >= 0 && value < limit

        raise ArgumentError, "#{name} が範囲外: #{value.inspect}（0〜#{limit - 1}）"
      end

      def check_u16!(name, value)
        return if value.is_a?(Integer) && value.between?(0, 0xFFFF)

        raise ArgumentError, "#{name} が範囲外: #{value.inspect}"
      end

      def check_keycode!(code)
        check_u16!('keycode', code)
        return unless @dangerous_keycode.call(code)

        raise ArgumentError, format('boot 系キーコード (0x%04x) は書き込めません', code)
      end

      # macOS 標準の compression_tool で xz (LZMA) を展開する
      def lzma_decompress(data)
        Dir.mktmpdir('cornix-def') do |dir|
          src = File.join(dir, 'def.xz')
          dst = File.join(dir, 'def.json')
          File.binwrite(src, data)
          out, status = Open3.capture2e('compression_tool', '-decode', '-a', 'lzma', '-i', src, '-o', dst)
          raise DeviceError, "キーボード定義の展開に失敗しました: #{out}" unless status.success?

          File.read(dst)
        end
      end
    end
  end
end
