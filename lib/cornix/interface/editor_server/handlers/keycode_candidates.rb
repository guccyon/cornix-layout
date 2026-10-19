# frozen_string_literal: true

require_relative '../handler'

module Cornix
  module Interface
    module EditorServer
      module Handlers
        # keycode/candidates: キー入力欄の候補（protocol.md の 5.3）。query は省けば ""、limit は省けば 50。
        # 知らない context は -32602（data: { field: "context" }）
        class KeycodeCandidates < Handler
          rpc 'keycode/candidates'

          def call(params, context)
            Application::Editor::Candidates.new(context.workbench).call(
              param(params, 'profileId', String),
              context: param(params, 'context', String),
              query: param(params, 'query', String, optional: true) || '',
              limit: param(params, 'limit', Integer, optional: true)
            )
          rescue Application::Editor::UnknownContext => e
            raise RpcError.new(ErrorCodes::INVALID_PARAMS, e.message, { field: 'context' })
          end
        end
      end
    end
  end
end
