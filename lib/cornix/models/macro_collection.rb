# frozen_string_literal: true

module Cornix
  module Models
    # 32マクロ固定のコレクション
    class MacroCollection
      MAX_SIZE = 32

      include Enumerable

      def initialize(macros = [])
        if macros.size > MAX_SIZE
          raise ArgumentError, "Too many macros: #{macros.size} (max: #{MAX_SIZE})"
        end
        @macros = macros
      end

      # インデックスアクセス
      def [](index)
        @macros[index]
      end

      # 反復処理
      def each(&block)
        @macros.each(&block)
      end

      # サイズ取得
      def size
        @macros.size
      end

      # 32要素の配列を生成（空きは空配列[]）
      def to_qmk_array
        result = Array.new(MAX_SIZE) { [] }
        @macros.each do |macro|
          next if macro.nil?
          result[macro.index] = macro.to_qmk
        end
        result
      end
    end
  end
end
