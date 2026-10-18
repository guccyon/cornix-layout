# frozen_string_literal: true

module Cornix
  module Domain
    # キーに割り当てる動作（16bit のキーコード 1 つ分）を表す値オブジェクトの族。
    #
    # 文字列（設定ファイルの表記、.vil の表記）や整数（デバイスの値）からの変換は
    # Mapping::KeycodeNotation / VialNotation / KeycodeCodec が一度だけ行い、
    # それ以降はこの値のまま扱う。名前（KC_A や別名）は持たず、名前はカタログから引く。
    #
    #   NoKey / Transparent              KC_NO / KC_TRNS
    #   Basic(code)                      0x04〜0xFF の基本キー
    #   Modified(mods, base)             LSFT(KC_1), SGUI(KC_4), Cmd + Shift + 4
    #   ModTap(mods, base)               LGUI_T(KC_LANG2)
    #   LayerTap(layer, base)            LT1(KC_SPACE)
    #   LayerAction(op, layer)           MO(3), TG(3), OSL(4), TO(1), DF(0), TT(2), PDF(0)
    #   LayerMod(layer, mods)            LM(1, MOD_LSFT)
    #   OneShotMod(mods)                 OSM(MOD_LSFT)
    #   MacroCall(index)                 M2
    #   TapDanceCall(index)              TD(4)
    #   Quantum(code)                    QK_BOOT, USER00 など名前付きの特殊キー
    #   Raw(code)                        解釈できない値（落とさずに往復させる）
    module Keycode
      # すべてのキーコードの値が include する目印
      module Value
        def keycode? = true
      end

      def self.keycode?(value) = value.is_a?(Value)

      def self.check!(value, what = 'キーコード')
        return value if keycode?(value)

        raise InvalidValue, "#{what}が不正です: #{value.inspect}"
      end
    end
  end
end
