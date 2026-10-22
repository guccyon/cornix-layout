# frozen_string_literal: true

require_relative '../handler'

module Cornix
  module Interface
    module EditorServer
      module Handlers
        # $/cancelRequest（通知）: 受け付けるが、リクエストは届いた順に 1 つずつ処理するので何もしない。
        # device のサーバーで読む間に届いたものは、サーバーが処理の途中で先に拾う（Server#progress。ここには来ない）
        class CancelRequest < Handler
          notification '$/cancelRequest', servers: SERVERS

          def call(_params, _context) = nil
        end
      end
    end
  end
end
