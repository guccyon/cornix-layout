# frozen_string_literal: true

require_relative '../command'

module Cornix
  module Interface
    module Cli
      module Commands
        # cornix serve: VS Code 拡張と話すサーバーを標準入出力で起動する（docs/vscode-extension/protocol.md）。
        # ワークスペースのフォルダは共通のオプション --root（なければカレントディレクトリ）。
        # 1 つのサーバーが、そのワークスペースの複数のプロファイルを扱う。標準出力は JSON-RPC 専用で、ログは標準エラー出力に書く。
        # --device で実機を比べる・反映する・戻す device のサーバー（protocol.md の 14.）。書き込みは --allow-writes を付けたときだけ
        class Serve < Command
          command 'serve', 'VS Code 拡張と話すサーバーを標準入出力で起動する（--root にワークスペースのフォルダ。' \
                           '--device で実機の比較・反映のサーバー、--allow-writes で書き込みを許す）',
                  args: '[--device [--allow-writes]]'

          def run(args)
            _, opts = parse!(args) do |p, o|
              p.on('--device') { o[:device] = true }
              p.on('--allow-writes') { o[:allow_writes] = true }
            end
            raise UsageError, '--allow-writes は --device と一緒に使います' if opts[:allow_writes] && !opts[:device]
            if runtime.global_options.key?(:config) || runtime.global_options.key?(:profile)
              raise UsageError, 'serve では --config / --profile は使えません（ワークスペースのフォルダを --root で指定する）'
            end
            # LANG が未設定でもファイルを UTF-8 として扱う（stdout は JSON-RPC 専用なので何も表示しない）
            Encoding.default_external = Encoding::UTF_8 unless Encoding.default_external == Encoding::UTF_8
            root = File.expand_path(runtime.global_options[:root] || Dir.pwd)
            raise UsageError, "--root のディレクトリがありません: #{root}" unless File.directory?(root)

            # TODO: ログの出し先を Main.new(err:) に合わせる（Runtime に err を持たせる。今は標準エラー出力に直接書く）
            io = { input: runtime.input, output: out.io, error: $stderr }
            if opts[:device]
              device = Application::Editor::DeviceOperations.new(root: root, env_factory: runtime.method(:env_for))
              return EditorServer::Server.new(device: device, allow_writes: opts[:allow_writes] == true, **io).run
            end

            workbench = Application::Editor::Workbench.new(root: root)
            EditorServer::Server.new(workbench: workbench, **io).run
          end
        end
      end
    end
  end
end
