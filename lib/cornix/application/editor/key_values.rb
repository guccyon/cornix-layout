# frozen_string_literal: true

module Cornix
  module Application
    module Editor
      # 割り当て 1 つの解釈（protocol.md の KeyValue）を作る。profile/open・keycode/candidates の typed・keycode/inspect で共通。
      #
      #   values = KeyValues.new(env:, profile:)            # profile は読めなければ nil（キーの表と同梱のショートカットだけで読む）
      #   keycode = values.parse("Macro('Bracket Pair')")  # 読めなければ Cornix::UnknownKeycode
      #   values.build(keycode, text: "Macro('Bracket Pair')", note: nil)
      #   #=> { text:, canonical:, code:, kind:, origin:, display: { label:, tap:, hold:, actions: }, icon:, note: }（nil の項目は省く）
      #
      # display の actions はタップダンス（プロファイルに定義があるもの）の割り当てのある動作（KeyDisplay#tap_dance_actions）。
      # 定義がない・どの動作も NoKey なら省く
      #
      # origin と icon（spec.md の「アイコン」）
      #   Shortcut('名前') で書いたもの   自分のショートカット（shortcuts.yaml）なら origin: "shortcut"（アイコンなし）、
      #                                    同梱のショートカットなら origin: "presetShortcut" と元のアプリのアイコン
      #   preset: のマクロを指すもの      origin: "presetMacro" と preset の元のアプリのアイコン（Macro(n) で書いても同じ）
      # Shortcut(...) で書いたかは KeycodeNotation#shortcut_name で見分ける（parse と同じ読み方）。
      # canonical は decompile の正規形（そのプロファイルの名前参照を使う）
      class KeyValues
        attr_reader :references, :layer_names

        def initialize(env:, profile:, icons: Mapping::AppIconCatalog.default)
          @notation = env.notation
          @codec = env.codec
          @icons = icons
          @display = Mapping::KeyDisplay.new(catalog: env.catalog, notation: env.notation)
          @profile = profile
          @references = build_references(env, profile)
          @layer_names = profile ? profile.layers.to_h { |layer| [layer.index, layer.name] }.freeze : {}.freeze
        end

        def parse(text) = @notation.parse(text, references: @references)

        # text はファイルに書いてある表記（ないときは呼び出し側が canonical を渡す）
        def build(keycode, text:, note: nil)
          origin, icon = origin_of(keycode, text)
          {
            text: text, canonical: canonical(keycode), code: @codec.encode(keycode), kind: @display.kind(keycode),
            origin: origin,
            display: display(keycode),
            icon: icon, note: note
          }.compact
        end

        def canonical(keycode) = @notation.format(keycode, references: @references)

        # 名前参照を使わない表記（Shortcut の中身、LT / MT のタップ側の説明、references.shortcuts の text の代わりに使う）
        def plain(keycode) = @notation.format(keycode)

        def label(keycode) = @display.display(keycode, references: @references, layer_names: @layer_names)[:label]

        # preset: のマクロの元のアプリのアイコン（preset でなければ nil）
        def macro_icon(macro) = macro&.preset ? app_icon(macro.preset) : nil

        # 同梱のショートカットの名前（"アプリ:カテゴリ:ラベル"）→ アプリのアイコン
        def app_icon(name) = @icons.icon(name.to_s.split(Mapping::ShortcutCatalog::SEPARATOR).first)

        # Shortcut('名前') で書いた表記なら名前。そうでなければ nil
        def shortcut_name(text) = @notation.shortcut_name(text)

        # 自分のショートカット（shortcuts.yaml）の名前か
        def user_shortcut?(name) = @references.shortcut_names.include?(name)

        private

        def display(keycode)
          shown = @display.display(keycode, references: @references, layer_names: @layer_names).compact
          actions = tap_dance_actions(keycode)
          actions.empty? ? shown : shown.merge(actions: actions)
        end

        def tap_dance_actions(keycode)
          return [] unless keycode.is_a?(Domain::Keycode::TapDanceCall)

          tap_dance = @profile&.tap_dance(keycode.index)
          tap_dance ? @display.tap_dance_actions(tap_dance, references: @references, layer_names: @layer_names) : []
        end

        def build_references(env, profile)
          presets = { preset_shortcuts: env.shortcut_catalog.library(env.notation).entries,
                      preset_macros: env.shortcut_catalog.macro_names }
          return Mapping::References.new(shortcuts: {}, **presets) unless profile

          Mapping::References.new(**profile.references, **presets)
        end

        def origin_of(keycode, text)
          if (name = shortcut_name(text))
            return ['shortcut', nil] if user_shortcut?(name)

            return ['presetShortcut', app_icon(name)]
          end
          return [nil, nil] unless keycode.is_a?(Domain::Keycode::MacroCall)

          macro = @profile&.macro(keycode.index)
          macro&.preset ? ['presetMacro', macro_icon(macro)] : [nil, nil]
        end
      end
    end
  end
end
