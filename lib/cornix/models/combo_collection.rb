# frozen_string_literal: true

require_relative 'concerns/validatable'

module Cornix
  module Models
    # 32コンボ固定のコレクション
    class ComboCollection
      include Concerns::Validatable

      MAX_SIZE = 32

      include Enumerable

      # Structural validations
      validates :combos, :custom, with: ->(value) {
        if value.size > MAX_SIZE
          { valid: false, error: "Too many combos: #{value.size} (max: #{MAX_SIZE})" }
        else
          { valid: true }
        end
      }, field_name: "size"

      # Structural validation: check for duplicate indices
      validates :combos, :custom, with: ->(value) {
        return { valid: true } if value.nil? || value.empty?

        indices = value.map(&:index)
        duplicates = indices.select { |i| indices.count(i) > 1 }.uniq

        if duplicates.empty?
          { valid: true }
        else
          { valid: false, error: "Duplicate combo indices found: #{duplicates.join(', ')}" }
        end
      }, field_name: "indices"

      # Semantic validation: validate each combo
      validates :combos, :custom, phase: :semantic, with: ->(value, options) {
        errors = []
        return { valid: true } if value.nil? || value.empty?

        # Extract only context keys, excluding validation-specific keys like :with
        context = options.slice(:keycode_converter, :reference_converter, :position_map, :config_dir)

        value.each_with_index do |combo, idx|
          next if combo.nil?

          unless combo.respond_to?(:validate!)
            errors << "combo[#{idx}] is not a Combo instance (got #{combo.class})"
            next
          end

          # メタデータからファイル名を取得
          file_path = begin
            metadata = combo.instance_variable_get(:@metadata)
            metadata && metadata[:file_path] ? File.basename(metadata[:file_path]) : nil
          rescue
            nil
          end
          prefix = file_path ? "#{file_path}: " : "combo[#{idx}]: "

          begin
            combo_errors = combo.validate!(context, mode: :collect)
            combo_errors.each { |e| errors << "#{prefix}#{e}" }
          rescue => e
            errors << "#{prefix}validation failed: #{e.message}"
          end
        end
        errors.empty? ? { valid: true } : { valid: false, error: errors.join("; ") }
      }

      def initialize(combos = [])
        @combos = combos
        if combos.size > MAX_SIZE
          raise ArgumentError, "Too many combos: #{combos.size} (max: #{MAX_SIZE})"
        end
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
