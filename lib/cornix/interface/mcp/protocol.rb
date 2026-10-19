# frozen_string_literal: true

require 'json'

module Cornix
  module Interface
    module Mcp
      # MCP（JSON-RPC 2.0、stdio で 1 行 1 メッセージ）の定数と書き出し
      module Protocol
        PROTOCOL_VERSION = '2025-06-18'
        SERVER_INFO = { name: 'cornix-device', version: Cornix::VERSION }.freeze

        PARSE_ERROR = -32_700
        METHOD_NOT_FOUND = -32_601

        module_function

        # 非 ASCII 文字は \uXXXX にエスケープし、クライアント側のロケールに関係なく読めるようにする
        def dump(message) = JSON.generate(message, ascii_only: true)

        def result(id, result) = { jsonrpc: '2.0', id: id, result: result }

        def error(id, code, message) = { jsonrpc: '2.0', id: id, error: { code: code, message: message } }
      end
    end
  end
end
