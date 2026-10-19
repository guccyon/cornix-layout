# frozen_string_literal: true

require_relative '../handler'

module Cornix
  module Interface
    module EditorServer
      module Handlers
        # keycode/shortcutTree: 同梱のショートカットの「アプリ → カテゴリ → ラベル」の木（protocol.md の 5.4）。
        # 中身はプロファイルによらない（params は見ない）
        class KeycodeShortcutTree < Handler
          rpc 'keycode/shortcutTree'

          def call(_params, context) = Application::Editor::Candidates.new(context.workbench).shortcut_tree
        end
      end
    end
  end
end
