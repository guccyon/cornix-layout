# frozen_string_literal: true

require_relative '../command'
require_relative '../decompile_report'

module Cornix
  module Interface
    module Cli
      module Commands
        # cornix decompile [FILE]: layout.vil を config/ の YAML にする（旧 bin/subcommands/decompile.rb）。
        # FILE の既定は tmp/layout.vil。config/ にすでに設定があれば何もしない
        class Decompile < Command
          include DecompileReport

          command 'decompile', 'layout.vil を config/ の YAML にする（FILE の既定は tmp/layout.vil）', args: '[FILE]'

          CONFIG_EXISTS = <<~TEXT
            ⚠️  Error: config/ directory already contains configuration files.

            To protect your existing configuration, decompile has been blocked.

            Options:
              1. Backup your config/ directory and remove it
              2. Use 'cornix compile' to compile existing config

            Example:
              mv config config.backup
              cornix decompile ~/Downloads/layout.vil
          TEXT

          def run(args)
            (file,), = parse!(args, max_args: 1)
            report_decompile(use_case(:decompile).call(input: file), config_exists: CONFIG_EXISTS)
          end
        end
      end
    end
  end
end
