# frozen_string_literal: true

require_relative '../handler'
require_relative 'draft_params'

module Cornix
  module Interface
    module EditorServer
      module Handlers
        # profile/validate: 未保存の変更を当てた状態でプロファイル全体を検証する（protocol.md の 5.6）。
        # params と失敗の code は profile/planEdits と同じ（DraftParams）
        class ProfileValidate < Handler
          include DraftParams

          rpc 'profile/validate'

          def call(params, context)
            draft_call(params) do |id, base_versions, changes|
              Application::Editor::ValidateDraft.new(context.workbench).call(id, base_versions: base_versions, changes: changes)
            end
          end
        end
      end
    end
  end
end
