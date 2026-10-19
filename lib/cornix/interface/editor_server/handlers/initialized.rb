# frozen_string_literal: true

require_relative '../handler'

module Cornix
  module Interface
    module EditorServer
      module Handlers
        # initialized（通知）: 拡張の準備ができた。v0.1 では何もしない
        class Initialized < Handler
          notification 'initialized'

          def call(_params, _context) = nil
        end
      end
    end
  end
end
