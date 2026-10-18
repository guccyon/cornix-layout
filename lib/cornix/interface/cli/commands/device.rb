# frozen_string_literal: true

require_relative '../command'

module Cornix
  module Interface
    module Cli
      module Commands
        # cornix device <action>: 接続中のキーボードを読む・差分を見る・書き込む（旧 bin/subcommands/device.rb）
        class Device < Command
          command 'device', '接続中のキーボードを読む・差分を見る・書き込む（info, read, backup, diff, apply, restore）',
                  args: '<action> [...]'

          USAGE = <<~USAGE
            Usage:
              cornix device info              接続中のキーボードの情報を表示
              cornix device read [-o FILE]    キーボードの状態を layout.vil 形式で出力
              cornix device backup            キーボードの状態を tmp/device_backups/ に保存
              cornix device diff [FILE]       layout.vil とキーボードの差分を表示（書き込みなし）
              cornix device apply [FILE]      差分を確認してキーボードへ書き込む（--yes で確認を省略）
              cornix device restore [FILE]    最後のバックアップ（直前の apply の前の状態）に戻す（--yes で確認を省略）
          USAGE

          CONFIRM = "\nこの差分をキーボードに書き込みますか？ [y/N] "

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

          # 1 回の接続の中で、差分を表示 → y/N（--yes なら尋ねない）→ 書き込み（旧実装と同じく接続は 1 回）
          def apply(action, args)
            (file,), opts = parse!(args, max_args: 1) { |p, o| p.on('--yes', '確認を省略する') { o[:yes] = true } }
            label = action == 'restore' ? '復元元' : '反映元'
            confirm = lambda do |plan|
              out.line("#{label}: #{plan.source}")
              print_diff(plan)
              plan.empty? || opts[:yes] || confirm?(CONFIRM)
            end
            outcome = if action == 'restore'
                        use_case(:device_restore).call(file, confirm: confirm)
                      else
                        use_case(:device_apply).call(vil_path: file, confirm: confirm)
                      end
            return report_apply(outcome) if outcome.written?

            out.line('中止しました') if outcome.cancelled?
            SUCCESS
          end

          def print_diff(plan)
            if plan.empty?
              out.line('✓ キーボードとの差分はありません')
            else
              out.line("差分 #{plan.changes.size} 件:")
              out.items(plan.changes)
            end
            out.items(plan.warnings, prefix: '  ⚠️  ')
          end

          def report_apply(outcome)
            out.line("✓ #{outcome.applied} 件を書き込みました（反映前のバックアップ: #{outcome.backup}）")
            if outcome.success?
              out.line('✓ 読み戻して検証し、すべて一致しました')
              SUCCESS
            else
              out.line("⚠️  読み戻し後も #{outcome.remaining.size} 件が一致しません:")
              out.items(outcome.remaining)
              FAILURE
            end
          end
        end
      end
    end
  end
end
