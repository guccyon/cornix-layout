# frozen_string_literal: true

require_relative '../command'
require_relative '../config_messages'
require_relative '../device_report'

module Cornix
  module Interface
    module Cli
      module Commands
        # cornix status: config/ を compile（tmp/build/layout.vil）して、キーボードとの差分を表示する（書き込みなし）。
        # = cornix compile && cornix device diff
        class Status < Command
          include ConfigMessages
          include DeviceReport

          command 'status', 'config/ を compile して、キーボードとの差分を表示する（書き込みなし）'

          def run(args)
            parse!(args)
            result = compile_config or return FAILURE

            out.line
            print_diff(use_case(:device_diff).call(vil_path: result.path))
            SUCCESS
          end
        end
      end
    end
  end
end
