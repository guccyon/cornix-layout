# frozen_string_literal: true

require_relative '../command'
require_relative '../config_messages'

module Cornix
  module Interface
    module Cli
      module Commands
        # cornix validate: config/ を検証する（旧 bin/subcommands/validate.rb）。問題があれば exit 1
        class Validate < Command
          include ConfigMessages

          command 'validate', 'config/ の YAML を検証する'

          def run(args)
            parse!(args)
            report = use_case(:validate).call
            print_report(report)
            report.valid? ? SUCCESS : FAILURE
          rescue Application::ConfigNotFound => e
            config_not_found(e)
          end
        end
      end
    end
  end
end
