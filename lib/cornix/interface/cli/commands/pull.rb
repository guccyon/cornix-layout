# frozen_string_literal: true

require_relative '../command'
require_relative '../decompile_report'

module Cornix
  module Interface
    module Cli
      module Commands
        # cornix pull: キーボードの状態を tmp/layout.vil に読み出し、config/ の YAML にする。
        # = cornix device read -o tmp/layout.vil && cornix decompile。
        # config/ にすでに設定があれば、キーボードを開かず tmp/layout.vil も書き換えずに止まる
        class Pull < Command
          include DecompileReport

          command 'pull', 'キーボードの状態を tmp/layout.vil に読み出して config/ の YAML にする'

          CONFIG_EXISTS = <<~TEXT
            ⚠️  Error: config/ directory already contains configuration files.

            To protect your existing configuration, pull has been blocked
            (the keyboard was not read and tmp/layout.vil was not changed).

            Options:
              1. Backup your config/ directory and remove it, then run 'cornix pull' again
              2. Use 'cornix status' to see differences between config/ and the keyboard

            Example:
              mv config config.backup
              cornix pull
          TEXT

          def run(args)
            parse!(args)
            result = use_case(:pull).call
            out.line("✓ キーボードの状態を保存しました: #{result.input}") if result.decompiled?
            report_decompile(result, config_exists: CONFIG_EXISTS)
          end
        end
      end
    end
  end
end
