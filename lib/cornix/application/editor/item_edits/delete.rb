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
        # レイヤー（v0.4。issue #84）: file（省けば name）のレイヤーのファイルを消す。references は、そのレイヤーを指すレイヤー操作（MO / TG / TO / OSL / LT / LM など。
        #   16bit 値で数える。Domain::Keycode.layer_index）の欄。compile ではそのレイヤーは KC_NO で埋まる（#83）
        # ショートカット: shortcuts.yaml のその行を消す。references は Shortcut('名前') と書いた欄
        #   （同梱のショートカットに同じ名前があれば、消してもそちらを指すだけなので []）
        class Delete < Operation
          private

          def run(edit)
            return delete_shortcut(edit) if edit.kind == 'shortcut'

            kind = kind_of(edit)
            item, file = find_item(kind, edit.name, file: edit.file)
            changeset.delete(file)
            # 消すファイルの中の欄（タップダンスが自分を指すなど）は、ファイルごとなくなるので入れない
            outcome(references: item_references(edit.kind, item, file))
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
