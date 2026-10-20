# frozen_string_literal: true

require_relative '../handler'

module Cornix
  module Interface
    module EditorServer
      module Handlers
        # profile/close（通知）: 開いたプロファイルを閉じる。知らない profileId でも何もしない
        class ProfileClose < Handler
          notification 'profile/close'

          def call(params, context)
            context.workbench.close(param(params, 'profileId', String))
            nil
          end
        end
      end
    end
  end
end
