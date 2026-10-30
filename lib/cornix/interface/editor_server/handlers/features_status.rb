# frozen_string_literal: true

require_relative '../handler'

module Cornix
  module Interface
    module EditorServer
      module Handlers
        # features/status: 解放されている機能の名前の一覧
        class FeaturesStatus < Handler
          rpc 'features/status'

          def call(_params, _context) = { unlocked: Application::Editor::UnlockedFeatures.new.call }
        end
      end
    end
  end
end
