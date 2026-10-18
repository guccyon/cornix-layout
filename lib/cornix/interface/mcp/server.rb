# frozen_string_literal: true

require 'json'
require_relative 'protocol'
require_relative 'tool_catalog'
require_relative 'tools'
require_relative '../use_cases'

module Cornix
  module Interface
    module Mcp
      # Cornix キーボードを直接操作する MCP サーバー（stdio, JSON-RPC 2.0, 改行区切り。旧 Device::McpServer）。
      #
      # 書き込みは apply_layout と restore_backup だけで、必ず dry run で差分と確認トークンを受け取り、
      # ユーザーの確認を得たうえでそのトークンを付けて呼ぶ二段階方式にしている。
      #
      #   Server.new(env).run
      #   Server.new(env, input:, output:, use_cases: { device_info: ->(env) { stub } })   # テスト
      class Server
        def initialize(env, input: $stdin, output: $stdout, use_cases: nil)
          @env = env
          @input = input
          @output = output
          @tools = Tools.new(env, UseCases.build(use_cases))
        end

        def run
          # LANG 未設定（US-ASCII ロケール）でも日本語を含む JSON を正しく読めるよう、入力は UTF-8 として扱う
          @input.set_encoding(Encoding::UTF_8) if @input.respond_to?(:set_encoding)
          @input.each_line do |line|
            next if line.strip.empty?

            message = begin
              JSON.parse(line)
            rescue JSON::ParserError
              write(Protocol.error(nil, Protocol::PARSE_ERROR, 'Parse error'))
              next
            end
            response = handle(message)
            write(response) if response
          end
        end

        # 1 メッセージ（Hash）を処理して応答（Hash）を返す。通知なら nil
        def handle(message)
          id = message['id']
          method = message['method']
          return nil if id.nil? # 通知には応答しない

          result =
            case method
            when 'initialize'
              { protocolVersion: message.dig('params', 'protocolVersion') || Protocol::PROTOCOL_VERSION,
                capabilities: { tools: {} }, serverInfo: Protocol::SERVER_INFO, instructions: ToolCatalog::INSTRUCTIONS }
            when 'ping' then {}
            when 'tools/list' then { tools: ToolCatalog.tools(default_vil: @env.layout_path) }
            when 'tools/call'
              @tools.call(message.dig('params', 'name'), message.dig('params', 'arguments') || {})
            else
              return Protocol.error(id, Protocol::METHOD_NOT_FOUND, "Method not found: #{method}")
            end
          Protocol.result(id, result)
        end

        private

        def write(message)
          @output.puts(Protocol.dump(message))
          @output.flush
        end
      end
    end
  end
end
