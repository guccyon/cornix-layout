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
      #
      # 欄（context。protocol.md の 5.3・12.4）によって読める名前参照が違う（Storage::ConfigLoader と同じ）
      #   macroKey       マクロの手順のキー。名前参照を読まない（Macro(2) / M2 は読めるが Macro('名前') と Shortcut(...) は読めない）
      #   shortcutValue  shortcuts.yaml の値。Macro('名前') / TapDance('名前') は読めるが Shortcut(...) は書けない（読み込みと同じ文の問題）
      #   そのほか       すべての名前参照
      # parse と build の context: を省けば「そのほか」。canonical もその欄の名前参照で書く（macroKey なら M2）
      class KeyValues
        MACRO_KEY = 'macroKey'
        SHORTCUT_VALUE = 'shortcutValue'

        attr_reader :references, :layer_names

        def initialize(env:, profile:, icons: Mapping::AppIconCatalog.default)
          @notation = env.notation
          @codec = env.codec
          @icons = icons
          @display = Mapping::KeyDisplay.new(catalog: env.catalog, notation: env.notation)
          @profile = profile
          @references = build_references(env, profile)
          @unshortcut_references = build_unshortcut_references(env, profile)
          @layer_names = profile ? profile.layers.to_h { |layer| [layer.index, layer.name] }.freeze : {}.freeze
        end

        def parse(text, context: nil)
          if context == SHORTCUT_VALUE && text.is_a?(String) &&
             text.strip.match?(Storage::Schema::ShortcutsFile::SELF_REFERENCE)
            raise UnknownKeycode, "shortcuts.yaml の値には Shortcut(...) は書けません: #{text}"
          end

          @notation.parse(text, references: references_for(context))
        end

        # その欄で表記を読み書きする名前参照
        def references_for(context)
          case context
          when MACRO_KEY then Mapping::References::NONE
          when SHORTCUT_VALUE then @unshortcut_references
          else @references
          end
        end

        # その欄の候補に出す名前（マクロ・タップダンス・ショートカット）の一覧。マクロの手順のキーでも名前は候補に出し、
        # 表記は references_for の形（M2）にする。Shortcut(...) を読めない欄ではショートカットを出さない
        def listing_references(context) = context == MACRO_KEY ? @unshortcut_references : references_for(context)

        # text はファイルに書いてある表記（ないときは呼び出し側が canonical を渡す）
        def build(keycode, text:, note: nil, context: nil)
          origin, icon = origin_of(keycode, text)
          {
            text: text, canonical: canonical(keycode, context: context), code: @codec.encode(keycode),
            kind: @display.kind(keycode),
            origin: origin,
            display: display_of(keycode),
            icon: icon, note: note
          }.compact
        end

        def canonical(keycode, context: nil) = @notation.format(keycode, references: references_for(context))

        def code(keycode) = @codec.encode(keycode)

        # 名前参照を使わない表記（Shortcut の中身、LT / MT のタップ側の説明、references.shortcuts の text の代わりに使う）
        def plain(keycode) = @notation.format(keycode)

        def label(keycode) = @display.display(keycode, references: @references)[:label]

        # preset: のマクロの元のアプリのアイコン（preset でなければ nil）
        def macro_icon(macro) = macro&.preset ? app_icon(macro.preset) : nil

        # 同梱のショートカットの名前（"アプリ:カテゴリ:ラベル"）→ アプリのアイコン
        def app_icon(name) = @icons.icon(name.to_s.split(Mapping::ShortcutCatalog::SEPARATOR).first)

        # Shortcut('名前') で書いた表記なら名前。そうでなければ nil
        def shortcut_name(text) = @notation.shortcut_name(text)

        # 自分のショートカット（shortcuts.yaml）の名前か
        def user_shortcut?(name) = @references.shortcut_names.include?(name)

        private

        def display_of(keycode)
          shown = @display.display(keycode, references: @references).compact
          actions = tap_dance_actions(keycode)
          actions.empty? ? shown : shown.merge(actions: actions)
        end

        def tap_dance_actions(keycode)
          return [] unless keycode.is_a?(Domain::Keycode::TapDanceCall)

          tap_dance = @profile&.tap_dance(keycode.index)
          tap_dance ? @display.tap_dance_actions(tap_dance, references: @references) : []
        end

        def build_references(env, profile)
          presets = { preset_shortcuts: env.shortcut_catalog.library(env.notation).entries,
                      preset_macros: env.shortcut_catalog.macro_names }
          return Mapping::References.new(shortcuts: {}, **presets) unless profile

          Mapping::References.new(**profile.references, **presets)
        end

        # shortcuts.yaml の値を読む名前参照（Storage::ConfigLoader#build_references の shortcuts なしと同じ）
        def build_unshortcut_references(env, profile)
          names = profile ? profile.references.slice(:macros, :tap_dances) : {}
          Mapping::References.new(**names, preset_macros: env.shortcut_catalog.macro_names)
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
