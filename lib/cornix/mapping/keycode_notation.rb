# frozen_string_literal: true

module Cornix
  module Mapping
    # 設定ファイル（config/*.yaml）に書くキーコードの文字列 ⇄ Domain::Keycode。
    #
    # 受け付ける表記（parse）
    #   別名            Tab, Space, "!", ¥, LCtrl          （data/aliases.yaml）
    #   QMK / Vial 名   KC_TAB, KC_ENT, KC_EXLM, QK_BOOT    （data/keycodes.yaml の name / qmk）
    #   修飾関数        LSFT(KC_1), SGUI(4), LGUI(LSFT(Q)), HYPR(Left), LCS(A)
    #   ModTap          LGUI_T(KC_LANG2), MT(MOD_LCTL|MOD_LSFT, A), ALL_T(Esc)
    #   レイヤー        LT1(Space), LT(1, Space), MO(3), TG(3), TO(0), DF(0), OSL(4), TT(2), PDF(0), LM(1, MOD_LSFT)
    #   ワンショット    OSM(MOD_LSFT|MOD_LGUI)
    #   修飾キー式      Cmd + Shift + A, Command + Plus, Ctrl + "-"   （修飾名は Modifiers::EXPRESSION）
    #   参照            Macro('名前'), Macro(3), M3, TapDance('名前'), TapDance(2), TD(2)
    #   ショートカット  Shortcut('名前')                                   （shortcuts.yaml か data/shortcuts/ の定義の Keycode）
    #   生の値          0x7C00
    #
    # format の正規形（decompile が書く表記）は Formatter を参照。
    # 不変条件: parse(format(k, references:), references:) == k
    class KeycodeNotation
      def initialize(catalog: KeycodeCatalog.default, codec: KeycodeCodec.new(catalog))
        @catalog = catalog
        @codec = codec
        @parser = Parser.new(catalog: catalog, codec: codec)
        @formatter = Formatter.new(catalog: catalog, codec: codec)
      end

      attr_reader :catalog, :codec

      # 文字列 → Domain::Keycode。解釈できなければ UnknownKeycode（利用者向けのメッセージ）
      def parse(text, references: References::NONE)
        @parser.parse(text, references)
      end

      # Domain::Keycode → 文字列（正規形）
      def format(keycode, references: References::NONE)
        @formatter.format(keycode, references)
      end
    end
  end
end
