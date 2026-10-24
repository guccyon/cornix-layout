# frozen_string_literal: true

module Cornix
  module Storage
    # 値の部分だけでは書き換えられない（ファイルを作り直す逃げ道は使わない。protocol.md の 6.3 と 9 の EditNotLocal）。
    # reason は :multiline（複数行の値）・:anchor（アンカーとエイリアス）・:flow_insert（フロー表記の中への挿入）・
    # :shared_line（前に別の内容がある行の項目を行ごと消す・並びの要素の行が見つからない。約束の reason は flowInsert）
    class EditNotLocal < Error
      REASONS = {
        multiline: '複数行の値',
        anchor: 'アンカーとエイリアス',
        flow_insert: 'フロー表記（{ } や [ ]）の中への挿入',
        shared_line: '前に別の内容がある行の書き換え'
      }.freeze

      attr_reader :reason, :path

      def initialize(reason:, path:)
        raise ArgumentError, "知らない理由です: #{reason}" unless REASONS.key?(reason)

        @reason = reason
        @path = path.dup.freeze
        super("値の部分だけでは書き換えられません（#{REASONS.fetch(reason)}）: #{path.join('.')}")
      end
    end
  end
end
