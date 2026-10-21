# frozen_string_literal: true

module Cornix
  module Application
    # DeviceApply / DeviceRestore の結果。
    # changes: 書き込もうとした変更の説明 / applied: 書き込んだ件数（差分がなければ 0）
    # backup: 書き込む前に保存したバックアップのパス（書かなかったら nil）
    # remaining: 読み直して目標と一致しなかった変更の説明 / remaining_changes: その Planning::Change
    # cancelled: confirm が偽を返して書き込みをやめた（何も書かず、バックアップも取っていない）
    # to_h の changes と remaining は説明と Change#to_h を合わせたもの（Serialize.changes）
    class ApplyOutcome < Data.define(:source, :plan, :changes, :warnings, :backup, :applied, :remaining, :remaining_changes,
                                     :cancelled)
      def initialize(cancelled: false, remaining_changes: [], **rest) = super

      # 書き込まずにやめた結果
      def self.cancelled(plan_result)
        new(source: plan_result.source, plan: plan_result.plan, changes: plan_result.changes,
            warnings: plan_result.warnings, backup: nil, applied: 0, remaining: [], cancelled: true)
      end

      def written? = applied.positive?
      def cancelled? = cancelled
      def success? = remaining.empty?

      def to_h
        {
          'source' => source, 'token' => plan.token, 'changes' => Serialize.changes(plan.changes, changes), 'warnings' => warnings.dup,
          'written' => written?, 'cancelled' => cancelled?, 'applied' => applied, 'backup' => backup,
          'remaining' => Serialize.changes(remaining_changes, remaining), 'success' => success?
        }
      end
    end
  end
end
