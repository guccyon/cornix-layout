# frozen_string_literal: true

module Cornix
  module Interface
    module Cli
      # device diff / apply / restore と、直下の status / apply / restore が共通で使う表示と流れ
      module DeviceReport
        CONFIRM = "\nこの差分をキーボードに書き込みますか？ [y/N] "

        private

        def print_diff(plan)
          if plan.empty?
            out.line('✓ キーボードとの差分はありません')
          else
            out.line("差分 #{plan.changes.size} 件:")
            out.items(plan.changes)
          end
          out.items(plan.warnings, prefix: '  ⚠️  ')
        end

        # 1 回の接続の中で、差分を表示 → y/N（yes なら尋ねない）→ 書き込み。→ 終了コード
        #   run_apply(restore: false, yes: opts[:yes]) { |confirm| use_case(:device_apply).call(vil_path: f, confirm: confirm) }
        def run_apply(restore:, yes:)
          label = restore ? '復元元' : '反映元'
          confirm = lambda do |plan|
            out.line("#{label}: #{plan.source}")
            print_diff(plan)
            plan.empty? || yes || confirm?(CONFIRM)
          end
          outcome = yield confirm
          return report_apply(outcome) if outcome.written?

          out.line('中止しました') if outcome.cancelled?
          Command::SUCCESS
        end

        def report_apply(outcome)
          out.line("✓ #{outcome.applied} 件を書き込みました（反映前のバックアップ: #{outcome.backup}）")
          if outcome.success?
            out.line('✓ 読み戻して検証し、すべて一致しました')
            Command::SUCCESS
          else
            out.line("⚠️  読み戻し後も #{outcome.remaining.size} 件が一致しません:")
            out.items(outcome.remaining)
            Command::FAILURE
          end
        end

        # restore の流れ（file はバックアップのパス・ファイル名。nil なら最新）
        def run_restore(file, yes:)
          run_apply(restore: true, yes: yes) { |confirm| use_case(:device_restore).call(file, confirm: confirm) }
        end

        def yes_option(parser, opts) = parser.on('--yes', '確認を省略する') { opts[:yes] = true }
      end
    end
  end
end
