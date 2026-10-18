# frozen_string_literal: true

require_relative '../command'
require_relative '../config_messages'

module Cornix
  module Interface
    module Cli
      module Commands
        # cornix compile: config/ を検証してから layout.vil を書く（旧 bin/subcommands/compile.rb）
        class Compile < Command
          include ConfigMessages

          command 'compile', 'config/ の YAML を検証して layout.vil を書く'

          def run(args)
            parse!(args)
            out.line('🔍 Validating configuration...')
            result = use_case(:compile).call
            print_report(result.report)
            unless result.compiled?
              out.line("\n❌ Validation failed. Fix errors before compiling.")
              return FAILURE
            end

            out.line("✓ Validation passed\n\n")
            out.line('🔨 Compiling...')
            out.line("✓ Compiled: #{result.path}")
            out.line("\n✓ Compilation completed: #{result.path}")
            SUCCESS
          rescue Application::ConfigNotFound => e
            config_not_found(e, hint: true)
          end
        end
      end
    end
  end
end
