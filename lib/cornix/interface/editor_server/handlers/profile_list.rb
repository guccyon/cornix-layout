# frozen_string_literal: true

require_relative '../handler'

module Cornix
  module Interface
    module EditorServer
      module Handlers
        # profile/list: ワークスペースのプロファイルの一覧と既定（protocol.md の 5.1）
        class ProfileList < Handler
          rpc 'profile/list'

          def call(_params, context) = Application::Editor::ListProfiles.new(root: context.workbench.root).call
        end
      end
    end
  end
end
