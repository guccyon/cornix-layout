# frozen_string_literal: true

require_relative '../keycode_notation'
require_relative 'modifiers'

module Cornix
  module Mapping
    class KeycodeNotation
      # Domain::Keycode → 設定ファイルの正規形。
      #
      #   ショートカットの定義のちょうど 1 つと同じ値  Shortcut('名前')（references に利用者のショートカットがあるときだけ。同梱の定義は使わない）
      #   別名がある値            別名リストの先頭（catalog.preferred_alias）       Escape, "!", BT0
      #   別名のない基本・特殊キー keycodes.yaml の name                           KC_KP_0, QK_REBOOT, QK_LOCK
      #   別名のない Modified     修飾キー式（Ctrl, Option, Shift, Command の順）   Shift + Command + Enter
      #                           右側は RCtrl / ROption / RShift / RCommand        RCtrl + RShift + A
      #   ModTap                  正規名_T(キー)、正規名がなければ MT(MOD_..., キー)  LGUI_T(Lang2)
      #   LayerTap                LT<n>(キー)                                       LT1(Space)
      #   LayerAction             MO(n) / TG(n) / TO(n) / DF(n) / OSL(n) / TT(n) / PDF(n)
      #   LayerMod / OneShotMod   LM(n, MOD_LCTL|MOD_LSFT) / OSM(MOD_LSFT)
      #   MacroCall / TapDanceCall 名前があれば Macro('名前') / TapDance('名前')、なければ M2 / TD(4)
      #   Raw                     0xHHHH
      #
      # 関数の引数のキーも同じ規則（別名があれば別名）で書き、カンマ・括弧・引用符を含む別名は引用符で囲む（LCTL_T(',')）。
      class Formatter
        K = Domain::Keycode

        LAYER_OPS = {
          to: 'TO', momentary: 'MO', default: 'DF', toggle: 'TG',
          one_shot: 'OSL', tap_toggle: 'TT', persistent_default: 'PDF'
        }.freeze

        SPECIAL = /[,()'"]/

        def initialize(catalog:, codec:)
          @catalog = catalog
          @codec = codec
        end

        def format(keycode, references)
          shortcut = references.shortcut_name(keycode)
          return reference('Shortcut', shortcut) if shortcut

          case keycode
          when K::MacroCall then reference('Macro', references.macro_name(keycode.index)) || "M#{keycode.index}"
          when K::TapDanceCall then reference('TapDance', references.tap_dance_name(keycode.index)) || "TD(#{keycode.index})"
          when K::Raw then hex(keycode.code)
          when K::LayerTap then "LT#{keycode.layer.index}(#{arg(keycode.base)})"
          when K::LayerAction then "#{LAYER_OPS.fetch(keycode.op)}(#{keycode.layer.index})"
          when K::LayerMod then "LM(#{keycode.layer.index}, #{Modifiers.constants(keycode.mods)})"
          when K::OneShotMod then "OSM(#{Modifiers.constants(keycode.mods)})"
          when K::ModTap then mod_tap(keycode)
          when K::Modified then aliased(keycode) || "#{Modifiers.expression(keycode.mods)} + #{key(keycode.base)}"
          when K::NoKey, K::Transparent, K::Basic, K::Quantum then key(keycode)
          else raise UnknownKeycode, "キーコードではありません: #{keycode.inspect}"
          end
        end

        private

        # 別名か keycodes.yaml の name
        def key(keycode)
          code = @codec.encode(keycode)
          @catalog.preferred_alias(code) || @catalog.name(code) || hex(code)
        end

        # 関数の引数。カンマ・括弧・引用符を含む別名（",", "(" など）は引用符で囲む
        def arg(keycode)
          text = key(keycode)
          return text unless text.match?(SPECIAL)

          text.include?("'") ? "\"#{text}\"" : "'#{text}'"
        end

        def aliased(keycode) = @catalog.preferred_alias(@codec.encode(keycode))

        def mod_tap(keycode)
          name = Modifiers.mod_tap_name(keycode.mods)
          return "#{name}(#{arg(keycode.base)})" if name

          "MT(#{Modifiers.constants(keycode.mods)}, #{arg(keycode.base)})"
        end

        def reference(function, name)
          return nil if name.nil?

          "#{function}(#{quote(name)})"
        end

        # ' を含む名前は "..." で囲む。' と " の両方を含むときは '...' の中の ' を \' にする
        def quote(name)
          return "'#{name}'" unless name.include?("'")
          return "\"#{name}\"" unless name.include?('"')

          "'#{name.gsub("'", "\\\\'")}'"
        end

        def hex(code) = ::Kernel.format('0x%04X', code)
      end
    end
  end
end
