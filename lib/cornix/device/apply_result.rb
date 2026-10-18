# frozen_string_literal: true

module Cornix
  module Device
    # Writer#apply の結果。
    # backup: 書き込み前に取ったバックアップ（backup コールバックの戻り値。変更がなければ nil）
    # applied: 書き込んだ Change / remaining: 読み直しで目標と一致しなかった Change
    class ApplyResult < Data.define(:backup, :applied, :remaining)
      def initialize(backup: nil, applied: [], remaining: [])
        super(backup: backup, applied: applied.dup.freeze, remaining: remaining.dup.freeze)
      end

      def success? = remaining.empty?
    end
  end
end
