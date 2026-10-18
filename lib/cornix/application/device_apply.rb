# frozen_string_literal: true

require_relative 'use_case'

module Cornix
  module Application
    # .vil（省略時は layout.vil）をキーボードへ書き込む → ApplyOutcome（旧 Device::Keyboard#apply）。
    #
    # 1 回の open_device の中で「読む → 計画 → token の確認 → バックアップ → 書く → 読み直して検証」を行う。
    # - expected_token（DeviceDiff の token）を渡すと、計画し直した token と違えば何も書かずに PlanError
    # - 差分がなければ何も書かず、バックアップも取らない
    # - 書き込む前に現在の状態を BackupStore に保存する（失敗時のメッセージにもそのパスが入る）
    # 確認（y/N、dry run → confirm_token）は Interface の責務
    class DeviceApply < UseCase
      def call(vil_path: nil, expected_token: nil)
        source = vil_path || env.layout_path
        target = env.vil_file.read(source)
        env.open_device do |session|
          current, plan = plan_for(session, target)
          result = writer(session).apply(plan, expected_token: expected_token,
                                               backup: -> { env.backup_store.save(current) })
          ApplyOutcome.new(source: source, plan: plan, changes: describe(plan.changes), warnings: plan.warnings,
                           backup: result.backup, applied: result.applied.size, remaining: describe(result.remaining))
        end
      end
    end
  end
end
