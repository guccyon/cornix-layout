# frozen_string_literal: true

require_relative '../handler'

module Cornix
  module Interface
    module EditorServer
      module Handlers
        # workspace/didChangeFiles（通知）: 設定ディレクトリのファイルが変わった（protocol.md の 7.1）。
        # 中身が知っている版と違う開いているプロファイルごとに profile/didChange を送る（7.2）
        class WorkspaceDidChangeFiles < Handler
          notification 'workspace/didChangeFiles'

          TYPES = %w[created changed deleted].freeze

          def call(params, context)
            changes = param(params, 'changes', Array)
            paths = changes.each_with_index.map do |change, i|
              change = param(changes, i, Hash, field: "changes[#{i}]")
              type = param(change, 'type', String, field: "changes[#{i}].type")
              unless TYPES.include?(type)
                raise RpcError.new(ErrorCodes::INVALID_PARAMS, "params の changes[#{i}].type の形が違います",
                                   { field: "changes[#{i}].type" })
              end
              param(change, 'path', String, field: "changes[#{i}].path")
            end
            Application::Editor::FileChanges.new(context.workbench).call(paths).each do |notification|
              context.notify('profile/didChange', notification)
            end
            nil
          end
        end
      end
    end
  end
end
