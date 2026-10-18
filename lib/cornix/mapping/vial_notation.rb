# frozen_string_literal: true

module Cornix
  module Mapping
    # layout.vil に書くキーコードの文字列 ⇄ Domain::Keycode。
    #
    # format は Vial GUI が .vil に保存する表記（KC_A, LSFT(KC_2), LT1(KC_SPACE), MO(3), TD(3), M7,
    # OSM(MOD_LCTL|MOD_LSFT)、表にない値は 0x7e40 のような小文字の 16 進）。
    # parse は Vial GUI の AnyKeycode と同じく、名前・QMK 名・MOD_ 定数・数値と、
    # LSFT(KC_A) / LT(1, KC_A) / MT(MOD_LCTL, KC_A) / OSM(MOD_LCTL|MOD_LSFT) / MO(3) / TD(3) / M7 / KC_A|0x200 などの式を受け付ける。
    class VialNotation
      # Vial の名前を持つ修飾関数（ビット → 名前）。それ以外の修飾の組は .vil では 16 進で書かれる
      MOD_FUNCTION_NAMES = {
        0x01 => 'LCTL', 0x02 => 'LSFT', 0x03 => 'C_S', 0x04 => 'LALT', 0x05 => 'LCA', 0x06 => 'LSA',
        0x07 => 'MEH', 0x08 => 'LGUI', 0x09 => 'LCG', 0x0A => 'SGUI', 0x0C => 'LAG', 0x0D => 'LCAG',
        0x0F => 'HYPR', 0x11 => 'RCTL', 0x12 => 'RSFT', 0x14 => 'RALT', 0x18 => 'RGUI', 0x19 => 'RCG'
      }.freeze

      MOD_TAP_NAMES = MOD_FUNCTION_NAMES
                      .reject { |bits, _| bits == 0x0F }
                      .transform_values { |name| "#{name}_T" }
                      .merge(0x0F => 'ALL_T', 0x1D => 'RCAG_T').freeze

      # 上位バイトで決まり、下位バイトに基本キーを入れる値（上位バイトの値 → 関数名）
      MASKED = MOD_FUNCTION_NAMES.to_h { |bits, name| [bits << 8, name] }
                                 .merge(MOD_TAP_NAMES.to_h { |bits, name| [KeycodeCodec::MOD_TAP.begin | (bits << 8), name] })
                                 .merge((0..15).to_h { |n| [KeycodeCodec::LAYER_TAP.begin | (n << 8), "LT#{n}"] })
                                 .freeze

      LAYER_FUNCTIONS = {
        to: 'TO', momentary: 'MO', default: 'DF', toggle: 'TG',
        one_shot: 'OSL', tap_toggle: 'TT', persistent_default: 'PDF'
      }.freeze

      ONE_SHOT_MOD_ORDER = %i[ctrl shift alt gui].freeze

      # 引数付きで名前を持つ値（値 → 名前）。レイヤー操作は 0〜15 だけ Vial の表にある
      NAMED = {}.tap do |named|
        LAYER_FUNCTIONS.each do |op, name|
          (0..15).each { |n| named[KeycodeCodec::LAYER_OPS.fetch(op) + n] = "#{name}(#{n})" }
        end
        (0..255).each do |n|
          named[KeycodeCodec::TAP_DANCE.begin + n] = "TD(#{n})"
          named[KeycodeCodec::MACRO.begin + n] = "M#{n}"
        end
        [0x00, 0x10].each do |side|
          (0x01..0x0F).each do |mods|
            bits = side | mods
            label = if bits == 0x07 then 'MOD_MEH'
                    elsif bits == 0x0F then 'MOD_HYPR'
                    else
                      prefix = side.zero? ? 'MOD_L' : 'MOD_R'
                      ONE_SHOT_MOD_ORDER.select { |m| bits.anybits?(Domain::ModifierSet::BITS[m]) }
                                        .map { |m| prefix + { ctrl: 'CTL', shift: 'SFT', alt: 'ALT', gui: 'GUI' }[m] }
                                        .join('|')
                    end
            named[KeycodeCodec::ONE_SHOT_MOD.begin | bits] = "OSM(#{label})"
          end
        end
      end.freeze

      # 名前として使える定数（Vial の AnyKeycode と同じ）
      CONSTANTS = {
        'MOD_LCTL' => 0x01, 'MOD_LSFT' => 0x02, 'MOD_LALT' => 0x04, 'MOD_LGUI' => 0x08,
        'MOD_RCTL' => 0x11, 'MOD_RSFT' => 0x12, 'MOD_RALT' => 0x14, 'MOD_RGUI' => 0x18,
        'MOD_MEH' => 0x07, 'MOD_HYPR' => 0x0F
      }.freeze

      NUMBER = /\A(0x\h+|\d+)\z/
      MACRO_NAME = /\AM(\d+)\z/

      def initialize(catalog: KeycodeCatalog.default, codec: KeycodeCodec.new(catalog))
        @catalog = catalog
        @codec = codec
      end

      attr_reader :catalog, :codec

      # .vil の文字列 → Domain::Keycode
      def parse(text) = @codec.decode(parse_code(text))

      # Domain::Keycode → .vil の文字列
      def format(keycode) = format_code(@codec.encode(keycode))

      # .vil の文字列（または整数）→ 16bit 値。解釈できなければ UnknownKeycode
      def parse_code(text)
        code = text.is_a?(Integer) ? text : (lookup(text.to_s.strip) || Expression.new(text.to_s.strip, self).evaluate)
        raise UnknownKeycode, "不明なキーコード: #{text}（値が 0〜0xFFFF の範囲外です）" unless code.between?(0, 0xFFFF)

        code
      rescue Expression::ParseError => e
        raise UnknownKeycode, "不明なキーコード: #{text}（#{e.message}）"
      end

      # 16bit 値 → .vil の文字列（Vial GUI の Keycode.serialize と同じ）
      def format_code(code)
        raise ArgumentError, "キーコードは 0〜0xFFFF の整数です: #{code.inspect}" unless code.is_a?(Integer) && code.between?(0, 0xFFFF)

        if (outer = MASKED[code & 0xFF00])
          inner = @catalog.vial_name(code & 0x00FF)
          return "#{outer}(#{inner})" if inner
        else
          name = @catalog.vial_name(code) || NAMED[code]
          return name if name
        end
        ::Kernel.format('0x%x', code)
      end

      # 名前・MOD_ 定数・数値 → 値（関数形式は対象外。なければ nil）
      def lookup(name)
        if (code = @catalog.code_for_name(name)) then code
        elsif (m = MACRO_NAME.match(name)) then (KeycodeCodec::MACRO.begin + m[1].to_i if m[1].to_i <= 255)
        elsif CONSTANTS.key?(name) then CONSTANTS[name]
        elsif NUMBER.match?(name) then Integer(name, 0)
        end
      end
    end
  end
end
