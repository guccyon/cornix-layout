# frozen_string_literal: true

require_relative '../handler'

module Cornix
  module Interface
    module EditorServer
      module Handlers
        # $/cancelRequest（通知）: 受け付けるが、リクエストは届いた順に 1 つずつ処理するので v0.1 では何もしない
        class CancelRequest < Handler
          notification '$/cancelRequest'

          def call(_params, _context) = nil
        end
      end
    end
  end
end
