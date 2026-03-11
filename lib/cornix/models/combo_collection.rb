# frozen_string_literal: true

module Cornix
  module Models
    # 32コンボ固定のコレクション
    class ComboCollection
      MAX_SIZE = 32

      include Enumerable

      def initialize(combos = [])
        if combos.size > MAX_SIZE
          raise ArgumentError, "Too many combos: #{combos.size} (max: #{MAX_SIZE})"
        end
        @combos = combos
      end

      # インデックスアクセス
      def [](index)
        @combos[index]
      end

      # 反復処理
      def each(&block)
        @combos.each(&block)
      end

      # サイズ取得
      def size
        @combos.size
      end

      # 32要素の配列を生成（空きは["KC_NO", "KC_NO", "KC_NO", "KC_NO", "KC_NO"]）
      def to_qmk_array
        result = Array.new(MAX_SIZE) { ['KC_NO', 'KC_NO', 'KC_NO', 'KC_NO', 'KC_NO'] }
        @combos.each do |combo|
          next if combo.nil?
          result[combo.index] = combo.to_qmk
        end
        result
      end
    end
  end
end
