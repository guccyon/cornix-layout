# frozen_string_literal: true

require_relative 'problem'
require_relative 'invalid_config'

module Cornix
  module Storage
    # 読み込みの途中で見つかった問題を集める入れ物。最後に raise_if_any! でまとめて送出する
    class Problems
      def initialize
        @list = []
      end

      # 問題を記録して nil を返す（読み込みの途中で「値なし」として使えるように）
      def add(file, location, message)
        @list << Problem.new(file: file, location: location, message: message)
        nil
      end

      def empty? = @list.empty?
      def size = @list.size
      def to_a = @list.dup

      # unused は InvalidConfig#unused に渡す未使用のファイル
      def raise_if_any!(unused: [])
        raise InvalidConfig.new(@list, unused: unused) unless @list.empty?
      end
    end
  end
end
