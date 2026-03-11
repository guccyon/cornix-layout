# frozen_string_literal: true

module Cornix
  module Models
    # 10レイヤー固定のコレクション
    class LayerCollection
      MAX_SIZE = 10

      include Enumerable

      def initialize(layers = [])
        if layers.size > MAX_SIZE
          raise ArgumentError, "Too many layers: #{layers.size} (max: #{MAX_SIZE})"
        end
        @layers = layers
      end

      # インデックスアクセス
      def [](index)
        @layers[index]
      end

      # 反復処理
      def each(&block)
        @layers.each(&block)
      end

      # サイズ取得
      def size
        @layers.size
      end

      # 10要素の layout 配列を生成
      def to_qmk_layout_array(position_map:, keycode_converter:, reference_converter:)
        Array.new(MAX_SIZE) do |i|
          if @layers[i]
            @layers[i].to_qmk(position_map: position_map, keycode_converter: keycode_converter, reference_converter: reference_converter)['layout']
          else
            Array.new(8) { Array.new(7, -1) }
          end
        end
      end

      # 10要素の encoder_layout 配列を生成
      def to_qmk_encoder_array(position_map:, keycode_converter:, reference_converter:)
        Array.new(MAX_SIZE) do |i|
          if @layers[i]
            @layers[i].to_qmk(position_map: position_map, keycode_converter: keycode_converter, reference_converter: reference_converter)['encoder_layout']
          else
            Array.new(2) { Array.new(2, -1) }
          end
        end
      end
    end
  end
end
