# frozen_string_literal: true

require_relative '../vial_notation'
require_relative '../keycode_codec'

module Cornix
  module Mapping
    class VialNotation
      # .vil のキーコード式（LSFT(KC_2), LT(1, KC_A), OSM(MOD_LCTL|MOD_LSFT), KC_A|0x200 など）を
      # 16bit 値に評価する小さなパーサ。Vial GUI の AnyKeycode と同じ計算をする。
      #
      # 旧 Device::Keycodes との違い: TO(n) は Vial の表と同じ 0x5200 + n にする
      # （旧実装は表にない書き方のときだけ ON_PRESS (0x10) を足していた）。
      class Expression
        class ParseError < StandardError; end

        TOKEN = /0x[0-9a-fA-F]+|\d+|[A-Za-z_][A-Za-z0-9_]*|[(),|]|\S/

        # 修飾関数名 → 上位バイトのビット
        MOD_FUNCTIONS = {
          'LCTL' => 0x01, 'LSFT' => 0x02, 'LALT' => 0x04, 'LGUI' => 0x08,
          'RCTL' => 0x11, 'RSFT' => 0x12, 'RALT' => 0x14, 'RGUI' => 0x18,
          'C_S' => 0x03, 'HYPR' => 0x0F, 'MEH' => 0x07, 'LCAG' => 0x0D, 'SGUI' => 0x0A,
          'LCA' => 0x05, 'LSA' => 0x06, 'LAG' => 0x0C, 'RSA' => 0x16, 'RCS' => 0x13,
          'LCG' => 0x09, 'RCG' => 0x19
        }.freeze
        MOD_FUNCTION_ALIASES = {
          'LOPT' => 'LALT', 'LCMD' => 'LGUI', 'LWIN' => 'LGUI', 'ALGR' => 'RALT', 'ROPT' => 'RALT',
          'RCMD' => 'RGUI', 'RWIN' => 'RGUI', 'SCMD' => 'SGUI', 'SWIN' => 'SGUI', 'LSG' => 'SGUI',
          'SAGR' => 'RSA', 'C' => 'LCTL', 'S' => 'LSFT', 'A' => 'LALT', 'G' => 'LGUI'
        }.freeze
        MOD_TAP_FUNCTIONS = {
          'LCTL_T' => 0x01, 'RCTL_T' => 0x11, 'LSFT_T' => 0x02, 'RSFT_T' => 0x12,
          'LALT_T' => 0x04, 'RALT_T' => 0x14, 'LGUI_T' => 0x08, 'RGUI_T' => 0x18,
          'C_S_T' => 0x03, 'MEH_T' => 0x07, 'LCAG_T' => 0x0D, 'RCAG_T' => 0x1D,
          'HYPR_T' => 0x0F, 'SGUI_T' => 0x0A, 'LCA_T' => 0x05, 'LSA_T' => 0x06, 'LAG_T' => 0x0C,
          'RSA_T' => 0x16, 'RCS_T' => 0x13, 'LCG_T' => 0x09, 'RCG_T' => 0x19
        }.freeze
        MOD_TAP_ALIASES = {
          'CTL_T' => 'LCTL_T', 'SFT_T' => 'LSFT_T', 'LOPT_T' => 'LALT_T', 'ROPT_T' => 'RALT_T',
          'ALGR_T' => 'RALT_T', 'ALT_T' => 'LALT_T', 'OPT_T' => 'LALT_T', 'LCMD_T' => 'LGUI_T',
          'LWIN_T' => 'LGUI_T', 'RCMD_T' => 'RGUI_T', 'RWIN_T' => 'RGUI_T', 'GUI_T' => 'LGUI_T',
          'CMD_T' => 'LGUI_T', 'WIN_T' => 'LGUI_T', 'SCMD_T' => 'SGUI_T', 'SWIN_T' => 'SGUI_T',
          'LSG_T' => 'SGUI_T', 'SAGR_T' => 'RSA_T', 'ALL_T' => 'HYPR_T'
        }.freeze
        LAYER_FUNCTIONS = {
          'TO' => KeycodeCodec::LAYER_OPS[:to],
          'MO' => KeycodeCodec::LAYER_OPS[:momentary],
          'DF' => KeycodeCodec::LAYER_OPS[:default],
          'TG' => KeycodeCodec::LAYER_OPS[:toggle],
          'OSL' => KeycodeCodec::LAYER_OPS[:one_shot],
          'TT' => KeycodeCodec::LAYER_OPS[:tap_toggle],
          'PDF' => KeycodeCodec::LAYER_OPS[:persistent_default],
          'TD' => KeycodeCodec::TAP_DANCE.begin
        }.freeze

        LM_SHIFT = 5
        LM_MASK = 0x1F

        def initialize(text, notation)
          @tokens = text.scan(TOKEN)
          @pos = 0
          @notation = notation
        end

        def evaluate
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
          return @notation.lookup(token) || raise(ParseError, "不明な名前: #{token}") unless peek == '('

          take('(')
          args = [parse_or]
          while peek == ','
            take(',')
            args << parse_or
          end
          take(')')
          call(token, args)
        end

        def call(name, args)
          name = MOD_FUNCTION_ALIASES.fetch(name, name)
          name = MOD_TAP_ALIASES.fetch(name, name)

          if (bits = MOD_FUNCTIONS[name])
            arity!(name, args, 1)
            (bits << 8) | args[0]
          elsif (bits = MOD_TAP_FUNCTIONS[name])
            arity!(name, args, 1)
            mod_tap(bits, args[0])
          elsif (m = name.match(/\ALT(\d+)\z/))
            arity!(name, args, 1)
            KeycodeCodec::LAYER_TAP.begin | ((m[1].to_i & 0xF) << 8) | (args[0] & 0xFF)
          elsif name == 'LT'
            arity!(name, args, 2)
            KeycodeCodec::LAYER_TAP.begin | ((args[0] & 0xF) << 8) | (args[1] & 0xFF)
          elsif name == 'MT'
            arity!(name, args, 2)
            mod_tap(args[0], args[1])
          elsif name == 'OSM'
            arity!(name, args, 1)
            KeycodeCodec::ONE_SHOT_MOD.begin | (args[0] & 0xFF)
          elsif name == 'LM'
            arity!(name, args, 2)
            KeycodeCodec::LAYER_MOD.begin | ((args[0] & 0xF) << LM_SHIFT) | (args[1] & LM_MASK)
          elsif name == 'TO'
            arity!(name, args, 1)
            KeycodeCodec::LAYER_OPS[:to] | (args[0] & 0x1F)
          elsif (base = LAYER_FUNCTIONS[name])
            arity!(name, args, 1)
            base | (args[0] & 0xFF)
          else
            raise ParseError, "不明な関数: #{name}"
          end
        end

        def mod_tap(mods, key)
          KeycodeCodec::MOD_TAP.begin | ((mods & 0x1F) << 8) | (key & 0xFF)
        end

        def arity!(name, args, count)
          raise ParseError, "#{name} の引数は #{count} 個です" unless args.size == count
        end
      end
    end
  end
end
