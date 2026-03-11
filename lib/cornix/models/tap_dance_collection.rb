# frozen_string_literal: true

module Cornix
  module Models
    # 32タップダンス固定のコレクション
    class TapDanceCollection
      MAX_SIZE = 32

      include Enumerable

      def initialize(tap_dances = [])
        if tap_dances.size > MAX_SIZE
          raise ArgumentError, "Too many tap dances: #{tap_dances.size} (max: #{MAX_SIZE})"
        end
        @tap_dances = tap_dances
      end

      # インデックスアクセス
      def [](index)
        @tap_dances[index]
      end

      # 反復処理
      def each(&block)
        @tap_dances.each(&block)
      end

      # サイズ取得
      def size
        @tap_dances.size
      end

      # 32要素の配列を生成（空きは["KC_NO", "KC_NO", "KC_NO", "KC_NO", 250]）
      def to_qmk_array
        result = Array.new(MAX_SIZE) { ['KC_NO', 'KC_NO', 'KC_NO', 'KC_NO', 250] }
        @tap_dances.each do |tap_dance|
          next if tap_dance.nil?
          result[tap_dance.index] = tap_dance.to_qmk
        end
        result
      end
    end
  end
end
