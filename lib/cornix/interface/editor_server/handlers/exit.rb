# frozen_string_literal: true

require_relative '../handler'

module Cornix
  module Interface
    module EditorServer
      module Handlers
        # exit（通知）: プロセスを終える。サーバーの run がここで戻る（終了コードは shutdown を受けていれば 0）
        class Exit < Handler
          notification 'exit'

          def call(_params, _context) = nil
        end
      end
    end
  end
end
