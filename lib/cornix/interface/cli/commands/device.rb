# frozen_string_literal: true

require_relative '../command'
require_relative '../device_report'

module Cornix
  module Interface
    module Cli
      module Commands
        # cornix device <action>: 接続中のキーボードを読む・差分を見る・書き込む（旧 bin/subcommands/device.rb）
        class Device < Command
          include DeviceReport

          command 'device', '接続中のキーボードを読む・差分を見る・書き込む（info, read, backup, diff, apply, restore）',
                  args: '<action> [...]'

          USAGE = <<~USAGE
            Usage:
              cornix device info              接続中のキーボードの情報を表示
              cornix device read [-o FILE]    キーボードの状態を layout.vil 形式で出力
              cornix device backup            キーボードの状態を tmp/device_backups/ に保存
              cornix device diff [FILE]       .vil とキーボードの差分を表示（書き込みなし。FILE の既定は compile の出力）
              cornix device apply [FILE]      差分を確認してキーボードへ書き込む（FILE の既定は compile の出力。--yes で確認を省略）
              cornix device restore [BACKUP]  最後のバックアップ（直前の apply の前の状態）に戻す（--yes で確認を省略）
          USAGE

          def self.help = "#{summary}\n\n#{USAGE}"

          def run(args)
            action = args.shift
            case action
            when 'info' then info(args)
            when 'read' then read(args)
            when 'backup' then backup(args)
            when 'diff' then diff(args)
            when 'apply', 'restore' then apply(action, args)
            else
              out.line(USAGE)
              action.nil? ? SUCCESS : FAILURE
            end
          end

          private

          def info(args)
            parse!(args)
            out.json(use_case(:device_info).call.to_h)
            SUCCESS
          end

          def read(args)
            _, opts = parse!(args) { |p, o| p.on('-o FILE', '保存先') { |f| o[:output] = f } }
            result = use_case(:device_read).call(output: opts[:output])
            out.line(result.path ? "✓ 保存しました: #{result.path}" : result.vil)
            SUCCESS
          end

          def backup(args)
            parse!(args)
            out.line("✓ バックアップを保存しました: #{use_case(:device_backup).call.path}")
            SUCCESS
          end

          def diff(args)
            (file,), = parse!(args, max_args: 1)
            print_diff(use_case(:device_diff).call(vil_path: file))
            SUCCESS
          end

          def apply(action, args)
            (file,), opts = parse!(args, max_args: 1) { |p, o| yes_option(p, o) }
            return run_restore(file, yes: opts[:yes]) if action == 'restore'

            run_apply(restore: false, yes: opts[:yes]) do |confirm|
              use_case(:device_apply).call(vil_path: file, confirm: confirm)
            end
          end
        end
      end
    end
  end
end
