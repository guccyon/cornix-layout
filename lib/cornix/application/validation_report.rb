# frozen_string_literal: true

module Cornix
  module Application
    # Validate の結果。errors / warnings は「ファイル: キーの位置: 内容」の文字列。
    # profile は読み込めたときの Domain::Profile（構造の問題で読めなければ nil）
    class ValidationReport < Data.define(:errors, :warnings, :profile)
      def initialize(errors:, warnings: [], profile: nil)
        super(errors: errors.dup.freeze, warnings: warnings.dup.freeze, profile: profile)
      end

      def valid? = errors.empty?
    end
  end
end
