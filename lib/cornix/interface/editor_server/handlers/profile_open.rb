# frozen_string_literal: true

require_relative '../handler'

module Cornix
  module Interface
    module EditorServer
      module Handlers
        # profile/open: プロファイルを開いて ProfileSnapshot を返す（protocol.md の 5.2）。
        # dir が分からなければ -32050。snapshot を作れなかったら、開いたものを閉じてからエラーにする
        class ProfileOpen < Handler
          rpc 'profile/open'

          def call(params, context)
            workbench = context.workbench
            opened = workbench.open(param(params, 'dir', String))
            begin
              Application::Editor::Snapshot.new(workbench).call(opened.id)
            rescue StandardError
              workbench.close(opened.id)
              raise
            end
          end
        end
      end
    end
  end
end
