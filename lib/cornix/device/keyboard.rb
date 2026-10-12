# frozen_string_literal: true

require 'json'
require 'digest'
require 'fileutils'
require 'time'
require 'set'
require_relative 'protocol'
require_relative 'keycodes'
require_relative 'macro_codec'

module Cornix
  module Device
    # 接続中のキーボードの状態を layout.vil 形式で読み出し、
    # layout.vil との差分計算と差分の書き込み（反映後に読み戻して検証）を行う。
    class Keyboard
      BACKUP_DIR = File.join(HidBridge::ROOT, 'tmp', 'device_backups')

      # RMK 0.8 の from_via_keycode が解釈できる範囲（それ以外は KC_NO として保存される）
      RMK_SUPPORTED = [
        0x0000..0x52BF, 0x5700..0x57FF, 0x7700..0x771F, 0x7C50..0x7C52,
        0x7C16..0x7C16, 0x7C73..0x7C73, 0x7C77..0x7C79, 0x7E00..0x7E0F
      ].freeze

      attr_reader :protocol, :keycodes, :dims, :positions

      def self.open
        HidBridge.open { |bridge| yield new(Protocol.new(bridge), bridge.info) }
      end

      def initialize(protocol, connection_info = {})
        @protocol = protocol
        @connection_info = connection_info
        load_layout_info
      end

      def info
        id = protocol.keyboard_id
        {
          connection: @connection_info,
          name: @definition['name'],
          via_protocol: protocol.via_protocol_version,
          vial_protocol: id[:vial_protocol],
          uid: id[:uid],
          firmware_version: protocol.firmware_version,
          matrix: { rows: dims[:rows], cols: dims[:cols] },
          layers: dims[:layers],
          encoders: dims[:encoders],
          macros: { count: @macro_count, buffer_size: @macro_size },
          tap_dance: @dynamic[:tap_dance],
          combo: @dynamic[:combo],
          key_override: @dynamic[:key_override],
          settings: @settings_ids,
          lock: protocol.unlock_status
        }
      end

      # キーボードの現在の状態（数値）
      def read_state
        flat = protocol.keymap_buffer(dims[:layers], dims[:rows], dims[:cols])
        per_layer = dims[:rows] * dims[:cols]
        layout = Array.new(dims[:layers]) do |l|
          Array.new(dims[:rows]) { |r| Array.new(dims[:cols]) { |c| flat[(l * per_layer) + (r * dims[:cols]) + c] } }
        end
        {
          layout: layout,
          encoders: Array.new(dims[:layers]) { |l| Array.new(dims[:encoders]) { |e| protocol.encoder(l, e) } },
          tap_dance: Array.new(@dynamic[:tap_dance]) { |i| protocol.tap_dance(i) },
          combo: Array.new(@dynamic[:combo]) { |i| protocol.combo(i) },
          macro: normalize_macro_buffer(protocol.macro_buffer(@macro_size, @macro_count)),
          settings: @settings_ids.to_h { |id| [id, protocol.setting(id)] }
        }
      end

      # 現在の状態を layout.vil 形式の Hash で返す
      def snapshot(state = read_state)
        id = protocol.keyboard_id
        {
          'version' => 1,
          'uid' => id[:uid],
          'vial_protocol' => id[:vial_protocol],
          'via_protocol' => protocol.via_protocol_version,
          'settings' => state[:settings].transform_keys(&:to_s),
          'layout' => state[:layout].each_with_index.map do |rows, l|
            rows.each_with_index.map do |cols, r|
              cols.each_with_index.map { |code, c| key_position?(r, c) ? keycodes.decode(code) : -1 }
            end
          end,
          'encoder_layout' => state[:encoders].map { |encs| encs.map { |pair| pair.map { |k| keycodes.decode(k) } } },
          'macro' => macro_codec.decode_all(state[:macro], @macro_count),
          'tap_dance' => state[:tap_dance].map { |td| [*td[:keys].map { |k| keycodes.decode(k) }, td[:term]] },
          'combo' => state[:combo].map { |cb| [*cb[:keys], cb[:output]].map { |k| keycodes.decode(k) } },
          'layout_options' => 0,
          'alt_repeat_key' => [],
          'key_override' => []
        }
      end

      def backup(state = read_state)
        FileUtils.mkdir_p(BACKUP_DIR)
        path = File.join(BACKUP_DIR, "#{Time.now.strftime('%Y%m%d-%H%M%S')}.vil")
        File.write(path, JSON.pretty_generate(snapshot(state)))
        path
      end

      # target（layout.vil の Hash）とキーボードの差分
      # => { changes: [...], warnings: [...], token: "..." }
      def diff(target, state = read_state)
        changes = []
        warnings = []
        diff_layout(target, state, changes, warnings)
        diff_encoders(target, state, changes, warnings)
        diff_tap_dance(target, state, changes, warnings)
        diff_combo(target, state, changes, warnings)
        diff_macro(target, state, changes, warnings)
        diff_settings(target, state, changes, warnings)
        warnings << 'layout_options はキーボードへ反映しません' if target['layout_options'].to_i != 0
        %w[key_override alt_repeat_key].each do |key|
          warnings << "#{key} はこのキーボードが対応していないため反映しません" if Array(target[key]).any?
        end
        changes.each do |ch|
          codes = ch[:codes] || []
          if (boot = codes.find { |c| Protocol::BOOT_KEYCODES.cover?(c) })
            raise DeviceError, "#{describe(ch)}: #{keycodes.decode(boot)} は安全のため書き込めません"
          end
          unsupported = codes.reject { |c| RMK_SUPPORTED.any? { |r| r.cover?(c) } }
          unsupported.each do |c|
            warnings << "#{describe(ch)}: #{keycodes.decode(c)} はファームウェアが未対応のため KC_NO になる可能性があります"
          end
        end
        { changes: changes, warnings: warnings, token: token_for(changes) }
      end

      # 差分を書き込み、読み戻して検証する
      # => { backup:, applied:, remaining: [...] }
      def apply(target, expected_token: nil)
        state = read_state
        result = diff(target, state)
        if expected_token && expected_token != result[:token]
          raise DeviceError, '差分が確認時から変わっています。もう一度 dry run で確認してください'
        end
        return { backup: nil, applied: 0, remaining: [] } if result[:changes].empty?

        backup_path = backup(state)
        result[:changes].each_with_index do |ch, i|
          write_change(ch)
        rescue DeviceError, ArgumentError => e
          raise DeviceError, "#{describe(ch)} の書き込みに失敗しました（#{i}/#{result[:changes].size} 件書き込み済み）: " \
                             "#{e.message}。反映前のバックアップ: #{backup_path}"
        end
        after = diff(target)
        { backup: backup_path, applied: result[:changes].size, remaining: after[:changes] }
      end

      def describe(change)
        case change[:kind]
        when :key then "レイヤー#{change[:layer]} (#{change[:row]},#{change[:col]})"
        when :encoder then "レイヤー#{change[:layer]} エンコーダ#{change[:index]} #{change[:clockwise] ? '時計回り' : '反時計回り'}"
        when :tap_dance then "タップダンス#{change[:index]}"
        when :combo then "コンボ#{change[:index]}"
        when :macro then "マクロ #{change[:indexes].map { |i| "M#{i}" }.join(', ')}"
        when :setting then "設定 #{change[:id]}"
        end
      end

      def format_change(change)
        "#{describe(change)}: #{change[:from]} → #{change[:to]}"
      end

      private

      def load_layout_info
        @definition = protocol.definition
        @keycodes = Keycodes.new(custom_keycodes: @definition['customKeycodes'] || [])
        matrix = @definition.fetch('matrix')
        @positions, encoder_count = parse_kle(@definition.dig('layouts', 'keymap') || [])
        @dims = { layers: protocol.layer_count, rows: matrix['rows'], cols: matrix['cols'], encoders: encoder_count }
        @macro_count = protocol.macro_count
        @macro_size = protocol.macro_buffer_size
        @dynamic = protocol.dynamic_entry_counts
        @settings_ids = protocol.supported_settings & Protocol::SETTING_WIDTHS.keys
      end

      # KLE 形式のラベルからキーの位置とエンコーダ数を取り出す（Vial と同じく 10 行目が "e" ならエンコーダ）
      def parse_kle(rows)
        positions = Set.new
        encoders = 0
        rows.flatten.grep(String).each do |label|
          lines = label.split("\n", -1)
          a, b = lines[0].to_s.split(',').map(&:to_i)
          next if a.nil? || b.nil?

          if lines[9] == 'e'
            encoders = [encoders, a + 1].max
          else
            positions << [a, b]
          end
        end
        [positions, encoders]
      end

      def key_position?(row, col)
        positions.include?([row, col])
      end

      def macro_codec
        @macro_codec ||= MacroCodec.new(keycodes)
      end

      def normalize_macro_buffer(buffer)
        parts = buffer.split("\x00".b, -1) + [''.b] * @macro_count
        parts.first(@macro_count).map { |p| p + "\x00".b }.join.b
      end

      def encode!(value, where)
        keycodes.encode(value)
      rescue Keycodes::UnknownKeycode => e
        raise DeviceError, "#{where}: #{e.message}"
      end

      def diff_layout(target, state, changes, warnings)
        layers = Array(target['layout'])
        raise DeviceError, "レイヤー数がキーボード (#{dims[:layers]}) より多い: #{layers.size}" if layers.size > dims[:layers]

        warnings << "layout.vil のレイヤー数 (#{layers.size}) がキーボード (#{dims[:layers]}) より少ない" if layers.size < dims[:layers]
        layers.each_with_index do |rows, l|
          rows.each_with_index do |cols, r|
            cols.each_with_index do |value, c|
              where = "レイヤー#{l} (#{r},#{c})"
              if r >= dims[:rows] || c >= dims[:cols] || !key_position?(r, c)
                warnings << "#{where} はキーボード上に存在しない位置のため無視します" unless value == -1
                next
              end
              if value == -1
                warnings << "#{where} が layout.vil で -1 のため無視します"
                next
              end
              code = encode!(value, where)
              current = state[:layout][l][r][c]
              next if code == current

              changes << { kind: :key, layer: l, row: r, col: c, code: code, codes: [code],
                           from: keycodes.decode(current), to: keycodes.decode(code) }
            end
          end
        end
      end

      def diff_encoders(target, state, changes, warnings)
        Array(target['encoder_layout']).each_with_index do |encs, l|
          next if l >= dims[:layers]

          encs.each_with_index do |pair, e|
            if e >= dims[:encoders]
              warnings << "レイヤー#{l} エンコーダ#{e} はキーボードに存在しないため無視します"
              next
            end
            pair.each_with_index do |value, dir|
              code = encode!(value, "レイヤー#{l} エンコーダ#{e}")
              current = state[:encoders][l][e][dir]
              next if code == current

              changes << { kind: :encoder, layer: l, index: e, clockwise: dir == 1, code: code, codes: [code],
                           from: keycodes.decode(current), to: keycodes.decode(code) }
            end
          end
        end
      end

      def diff_tap_dance(target, state, changes, warnings)
        Array(target['tap_dance']).each_with_index do |entry, i|
          keys = entry[0, 4].map { |k| encode!(k, "タップダンス#{i}") }
          term = Integer(entry[4] || 0)
          if i >= state[:tap_dance].size
            warnings << "タップダンス#{i} はキーボードの上限を超えるため無視します" unless keys.all?(&:zero?)
            next
          end
          current = state[:tap_dance][i]
          next if current[:keys] == keys && current[:term] == term

          changes << { kind: :tap_dance, index: i, keys: keys, term: term, codes: keys,
                       from: format_td(current[:keys], current[:term]), to: format_td(keys, term) }
        end
      end

      def diff_combo(target, state, changes, warnings)
        Array(target['combo']).each_with_index do |entry, i|
          codes = entry[0, 5].map { |k| encode!(k, "コンボ#{i}") }
          if i >= state[:combo].size
            warnings << "コンボ#{i} はキーボードの上限を超えるため無視します" unless codes.all?(&:zero?)
            next
          end
          current = state[:combo][i]
          next if [*current[:keys], current[:output]] == codes

          changes << { kind: :combo, index: i, keys: codes[0, 4], output: codes[4], codes: codes,
                       from: format_combo([*current[:keys], current[:output]]), to: format_combo(codes) }
        end
      end

      def diff_macro(target, state, changes, warnings)
        macros = Array(target['macro'])
        if macros.size > @macro_count && macros[@macro_count..].any? { |m| !m.empty? }
          raise DeviceError, "マクロ数がキーボードの上限 (#{@macro_count}) を超えています"
        end

        padded = (macros + [[]] * @macro_count).first(@macro_count)
        buffer = begin
          macro_codec.encode_all(padded)
        rescue Keycodes::UnknownKeycode, ArgumentError => e
          raise DeviceError, "マクロ: #{e.message}"
        end
        raise DeviceError, "マクロがバッファ (#{@macro_size} バイト) に収まりません" if buffer.bytesize > @macro_size
        return if buffer == state[:macro]

        before = state[:macro].split("\x00".b, -1)
        after = buffer.split("\x00".b, -1)
        indexes = (0...@macro_count).reject { |i| before[i] == after[i] }
        codes = padded.values_at(*indexes).flatten(1).flat_map do |action|
          %w[tap down up].include?(action[0]) ? action[1..].map { |k| keycodes.encode(k) } : []
        end
        current = macro_codec.decode_all(state[:macro], @macro_count)
        changes << { kind: :macro, indexes: indexes, buffer: buffer, codes: codes,
                     from: indexes.map { |i| current[i].to_json }.join(' / '),
                     to: indexes.map { |i| padded[i].to_json }.join(' / ') }
      end

      def diff_settings(target, state, changes, warnings)
        (target['settings'] || {}).each do |key, value|
          id = key.to_i
          unless state[:settings].key?(id)
            warnings << "設定 #{id} はこのキーボードでは扱えないため無視します"
            next
          end
          next if state[:settings][id] == value

          changes << { kind: :setting, id: id, value: value, from: state[:settings][id], to: value }
        end
      end

      def write_change(change)
        case change[:kind]
        when :key
          protocol.set_keycode(change[:layer], change[:row], change[:col], change[:code], dims: dims)
        when :encoder
          protocol.set_encoder(change[:layer], change[:index], change[:clockwise], change[:code], dims: dims)
        when :tap_dance
          protocol.set_tap_dance(change[:index], change[:keys], change[:term], count: @dynamic[:tap_dance])
        when :combo
          protocol.set_combo(change[:index], change[:keys], change[:output], count: @dynamic[:combo])
        when :macro
          protocol.set_macro_buffer(change[:buffer], size: @macro_size)
        when :setting
          protocol.set_setting(change[:id], change[:value])
        end
      end

      def format_td(keys, term)
        "[#{keys.map { |k| keycodes.decode(k) }.join(', ')}, #{term}ms]"
      end

      def format_combo(codes)
        "[#{codes[0, 4].map { |k| keycodes.decode(k) }.join(' + ')} → #{keycodes.decode(codes[4])}]"
      end

      def token_for(changes)
        payload = changes.map { |ch| ch.reject { |k, _| %i[from to].include?(k) }.transform_values { |v| v.is_a?(String) ? v.unpack1('H*') : v } }
        Digest::SHA256.hexdigest(JSON.generate(payload))[0, 16]
      end
    end
  end
end
