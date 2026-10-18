# frozen_string_literal: true

require_relative '../command'

module Cornix
  module Interface
    module Cli
      module Commands
        # cornix mcp: 接続中のキーボードを操作する MCP サーバーを stdio で起動する（旧 bin/subcommands/mcp.rb）
        class Mcp < Command
          command 'mcp', '接続中のキーボードを操作する MCP サーバーを stdio で起動する'

          def run(args)
            parse!(args)
            # LANG が未設定でもファイルや標準入出力を UTF-8 として扱う（stdout は JSON-RPC 専用なので何も表示しない）
            Encoding.default_external = Encoding::UTF_8 unless Encoding.default_external == Encoding::UTF_8
            runtime.mcp_server.run
            SUCCESS
          end
        end
      end
    end
  end
end
