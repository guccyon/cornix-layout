# frozen_string_literal: true

module Cornix
  module Mapping
    # Vial のマクロバッファ（NUL 区切りのバイト列）⇄ [[Image::MacroAction]] の変換。
    #
    # バイト列の形式は Vial protocol >= 2（vial-gui の macro_action.py / protocol/macro.py と同じ）。
    # キーコードは 16bit 整数のまま扱い、名前への変換はしない。
    #   01 01 kc / 01 02 kc / 01 03 kc      tap / down / up（kc が 1 バイトに収まる場合）
    #   01 05 lo hi / 01 06 .. / 01 07 ..   tap / down / up の拡張（16bit。下位バイトが 0 なら 0xFF00 | 上位バイト）
    #   01 04 a b                           delay（ms = (a - 1) + (b - 1) * 255）
    #   それ以外のバイト                     text
    # decode は連続する同じ種類のキー操作を 1 つの MacroAction にまとめ、連続する text もまとめる。
    class MacroCodec
      SS_QMK_PREFIX = 1
      SS_TAP_CODE = 1
      SS_DOWN_CODE = 2
      SS_UP_CODE = 3
      SS_DELAY_CODE = 4
      VIAL_MACRO_EXT_TAP = 5
      VIAL_MACRO_EXT_DOWN = 6
      VIAL_MACRO_EXT_UP = 7

      CODE_FOR_KIND = { tap: SS_TAP_CODE, down: SS_DOWN_CODE, up: SS_UP_CODE }.freeze
      KIND_FOR_CODE = CODE_FOR_KIND.invert.freeze
      EXT_TO_BASIC = { VIAL_MACRO_EXT_TAP => SS_TAP_CODE, VIAL_MACRO_EXT_DOWN => SS_DOWN_CODE,
                       VIAL_MACRO_EXT_UP => SS_UP_CODE }.freeze
      MAX_DELAY = (254 * 255) + 254
      NUL = "\x00".b.freeze

      # [[MacroAction]] → バッファ（末尾の空マクロも NUL で区切って全件分出力）
      def encode_all(macros)
        macros.map { |actions| encode(actions) + NUL }.join.b
      end

      # [MacroAction] → 1 マクロ分のバイト列（終端の NUL は含まない）
      def encode(actions)
        actions.each_with_object(+''.b) { |action, out| out << encode_action(action) }
      end

      # バッファ → count 個の [MacroAction]（足りない分は空のマクロ）
      def decode_all(buffer, count)
        parts = buffer.b.split(NUL, -1) + ([''.b] * count)
        parts.first(count).map { |part| decode(part) }
      end

      # 1 マクロ分のバイト列 → [MacroAction]
      def decode(bytes)
        data = bytes.b.bytes
        seq = []
        until data.empty?
          consumed = data[0] == SS_QMK_PREFIX ? decode_command(data, seq) : decode_text(data, seq)
          break if consumed.nil?

          data.shift(consumed)
        end
        seq.map { |entry| to_action(entry) }
      end

      private

      def encode_action(action)
        case action.kind
        when :text then encode_text(action.value)
        when :delay then encode_delay(action.value)
        else action.keys.map { |kc| encode_key(CODE_FOR_KIND.fetch(action.kind), kc) }.join.b
        end
      end

      def encode_text(value)
        text = value.to_s.b
        raise InvalidValue, 'マクロの text に NUL や制御コード 1 は使えません' if text.include?("\x00") || text.include?("\x01")

        text
      end

      def encode_delay(value)
        ms = Integer(value)
        raise InvalidValue, "delay の範囲外: #{ms}" unless ms.between?(0, MAX_DELAY)

        [SS_QMK_PREFIX, SS_DELAY_CODE, (ms % 255) + 1, (ms / 255) + 1].pack('C4')
      rescue ArgumentError, TypeError
        raise InvalidValue, "delay が整数ではありません: #{value.inspect}"
      end

      def encode_key(code, kc)
        raise InvalidValue, "マクロのキーコードが範囲外: #{kc.inspect}" unless kc.is_a?(Integer) && kc.between?(0, 0xFFFF)
        return [SS_QMK_PREFIX, code, kc].pack('C3') if kc < 256

        kc = 0xFF00 | (kc >> 8) if (kc % 256).zero?
        [SS_QMK_PREFIX, code + 4, kc].pack('C2v')
      end

      # 01 で始まる命令を 1 つ読む。読んだバイト数（途中で切れていれば nil）
      def decode_command(data, seq)
        return nil if data.size < 2

        act = data[1]
        if KIND_FOR_CODE.key?(act)
          return nil if data.size < 3

          push_key(seq, act, data[2])
          3
        elsif EXT_TO_BASIC.key?(act)
          return nil if data.size < 4

          kc = data[2] | (data[3] << 8)
          kc = (kc & 0xFF) << 8 if kc > 0xFF00
          push_key(seq, EXT_TO_BASIC[act], kc)
          4
        elsif act == SS_DELAY_CODE
          return nil if data.size < 4

          seq << [:delay, (data[2] - 1) + ((data[3] - 1) * 255)]
          4
        else
          2
        end
      end

      def decode_text(data, seq)
        if seq.last && seq.last[0] == :text
          seq.last[1] << data[0]
        else
          seq << [:text, +''.b << data[0]]
        end
        1
      end

      def push_key(seq, code, kc)
        if seq.last && seq.last[0] == code
          seq.last[1] << kc
        else
          seq << [code, [kc]]
        end
      end

      def to_action(entry)
        kind, payload = entry
        case kind
        when Integer then Image::MacroAction.new(kind: KIND_FOR_CODE.fetch(kind), keys: payload)
        when :text then Image::MacroAction.new(kind: :text, value: utf8(payload))
        else Image::MacroAction.new(kind: kind, value: payload)
        end
      end

      # .vil は UTF-8 の JSON なので、UTF-8 として正しければ UTF-8 の文字列にする（正しくなければバイト列のまま）
      def utf8(bytes)
        text = bytes.dup.force_encoding(Encoding::UTF_8)
        text.valid_encoding? ? text : bytes
      end
    end
  end
end
