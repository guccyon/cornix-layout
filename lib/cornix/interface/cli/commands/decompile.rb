# frozen_string_literal: true

require_relative '../command'

module Cornix
  module Interface
    module Cli
      module Commands
        # cornix decompile [FILE]: layout.vil を config/ の YAML にする（旧 bin/subcommands/decompile.rb）。
        # FILE の既定は tmp/layout.vil。config/ にすでに設定があれば何もしない
        class Decompile < Command
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
            result = use_case(:decompile).call(input: file)
            case result.status
            when :input_missing
              out.line("Error: #{result.input} not found")
              FAILURE
            when :config_exists
              out.line(CONFIG_EXISTS)
              FAILURE
            else
              report(result)
            end
          end

          private

          def report(result)
            out.line("Decompiling: #{result.input}")
            out.line("Output to: #{result.output_dir}")
            out.line
            out.line("✓ Wrote #{result.files.size} files")
            out.line("\n✓ Decompilation completed: #{result.output_dir}")
            out.line("✓ Lock file created: #{result.lock}")
            SUCCESS
          end
        end
      end
    end
  end
end
