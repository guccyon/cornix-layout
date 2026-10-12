# frozen_string_literal: true

require 'yaml'
require 'set'

module Cornix
  module Device
    # Vial protocol 6 のキーコード文字列 <-> 16bit 値の変換
    #
    # layout.vil と同じ文字列表現（KC_A, LSFT(KC_2), LT1(KC_SPACE), TD(3), M7 など）を扱い、
    # Vial GUI の Keycode.serialize / deserialize と同じ結果になるようにしている。
    class Keycodes
      class UnknownKeycode < StandardError; end

      DATA_PATH = File.join(__dir__, 'via_keycodes.yaml')

      def initialize(custom_keycodes: [])
        data = YAML.load_file(DATA_PATH)
        @name_to_code = {}
        @code_to_name = {}
        data['codes'].each do |name, code|
          @name_to_code[name] = code
          @code_to_name[code] = name
        end
        @aliases = data['aliases'].dup
        # キーボード定義の customKeycodes（BT0 など）は USER00.. の別名
        custom_keycodes.each_with_index do |custom, i|
          @aliases[custom['name']] = format('USER%02d', i) if custom['name']
        end
        @const = data['constants']
        @masked = @name_to_code.select { |name, _| name.end_with?('(kc)') }.values.to_set
      end

      # 文字列（または整数）→ 16bit 値
      def encode(value)
        return value if value.is_a?(Integer)

        str = value.to_s.strip
        code = lookup_name(str)
        return code if code

        code = Expression.new(str, self).parse
        raise UnknownKeycode, "不明なキーコード: #{value}" unless code.between?(0, 0xFFFF)

        code
      rescue Expression::ParseError => e
        raise UnknownKeycode, "不明なキーコード: #{value} (#{e.message})"
      end

      # 16bit 値 → 文字列（Vial GUI と同じ表記）
      def decode(code)
        if @masked.include?(code & 0xFF00)
          outer = @code_to_name[code & 0xFF00]
          inner = @code_to_name[code & 0x00FF]
          return outer.sub('kc', inner) if outer && inner
        else
          name = @code_to_name[code]
          return name if name
        end
        format('0x%x', code)
      end

      # 名前・別名・定数を値に解決（関数形式は対象外）
      def lookup_name(name)
        return @name_to_code[name] if @name_to_code.key?(name) && !name.end_with?('(kc)')
        return @name_to_code[@aliases[name]] if @aliases.key?(name)
        return @const[name] if name.start_with?('MOD_')
        return Integer(name, 0) if name.match?(/\A(0x[0-9a-fA-F]+|\d+)\z/)

        nil
      end

      def const(name)
        @const.fetch(name)
      end

      # LSFT(KC_2) や LT(1, KC_A) などの式を評価する小さなパーサ（Vial GUI の AnyKeycode 相当）
      class Expression
        class ParseError < StandardError; end

        MOD_FUNCS = {
          'LCTL' => %w[QK_LCTL], 'LSFT' => %w[QK_LSFT], 'LALT' => %w[QK_LALT], 'LGUI' => %w[QK_LGUI],
          'RCTL' => %w[QK_RCTL], 'RSFT' => %w[QK_RSFT], 'RALT' => %w[QK_RALT], 'RGUI' => %w[QK_RGUI],
          'C_S' => %w[QK_LCTL QK_LSFT], 'HYPR' => %w[QK_LCTL QK_LSFT QK_LALT QK_LGUI],
          'MEH' => %w[QK_LCTL QK_LSFT QK_LALT], 'LCAG' => %w[QK_LCTL QK_LALT QK_LGUI],
          'SGUI' => %w[QK_LGUI QK_LSFT], 'LCA' => %w[QK_LCTL QK_LALT], 'LSA' => %w[QK_LSFT QK_LALT],
          'LAG' => %w[QK_LALT QK_LGUI], 'RSA' => %w[QK_RSFT QK_RALT], 'RCS' => %w[QK_RCTL QK_RSFT],
          'LCG' => %w[QK_LCTL QK_LGUI], 'RCG' => %w[QK_RCTL QK_RGUI]
        }.freeze
        MOD_FUNC_ALIASES = {
          'LOPT' => 'LALT', 'LCMD' => 'LGUI', 'LWIN' => 'LGUI', 'ALGR' => 'RALT', 'ROPT' => 'RALT',
          'RCMD' => 'RGUI', 'RWIN' => 'RGUI', 'SCMD' => 'SGUI', 'SWIN' => 'SGUI', 'LSG' => 'SGUI',
          'SAGR' => 'RSA', 'C' => 'LCTL', 'S' => 'LSFT', 'A' => 'LALT', 'G' => 'LGUI'
        }.freeze
        MOD_TAP_FUNCS = {
          'LCTL_T' => %w[MOD_LCTL], 'RCTL_T' => %w[MOD_RCTL], 'LSFT_T' => %w[MOD_LSFT], 'RSFT_T' => %w[MOD_RSFT],
          'LALT_T' => %w[MOD_LALT], 'RALT_T' => %w[MOD_RALT], 'LGUI_T' => %w[MOD_LGUI], 'RGUI_T' => %w[MOD_RGUI],
          'C_S_T' => %w[MOD_LCTL MOD_LSFT], 'MEH_T' => %w[MOD_LCTL MOD_LSFT MOD_LALT],
          'LCAG_T' => %w[MOD_LCTL MOD_LALT MOD_LGUI], 'RCAG_T' => %w[MOD_RCTL MOD_RALT MOD_RGUI],
          'HYPR_T' => %w[MOD_LCTL MOD_LSFT MOD_LALT MOD_LGUI], 'SGUI_T' => %w[MOD_LGUI MOD_LSFT],
          'LCA_T' => %w[MOD_LCTL MOD_LALT], 'LSA_T' => %w[MOD_LSFT MOD_LALT], 'LAG_T' => %w[MOD_LALT MOD_LGUI],
          'RSA_T' => %w[MOD_RSFT MOD_RALT], 'RCS_T' => %w[MOD_RCTL MOD_RSFT], 'LCG_T' => %w[MOD_LCTL MOD_LGUI],
          'RCG_T' => %w[MOD_RCTL MOD_RGUI]
        }.freeze
        MOD_TAP_ALIASES = {
          'CTL_T' => 'LCTL_T', 'SFT_T' => 'LSFT_T', 'LOPT_T' => 'LALT_T', 'ROPT_T' => 'RALT_T',
          'ALGR_T' => 'RALT_T', 'ALT_T' => 'LALT_T', 'OPT_T' => 'LALT_T', 'LCMD_T' => 'LGUI_T',
          'LWIN_T' => 'LGUI_T', 'RCMD_T' => 'RGUI_T', 'RWIN_T' => 'RGUI_T', 'GUI_T' => 'LGUI_T',
          'CMD_T' => 'LGUI_T', 'WIN_T' => 'LGUI_T', 'SCMD_T' => 'SGUI_T', 'SWIN_T' => 'SGUI_T',
          'LSG_T' => 'SGUI_T', 'SAGR_T' => 'RSA_T', 'ALL_T' => 'HYPR_T'
        }.freeze
        LAYER_FUNCS = {
          'TO' => 'QK_TO', 'MO' => 'QK_MOMENTARY', 'DF' => 'QK_DEF_LAYER', 'TG' => 'QK_TOGGLE_LAYER',
          'OSL' => 'QK_ONE_SHOT_LAYER', 'TT' => 'QK_LAYER_TAP_TOGGLE', 'PDF' => 'QK_PERSISTENT_DEF_LAYER',
          'TD' => 'QK_TAP_DANCE'
        }.freeze

        def initialize(str, keycodes)
          @tokens = str.scan(/0x[0-9a-fA-F]+|\d+|[A-Za-z_][A-Za-z0-9_]*|[(),|]|\S/)
          @pos = 0
          @kc = keycodes
        end

        def parse
          value = parse_or
          raise ParseError, "余分なトークン: #{peek}" if peek

          value
        end

        private

        def peek = @tokens[@pos]

        def take(expected = nil)
          token = @tokens[@pos]
          raise ParseError, "#{expected} が必要です" if token.nil? || (expected && token != expected)

          @pos += 1
          token
        end

        def parse_or
          value = parse_term
          while peek == '|'
            take('|')
            value |= parse_term
          end
          value
        end

        def parse_term
          token = take
          return Integer(token, 0) if token.match?(/\A(0x[0-9a-fA-F]+|\d+)\z/)
          raise ParseError, "不正なトークン: #{token}" unless token.match?(/\A[A-Za-z_]/)

          if peek == '('
            take('(')
            args = [parse_or]
            while peek == ','
              take(',')
              args << parse_or
            end
            take(')')
            call(token, args)
          else
            @kc.lookup_name(token) || raise(ParseError, "不明な名前: #{token}")
          end
        end

        def call(name, args)
          c = ->(n) { @kc.const(n) }
          name = MOD_FUNC_ALIASES.fetch(name, name)
          name = MOD_TAP_ALIASES.fetch(name, name)

          if MOD_FUNCS.key?(name)
            arity!(name, args, 1)
            MOD_FUNCS[name].map { |m| c.(m) }.reduce(:|) | args[0]
          elsif MOD_TAP_FUNCS.key?(name)
            arity!(name, args, 1)
            mod_tap(MOD_TAP_FUNCS[name].map { |m| c.(m) }.reduce(:|), args[0])
          elsif (m = name.match(/\ALT(\d+)\z/))
            arity!(name, args, 1)
            c.('QK_LAYER_TAP') | ((m[1].to_i & 0xF) << 8) | (args[0] & 0xFF)
          elsif name == 'LT'
            arity!(name, args, 2)
            c.('QK_LAYER_TAP') | ((args[0] & 0xF) << 8) | (args[1] & 0xFF)
          elsif name == 'MT'
            arity!(name, args, 2)
            mod_tap(args[0], args[1])
          elsif name == 'OSM'
            arity!(name, args, 1)
            c.('QK_ONE_SHOT_MOD') | (args[0] & 0xFF)
          elsif name == 'LM'
            arity!(name, args, 2)
            c.('QK_LAYER_MOD') | ((args[0] & 0xF) << c.('QMK_LM_SHIFT')) | (args[1] & c.('QMK_LM_MASK'))
          elsif name == 'TO'
            arity!(name, args, 1)
            c.('QK_TO') | (c.('ON_PRESS') << 4) | (args[0] & 0xFF)
          elsif LAYER_FUNCS.key?(name)
            arity!(name, args, 1)
            c.(LAYER_FUNCS[name]) | (args[0] & 0xFF)
          else
            raise ParseError, "不明な関数: #{name}"
          end
        end

        def mod_tap(mods, kc)
          @kc.const('QK_MOD_TAP') | ((mods & 0x1F) << 8) | (kc & 0xFF)
        end

        def arity!(name, args, n)
          raise ParseError, "#{name} の引数は #{n} 個です" unless args.size == n
        end
      end
    end
  end
end
