# frozen_string_literal: true

require_relative '../command'
require_relative '../device_report'

module Cornix
  module Interface
    module Cli
      module Commands
        # cornix restore [SNAPSHOT] [--yes]: スナップショット（既定は最新の pre-apply = 直前の apply の前の状態）にキーボードを戻す。
        # = cornix device restore
        class Restore < Command
          include DeviceReport

          command 'restore', 'スナップショット（既定は直前の apply の前の状態）にキーボードを戻す（--yes で確認を省略）',
                  args: '[SNAPSHOT] [--yes]'

          def run(args)
            (file,), opts = parse!(args, max_args: 1) { |p, o| yes_option(p, o) }
            run_restore(file, yes: opts[:yes], wrap: method(:with_config))
          end
        end
      end
    end
  end
end
