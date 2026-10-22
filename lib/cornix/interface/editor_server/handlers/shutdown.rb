# frozen_string_literal: true

require_relative '../handler'

module Cornix
  module Interface
    module EditorServer
      module Handlers
        # shutdown: 終わる準備。result は null。以降のリクエストは -32600 になる（状態はサーバーが持つ）
        class Shutdown < Handler
          rpc 'shutdown', servers: SERVERS

          def call(_params, _context) = nil
        end
      end
    end
  end
end
