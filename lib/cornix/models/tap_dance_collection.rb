# frozen_string_literal: true

require_relative 'concerns/validatable'

module Cornix
  module Models
    # 32タップダンス固定のコレクション
    class TapDanceCollection
      include Concerns::Validatable

      MAX_SIZE = 32

      include Enumerable

      # Structural validations
      validates :tap_dances, :custom, with: ->(value) {
        if value.size > MAX_SIZE
          { valid: false, error: "Too many tap dances: #{value.size} (max: #{MAX_SIZE})" }
        else
          { valid: true }
        end
      }, field_name: "size"

      # Semantic validation: validate each tap_dance
      validates :tap_dances, :custom, phase: :semantic, with: ->(value, options) {
        errors = []
        return { valid: true } if value.nil? || value.empty?

        # Extract only context keys, excluding validation-specific keys like :with
        context = options.slice(:keycode_converter, :reference_converter, :position_map, :config_dir)

        value.each_with_index do |tap_dance, idx|
          next if tap_dance.nil?

          unless tap_dance.respond_to?(:validate!)
            errors << "tap_dance[#{idx}] is not a TapDance instance (got #{tap_dance.class})"
            next
          end

          begin
            td_errors = tap_dance.validate!(context, mode: :collect)
            td_errors.each { |e| errors << "tap_dance[#{idx}]: #{e}" }
          rescue => e
            errors << "tap_dance[#{idx}] validation failed: #{e.message}"
          end
        end
        errors.empty? ? { valid: true } : { valid: false, error: errors.join("; ") }
      }

      def initialize(tap_dances = [])
        @tap_dances = tap_dances
        if tap_dances.size > MAX_SIZE
          raise ArgumentError, "Too many tap dances: #{tap_dances.size} (max: #{MAX_SIZE})"
        end
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
