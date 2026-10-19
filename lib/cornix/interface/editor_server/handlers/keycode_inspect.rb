# frozen_string_literal: true

require_relative '../handler'

module Cornix
  module Interface
    module EditorServer
      module Handlers
        # keycode/inspect: 1 つの表記の解釈・説明・その欄だけの検証（protocol.md の 5.5）。
        # 読めない表記はエラーにせず value: null と diagnostics で返す。知らない context は -32602（data: { field: "context" }）
        class KeycodeInspect < Handler
          rpc 'keycode/inspect'

          def call(params, context)
            Application::Editor::Inspect.new(context.workbench).call(
              param(params, 'profileId', String),
              context: param(params, 'context', String),
              text: param(params, 'text', String)
            )
          rescue Application::Editor::Candidates::UnknownContext => e
            raise RpcError.new(ErrorCodes::INVALID_PARAMS, e.message, { field: 'context' })
          end
        end
      end
    end
  end
end
