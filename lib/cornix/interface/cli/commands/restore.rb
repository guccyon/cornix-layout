# frozen_string_literal: true

require_relative '../command'
require_relative '../device_report'

module Cornix
  module Interface
    module Cli
      module Commands
        # cornix restore [BACKUP] [--yes]: バックアップ（既定は最新 = 直前の apply の前の状態）にキーボードを戻す。
        # = cornix device restore
        class Restore < Command
          include DeviceReport

          command 'restore', 'バックアップ（既定は直前の apply の前の状態）にキーボードを戻す（--yes で確認を省略）',
                  args: '[BACKUP] [--yes]'

          def run(args)
            (file,), opts = parse!(args, max_args: 1) { |p, o| yes_option(p, o) }
            run_restore(file, yes: opts[:yes])
          end
        end
      end
    end
  end
end
