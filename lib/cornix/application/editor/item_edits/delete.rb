# frozen_string_literal: true

require_relative 'operation'

module Cornix
  module Application
    module Editor
      class ItemEdits
        # 項目を消す（protocol.md の 12.5 の delete）。参照は書き換えず、壊れる参照の場所を references に返す。
        #
        # マクロ・タップダンス・コンボ: そのファイルを消す。references は、そのマクロ・タップダンスを指す欄
        #   （名前でも番号でも、Shortcut(...) を通してでも、16bit 値がその M(n) / TD(n) になるもの。shortcuts.yaml の値も）。
        #   コンボは参照されないので []
        # ショートカット: shortcuts.yaml のその行を消す。references は Shortcut('名前') と書いた欄
        #   （同梱のショートカットに同じ名前があれば、消してもそちらを指すだけなので []）
        class Delete < Operation
          CALLS = { 'macro' => Domain::Keycode::MacroCall, 'tapDance' => Domain::Keycode::TapDanceCall }.freeze

          private

          def run(edit)
            return delete_shortcut(edit) if edit.kind == 'shortcut'

            kind = kind_of(edit)
            item, file = find_item(kind, edit.name)
            changeset.delete(file)
            outcome(references: references_to(edit.kind, item, file))
          end

          # 消すファイルの中の欄（タップダンスが自分を指すなど）は、ファイルごとなくなるので入れない
          def references_to(kind, item, file)
            call = CALLS[kind] or return []

            slots.select { |slot| slot.address[:file] != file && slot.keycode.is_a?(call) && slot.keycode.index == item.index }
                 .map(&:address)
          end

          def delete_shortcut(edit)
            require_shortcut!(edit.name)
            edit_file(reading.shortcuts_file) { |text| YamlKeys.new(text).remove_entry(['shortcuts', edit.name]) }
            bundled = env.shortcut_catalog.library(env.notation).entries.key?(edit.name)
            outcome(references: bundled ? [] : text_references('Shortcut', edit.name))
          end
        end
      end
    end
  end
end
