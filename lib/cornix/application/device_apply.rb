# frozen_string_literal: true

require_relative 'use_case'

module Cornix
  module Application
    # .vil（省略時は layout.vil）をキーボードへ書き込む → ApplyOutcome（旧 Device::Keyboard#apply）。
    #
    # 1 回の open_device の中で「読む → 計画 → 確認 → token の確認 → バックアップ → 書く → 読み直して検証」を行う。
    # - confirm（省略可）: 計画のあと同じ接続の中で PlanResult を渡して呼ぶ（差分がなくても呼ぶので表示に使える）。
    #   偽を返したら何も書かず、バックアップも取らずに cancelled の ApplyOutcome を返す（CLI の y/N）
    # - expected_token（DeviceDiff の token）を渡すと、計画し直した token と違えば何も書かずに PlanError（MCP の二段階）
    # - 差分がなければ何も書かず、バックアップも取らない
    # - 書き込む前に現在の状態を BackupStore に保存する（失敗時のメッセージにもそのパスが入る）
    class DeviceApply < UseCase
      def call(vil_path: nil, expected_token: nil, confirm: nil)
        source = vil_path || env.layout_path
        target = env.vil_file.read(source)
        env.open_device do |session|
          current, plan = plan_for(session, target)
          planned = plan_result(source, plan)
          next ApplyOutcome.cancelled(planned) if confirm && !confirm.call(planned)

          result = writer(session).apply(plan, expected_token: expected_token,
                                               backup: -> { env.backup_store.save(current) })
          ApplyOutcome.new(source: source, plan: plan, changes: planned.changes, warnings: plan.warnings,
                           backup: result.backup, applied: result.applied.size, remaining: describe(result.remaining))
        end
      end
    end
  end
end
