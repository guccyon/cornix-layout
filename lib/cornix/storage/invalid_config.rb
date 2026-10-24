# frozen_string_literal: true

module Cornix
  module Storage
    # 設定ディレクトリの読み込みで見つかった問題をすべてまとめた例外。
    # message は「ファイル: キーの位置: 内容」を 1 行ずつ並べたもの。
    # unused は読み込めた範囲の未使用のファイル（UnusedFile。その問題は compile を止めないので problems に入れない）
    class InvalidConfig < ConfigError
      attr_reader :problems, :unused

      def initialize(problems, unused: [])
        @problems = problems.dup.freeze
        @unused = unused.dup.freeze
        lines = @problems.map { |p| "  #{p}" }
        super("設定ファイルに #{@problems.size} 件の問題があります:\n#{lines.join("\n")}")
      end
    end
  end
end
