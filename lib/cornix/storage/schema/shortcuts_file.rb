# frozen_string_literal: true

module Cornix
  module Storage
    module Schema
      # shortcuts.yaml（名前付きショートカット。任意。定義がなければファイルを作らない）
      #
      #   shortcuts:
      #     前のタブへ: Command + Shift + [
      #     ウインドウを左半分に: Ctrl + Option + Left
      #
      # 値にはキーコードの書き方なら何でも書ける（Macro('名前') も可）。ただし Shortcut(...) は書けない。
      # 解釈できない定義は問題を記録して除く（ほかの定義への参照まで「定義されていません」にしないため）
      module ShortcutsFile
        SELF_REFERENCE = /\bShortcut\s*\(/

        module_function

        def read(data, ctx, keycodes)
          hash = ctx.mapping(data, '', required: ['shortcuts'], allowed: ['shortcuts']) or return nil
          raw = hash['shortcuts']
          return Domain::ShortcutLibrary::EMPTY if raw.nil?

          entries = ctx.mapping(raw, 'shortcuts', key_label: 'ショートカットの名前') or return nil
          values = entries.filter_map do |name, value|
            next unless name.is_a?(String)

            keycode = read_value(value, ctx, keycodes, "shortcuts.#{name}")
            [name, keycode] if keycode
          end
          ctx.build('shortcuts') { Domain::ShortcutLibrary.new(entries: values.to_h) }
        end

        def read_value(value, ctx, keycodes, loc)
          if value.is_a?(String) && value.strip.match?(SELF_REFERENCE)
            return ctx.problem(loc, "shortcuts.yaml の値には Shortcut(...) は書けません: #{value}")
          end

          keycodes.read(value, ctx, loc)
        end

        # existing は既存の shortcuts.yaml の内容。同じキーコードを表す値はその書き方のまま残す
        def write(library, keycodes, existing)
          old = existing.is_a?(Hash) && existing['shortcuts'].is_a?(Hash) ? existing['shortcuts'] : {}
          { 'shortcuts' => library.entries.to_h { |name, kc| [name, write_value(kc, keycodes, old[name])] } }
        end

        # 整数（YAML の 0x0A2F）は 16 進の書き方が読み込みで失われるので残さず、正規形で書く
        def write_value(keycode, keycodes, old)
          return old if old.is_a?(String) && keycodes.read(old, Context.new(nil, Problems.new), '') == keycode

          keycodes.write(keycode)
        end
      end
    end
  end
end
