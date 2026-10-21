# frozen_string_literal: true

module Cornix
  module Application
    # 差分の確認（dry run）の結果。source は目標の .vil、changes は plan.changes の説明（"場所: 現在 → 目標"）。
    # to_h の changes は説明と Change#to_h を合わせたもの（Serialize.changes）
    class PlanResult < Data.define(:source, :plan, :changes, :warnings)
      def token = plan.token
      def empty? = plan.empty?

      def to_h
        { 'source' => source, 'token' => token, 'empty' => empty?, 'changes' => Serialize.changes(plan.changes, changes), 'warnings' => warnings.dup }
      end
    end
  end
end
