# frozen_string_literal: true

module Cornix
  module Application
    module Editor
      class Inspect
        # QMK の keymap.c に書く名前（マウスを載せたときの説明の最後の行。protocol.md の 5.5）。
        #
        #   QmkName.new(catalog:, codec:).call(keycode)   #=> "LT(1, KC_SPACE)"（QMK の名前にできない値は nil）
        #
        # 名前は QMK の公式の表（https://docs.qmk.fm/keycodes ）の「Key」の列の形に揃える（長い名前。KC_SPC ではなく KC_SPACE）。
        #   名前付きの値      data/keycodes.yaml のその値の name と qmk から、KC_ / QK_ で始まるものを優先して一番長いもの
        #                     （KC_BSPACE → KC_BACKSPACE、KC_TRNS → KC_TRANSPARENT、RGB_TOG → QK_UNDERGLOW_TOGGLE、
        #                     USER00 → QK_KB_0、LSFT(KC_1) → KC_EXCLAIM）。表の Vial 名には QMK で古くなった名前があるため。
        #                     USER32〜USER63 は Vial GUI だけの名前（QMK の QK_KB_ は 31 まで）なので nil
        #   修飾付き          LSFT(kc) / LCS(kc) / LSAG(kc) / MEH(kc) / HYPR(kc) / RCTL(kc) / RSG(kc) …（QMK に名前のない
        #                     右の Ctrl+Shift+Alt と 4 つ全部は 1 つずつ入れ子にする: RCTL(RSFT(RALT(kc)))）
        #   Mod-Tap           LCTL_T(kc) / LSG_T(kc) / MEH_T(kc) / HYPR_T(kc) …（名前のない組は MT(MOD_RCTL | MOD_RSFT | MOD_RALT, kc)）
        #   レイヤー操作      MO(1) / TG(1) / TO(1) / DF(0) / OSL(2) / TT(2) / PDF(0)、LT(1, kc)、LM(1, MOD_LSFT)
        #   OSM               OSM(MOD_LCTL | MOD_LSFT)（左の 3 つ・4 つは MOD_MEH / MOD_HYPR）
        #   タップダンス      TD(4)
        #   マクロ            QK_MACRO_0〜QK_MACRO_31（QMK に名前があるのは 31 まで。それより後は nil）
        #   Raw               nil
        class QmkName
          K = Domain::Keycode

          # 修飾の 1 文字（QMK の LCS(kc) / LSAG_T(kc) などの組の名前）と、1 つだけのときの名前（LCTL / RSFT …）
          LETTERS = { ctrl: 'C', shift: 'S', alt: 'A', gui: 'G' }.freeze
          SINGLE = { ctrl: 'CTL', shift: 'SFT', alt: 'ALT', gui: 'GUI' }.freeze
          MEH = %i[ctrl shift alt].freeze
          HYPR = %i[ctrl shift alt gui].freeze
          MACRO_NAMES = (0..31)
          OFFICIAL_PREFIX = /\A(KC|QK)_/
          VIAL_ONLY = /\AUSER\d+\z/

          def initialize(catalog:, codec:)
            @catalog = catalog
            @codec = codec
          end

          def call(keycode)
            named(@codec.encode(keycode)) || composed(keycode)
          end

          private

          def composed(keycode)
            case keycode
            when K::Modified then mod_function(keycode.mods, base(keycode))
            when K::ModTap then mod_tap(keycode.mods, base(keycode))
            when K::LayerTap then "LT(#{keycode.layer.index}, #{base(keycode)})"
            when K::LayerMod then "LM(#{keycode.layer.index}, #{mod_mask(keycode.mods)})"
            when K::LayerAction then "#{Mapping::VialNotation::LAYER_FUNCTIONS.fetch(keycode.op)}(#{keycode.layer.index})"
            when K::OneShotMod then "OSM(#{mod_mask(keycode.mods)})"
            when K::TapDanceCall then "TD(#{keycode.index})"
            when K::MacroCall then ("QK_MACRO_#{keycode.index}" if MACRO_NAMES.cover?(keycode.index))
            end
          end

          def named(code)
            names = @catalog.names_for(code)
            return nil if names.empty?

            # 同じ長さなら qmk（表の後ろ）を優先する（USER00 と QK_KB_0 など）
            name = names.each_with_index.max_by { |n, i| [n.match?(OFFICIAL_PREFIX) ? 1 : 0, n.length, i] }.first
            name unless name.match?(VIAL_ONLY)
          end

          def base(keycode) = named(keycode.base.code)

          def side(mods) = mods.right? ? 'R' : 'L'

          # 修飾関数の名前（QMK に名前のない組は nil）
          def mod_name(mods)
            return 'MEH' if !mods.right? && mods.mods == MEH
            return 'HYPR' if !mods.right? && mods.mods == HYPR
            return side(mods) + SINGLE.fetch(mods.mods.first) if mods.mods.size == 1
            return nil if mods.mods.size == 4 || mods.mods == MEH

            side(mods) + mods.mods.map { |m| LETTERS.fetch(m) }.join
          end

          def mod_function(mods, inner)
            if (name = mod_name(mods)) then "#{name}(#{inner})"
            else mods.mods.reverse.reduce(inner) { |acc, m| "#{side(mods)}#{SINGLE.fetch(m)}(#{acc})" }
            end
          end

          def mod_tap(mods, inner)
            (name = mod_name(mods)) ? "#{name}_T(#{inner})" : "MT(#{mod_mask(mods)}, #{inner})"
          end

          # MOD_LCTL | MOD_LSFT のような mods の式（左の 3 つ・4 つは QMK の MOD_MEH / MOD_HYPR）
          def mod_mask(mods)
            return 'MOD_MEH' if !mods.right? && mods.mods == MEH
            return 'MOD_HYPR' if !mods.right? && mods.mods == HYPR

            mods.mods.map { |m| "MOD_#{side(mods)}#{SINGLE.fetch(m)}" }.join(' | ')
          end
        end
      end
    end
  end
end
