# frozen_string_literal: true

require_relative '../command'
require_relative '../config_messages'
require_relative '../device_report'

module Cornix
  module Interface
    module Cli
      module Commands
        # cornix status: config/ を compile（tmp/build/layout.vil）して、キーボードとの差分を表示する（書き込みなし）。
        # = cornix compile && cornix device diff。差分があれば終了コード 2（nape_pro と同じ）
        class Status < Command
          include ConfigMessages
          include DeviceReport

          command 'status', 'config/ を compile して、キーボードとの差分を表示する（書き込みなし。差分があれば終了コード 2）'

          def run(args)
            parse!(args)
            result = compile_config or return FAILURE

            out.line
            plan = use_case(:device_diff).call(vil_path: result.path)
            print_diff(plan)
            plan.empty? ? SUCCESS : HAS_CHANGES
          end
        end
      end
    end
  end
end
