# frozen_string_literal: true

module Cornix
  module Device
    # Vial のマクロバッファ（NUL 区切りのバイト列）と layout.vil のマクロ表現の相互変換
    #
    # layout.vil のマクロ: [[["tap", "KC_A", "KC_B"], ["text", "abc"], ["delay", 100]], ...]
    # バイト列の形式は Vial protocol >= 2（vial-gui の macro_action.py / protocol/macro.py と同じ）。
    class MacroCodec
      SS_QMK_PREFIX = 1
      SS_TAP_CODE = 1
      SS_DOWN_CODE = 2
      SS_UP_CODE = 3
      SS_DELAY_CODE = 4
      VIAL_MACRO_EXT_TAP = 5
      VIAL_MACRO_EXT_DOWN = 6
      VIAL_MACRO_EXT_UP = 7

      CODE_FOR_TAG = { 'tap' => SS_TAP_CODE, 'down' => SS_DOWN_CODE, 'up' => SS_UP_CODE }.freeze
      TAG_FOR_CODE = CODE_FOR_TAG.invert.freeze
      EXT_TO_BASIC = { VIAL_MACRO_EXT_TAP => SS_TAP_CODE, VIAL_MACRO_EXT_DOWN => SS_DOWN_CODE,
                       VIAL_MACRO_EXT_UP => SS_UP_CODE }.freeze

      def initialize(keycodes)
        @keycodes = keycodes
      end

      # マクロ配列 → バッファ（末尾の空マクロも NUL で区切って全件分出力）
      def encode_all(macros)
        macros.map { |m| encode(m) + "\x00".b }.join.b
      end

      def encode(actions)
        out = +''.b
        actions.each do |action|
          tag, *args = action
          case tag
          when 'text'
            text = args.first.to_s.b
            raise ArgumentError, 'マクロの text に NUL や制御コード 1 は使えません' if text.include?("\x00") || text.include?("\x01")

            out << text
          when 'delay'
            ms = Integer(args.first)
            raise ArgumentError, "delay の範囲外: #{ms}" unless ms.between?(0, 254 * 255 + 254)

            out << [SS_QMK_PREFIX, SS_DELAY_CODE, (ms % 255) + 1, (ms / 255) + 1].pack('C4')
          when 'tap', 'down', 'up'
            args.each { |kc| out << encode_key(CODE_FOR_TAG[tag], @keycodes.encode(kc)) }
          else
            raise ArgumentError, "不明なマクロアクション: #{tag}"
          end
        end
        out
      end

      # バッファ → マクロ配列（count 個）
      def decode_all(buffer, count)
        parts = buffer.b.split("\x00".b, -1)
        parts += [''.b] * count
        parts.first(count).map { |p| decode(p) }
      end

      def decode(bytes)
        data = bytes.bytes
        seq = []
        until data.empty?
          if data[0] == SS_QMK_PREFIX
            break if data.size < 2

            act = data[1]
            if CODE_FOR_TAG.value?(act)
              break if data.size < 3

              push_key(seq, act, data[2])
              data.shift(3)
            elsif EXT_TO_BASIC.key?(act)
              break if data.size < 4

              kc = data[2] | (data[3] << 8)
              kc = (kc & 0xFF) << 8 if kc > 0xFF00
              push_key(seq, EXT_TO_BASIC[act], kc)
              data.shift(4)
            elsif act == SS_DELAY_CODE
              break if data.size < 4

              seq << ['delay', (data[2] - 1) + ((data[3] - 1) * 255)]
              data.shift(4)
            else
              data.shift(2)
            end
          else
            if seq.last && seq.last[0] == 'text'
              seq.last[1] += data[0].chr
            else
              seq << ['text', data[0].chr]
            end
            data.shift
          end
        end
        seq.map do |entry|
          entry[0].is_a?(Integer) ? [TAG_FOR_CODE[entry[0]], *entry[1].map { |kc| @keycodes.decode(kc) }] : entry
        end
      end

      private

      def encode_key(code, kc)
        return [SS_QMK_PREFIX, code, kc].pack('C3') if kc < 256

        kc = 0xFF00 | (kc >> 8) if (kc % 256).zero?
        [SS_QMK_PREFIX, code + 4, kc].pack('C2v')
      end

      def push_key(seq, code, kc)
        if seq.last && seq.last[0] == code
          seq.last[1] << kc
        else
          seq << [code, [kc]]
        end
      end
    end
  end
end
