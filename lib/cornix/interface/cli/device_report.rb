# frozen_string_literal: true

module Cornix
  module Interface
    module Cli
      # device diff / apply / restore と、直下の status / apply / restore が共通で使う表示と流れ
      module DeviceReport
        CONFIRM = "\nこの差分をキーボードに書き込みますか？ [y/N] "
        JSON_NEEDS_YES = '--json では書き込みの確認（y/N）ができないので --yes を付けてください（差分を見るだけなら status か device diff）'

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
        # --json のときは尋ねずに書き込んで ApplyOutcome#to_h を出す（yes が要る。wrap はその Hash を包む手続き）
        def run_apply(restore:, yes:, wrap: ->(h) { h })
          return json_apply(yes: yes, wrap: wrap) { yield nil } if json?

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

        def json_apply(yes:, wrap:)
          check_json_yes!(yes)
          outcome = yield
          emit(wrap.call(outcome.to_h))
          outcome.written? && !outcome.success? ? Command::FAILURE : Command::SUCCESS
        end

        # --json で書き込むコマンドは、キーボードを開く前に --yes を確かめる
        def check_json_yes!(yes)
          raise UsageError, JSON_NEEDS_YES if json? && !yes
        end

        # restore の流れ（file はスナップショットの名前・パス。nil なら最新の pre-apply）
        def run_restore(file, yes:, wrap: ->(h) { h })
          run_apply(restore: true, yes: yes, wrap: wrap) { |confirm| use_case(:device_restore).call(file, confirm: confirm) }
        end

        def yes_option(parser, opts) = parser.on('--yes', '確認を省略する') { opts[:yes] = true }
      end
    end
  end
end
