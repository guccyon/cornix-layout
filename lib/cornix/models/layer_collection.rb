# frozen_string_literal: true

require_relative 'concerns/validatable'

module Cornix
  module Models
    # 10レイヤー固定のコレクション
    class LayerCollection
      include Concerns::Validatable

      MAX_SIZE = 10

      include Enumerable

      # Structural validations
      validates :layers, :custom, with: ->(value) {
        if value.size > MAX_SIZE
          { valid: false, error: "Too many layers: #{value.size} (max: #{MAX_SIZE})" }
        else
          { valid: true }
        end
      }, field_name: "size"

      # Semantic validation: validate each layer
      validates :layers, :custom, phase: :semantic, with: ->(value, options) {
        errors = []
        return { valid: true } if value.nil? || value.empty?

        unless value.is_a?(Array)
          return { valid: false, error: "layers is not an Array (got #{value.class})" }
        end

        # Extract only context keys, excluding validation-specific keys like :with
        context = options.slice(:keycode_converter, :reference_converter, :position_map, :config_dir)

        value.each_with_index do |layer, idx|
          # Skip nil elements
          next if layer.nil?

          # Check if layer has validate! method (is a model instance)
          unless layer.respond_to?(:validate!)
            errors << "layer[#{idx}] is not a Layer instance (got #{layer.class})"
            next
          end

          # メタデータからファイル名を取得
          file_path = begin
            metadata = layer.instance_variable_get(:@metadata)
            metadata && metadata[:file_path] ? File.basename(metadata[:file_path]) : nil
          rescue
            nil
          end
          prefix = file_path ? "#{file_path}: " : "layer[#{idx}]: "

          begin
            layer_errors = layer.validate!(context, mode: :collect)
            layer_errors.each { |e| errors << "#{prefix}#{e}" }
          rescue => e
            errors << "#{prefix}validation failed: #{e.message}"
          end
        end
        errors.empty? ? { valid: true } : { valid: false, error: errors.join("; ") }
      }

      def initialize(layers = [])
        @layers = layers
        if layers.size > MAX_SIZE
          raise ArgumentError, "Too many layers: #{layers.size} (max: #{MAX_SIZE})"
        end
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
