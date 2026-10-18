# frozen_string_literal: true

module Cornix
  module Application
    # SuggestRenames の結果。status は
    #   :ok              plans を読めた（空のこともある）
    #   :claude_missing  claude コマンドがない
    #   :unparsed        Claude の出力から JSON を取り出せなかった（output は log_path に保存した）
    #   :missing         計画ファイルがない / :invalid 計画ファイルを JSON として読めない（error に理由）
    class RenameSuggestions < Data.define(:status, :plans, :elapsed, :success, :log_path, :plans_path, :error)
      def initialize(status:, plans: [], elapsed: nil, success: nil, log_path: nil, plans_path: nil, error: nil) = super

      def ok? = status == :ok
    end
  end
end
