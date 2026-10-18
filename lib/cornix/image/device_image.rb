# frozen_string_literal: true

module Cornix
  module Image
    # デバイス（と layout.vil）が持つ値を、解釈せずに 16bit 整数とバイト列のまま持つ型。
    # Domain には依存しない。差分（Planning::ImageDiff）はこの型どうしで取る。
    #
    #   layers     [layer][row][col] => Integer（キーコード）| nil（その位置にキーがない。.vil の -1）
    #   encoders   [layer][encoder]  => EncoderRecord（ccw, cw）。push はマトリクス側（layers）にある
    #   macros     [index]           => [MacroAction]
    #   tap_dances [index]           => TapDanceRecord
    #   combos     [index]           => ComboRecord
    #   settings   { QSID(Integer) => Integer }
    #   meta       .vil のその他のトップレベル項目（version, uid, vial_protocol, via_protocol,
    #              layout_options, alt_repeat_key, key_override）。解釈せずにそのまま運ぶ
    class DeviceImage < Data.define(:layers, :encoders, :macros, :tap_dances, :combos, :settings, :meta)
      def initialize(layers:, encoders:, macros:, tap_dances:, combos:, settings:, meta: {})
        super(layers: Image.deep_freeze(layers), encoders: Image.deep_freeze(encoders),
              macros: Image.deep_freeze(macros), tap_dances: Image.deep_freeze(tap_dances),
              combos: Image.deep_freeze(combos), settings: Image.deep_freeze(settings),
              meta: Image.deep_freeze(meta))
      end
    end

    # エンコーダ 1 つ分の回転（反時計回り / 時計回り）
    class EncoderRecord < Data.define(:ccw, :cw); end

    # マクロの 1 動作。kind は :tap / :down / :up（keys に整数のキーコード）、
    # :delay（value にミリ秒）、:text（value に文字列）
    class MacroAction < Data.define(:kind, :keys, :value)
      KINDS = %i[tap down up delay text].freeze

      def initialize(kind:, keys: [], value: nil)
        raise InvalidValue, "マクロの動作が不正です: #{kind.inspect}" unless KINDS.include?(kind)

        super(kind: kind, keys: Image.deep_freeze(keys), value: value.is_a?(String) ? value.dup.freeze : value)
      end
    end

    # タップダンス 1 つ分（4 つの動作とタッピング時間）
    class TapDanceRecord < Data.define(:on_tap, :on_hold, :on_double_tap, :on_tap_hold, :tapping_term); end

    # コンボ 1 つ分（keys は 4 要素、未使用は 0 = KC_NO）
    class ComboRecord < Data.define(:keys, :output)
      def initialize(keys:, output:)
        super(keys: Image.deep_freeze(keys), output: output)
      end
    end

    def self.deep_freeze(value)
      case value
      when Array then value.map { |v| deep_freeze(v) }.freeze
      when Hash then value.to_h { |k, v| [deep_freeze(k), deep_freeze(v)] }.freeze
      when String then value.frozen? ? value : value.dup.freeze
      else value
      end
    end
  end
end
