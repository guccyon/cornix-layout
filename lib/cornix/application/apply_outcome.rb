# frozen_string_literal: true

module Cornix
  module Application
    # DeviceApply / DeviceRestore の結果。
    # changes: 書き込もうとした変更の説明 / applied: 書き込んだ件数（差分がなければ 0）
    # backup: 書き込む前に保存したバックアップのパス（書かなかったら nil）
    # remaining: 読み直して目標と一致しなかった変更の説明
    class ApplyOutcome < Data.define(:source, :plan, :changes, :warnings, :backup, :applied, :remaining)
      def written? = applied.positive?
      def success? = remaining.empty?

      def to_h
        {
          'source' => source, 'token' => plan.token, 'changes' => changes.dup, 'warnings' => warnings.dup,
          'written' => written?, 'applied' => applied, 'backup' => backup, 'remaining' => remaining.dup,
          'success' => success?
        }
      end
    end
  end
end
