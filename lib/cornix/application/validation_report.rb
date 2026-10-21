# frozen_string_literal: true

module Cornix
  module Application
    # Validate の結果。diagnostics は Domain::Diagnostic の一覧で、path は設定ファイル上の位置（「ファイル: キーの位置」。
    # 構造の問題でファイルや位置が分からなければ空）。
    # profile は読み込めたときの Domain::Profile（構造の問題で読めなければ nil）
    class ValidationReport < Data.define(:diagnostics, :profile)
      def initialize(diagnostics: [], profile: nil)
        super(diagnostics: diagnostics.dup.freeze, profile: profile)
      end

      def valid? = diagnostics.none?(&:error?)

      # 「ファイル: キーの位置: 内容」の文字列（人が読む表示用）
      def errors = texts(diagnostics.select(&:error?))
      def warnings = texts(diagnostics.select(&:warning?))

      def to_h = { 'ok' => valid?, 'diagnostics' => Serialize.diagnostics(diagnostics) }

      private

      def texts(list) = list.map { |d| [d.path, d.message].reject(&:empty?).join(': ') }
    end
  end
end
