# frozen_string_literal: true

require_relative '../handler'
require_relative 'draft_params'

module Cornix
  module Interface
    module EditorServer
      module Handlers
        # profile/planEdits: 未保存の変更をファイルの書き換え（範囲と文字）にする（protocol.md の 6.1）
        class ProfilePlanEdits < Handler
          include DraftParams

          rpc 'profile/planEdits'

          def call(params, context)
            draft_call(params) do |id, base_versions, changes|
              Application::Editor::PlanEdits.new(context.workbench).call(id, base_versions: base_versions, changes: changes)
            end
          end
        end
      end
    end
  end
end
