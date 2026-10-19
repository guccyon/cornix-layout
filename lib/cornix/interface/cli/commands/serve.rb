# frozen_string_literal: true

require_relative '../command'

module Cornix
  module Interface
    module Cli
      module Commands
        # cornix serve: VS Code 拡張と話すサーバーを標準入出力で起動する（docs/vscode-extension/protocol.md）。
        # ワークスペースのフォルダは共通のオプション --root（なければカレントディレクトリ）。
        # 1 つのサーバーが、そのワークスペースの複数のプロファイルを扱う。標準出力は JSON-RPC 専用で、ログは標準エラー出力に書く
        class Serve < Command
          command 'serve', 'VS Code 拡張と話すサーバーを標準入出力で起動する（--root にワークスペースのフォルダ）'

          def run(args)
            parse!(args)
            # LANG が未設定でもファイルを UTF-8 として扱う（stdout は JSON-RPC 専用なので何も表示しない）
            Encoding.default_external = Encoding::UTF_8 unless Encoding.default_external == Encoding::UTF_8
            root = File.expand_path(runtime.global_options[:root] || Dir.pwd)
            raise UsageError, "--root のディレクトリがありません: #{root}" unless File.directory?(root)

            workbench = Application::Editor::Workbench.new(root: root)
            EditorServer::Server.new(workbench: workbench, input: runtime.input, output: out.io, error: $stderr).run
          end
        end
      end
    end
  end
end
