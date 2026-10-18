# frozen_string_literal: true

module Cornix
  module Storage
    # 設定ファイルの問題 1 件。file は設定ディレクトリからの相対パス（ディレクトリ全体の問題は nil）、
    # location はファイル内のキーの位置（"mapping.left_hand.row0.tab"、"sequence[1].keys[0]"）
    class Problem < Data.define(:file, :location, :message)
      def initialize(file:, message:, location: nil)
        super(file: file&.to_s&.dup&.freeze, location: location.to_s.dup.freeze, message: message.to_s.dup.freeze)
      end

      # "ファイル: キーの位置: 内容"（空の部分は省く）
      def to_s = [file, location, message].reject { |s| s.nil? || s.empty? }.join(': ')
    end
  end
end
