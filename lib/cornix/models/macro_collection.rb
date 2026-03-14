# frozen_string_literal: true

require_relative 'concerns/validatable'

module Cornix
  module Models
    # 32マクロ固定のコレクション
    class MacroCollection
      include Concerns::Validatable

      MAX_SIZE = 32

      include Enumerable

      # Structural validations
      validates :macros, :custom, with: ->(value) {
        if value.size > MAX_SIZE
          { valid: false, error: "Too many macros: #{value.size} (max: #{MAX_SIZE})" }
        else
          { valid: true }
        end
      }, field_name: "size"

      # Structural validation: check for duplicate indices
      validates :macros, :custom, with: ->(value) {
        return { valid: true } if value.nil? || value.empty?

        indices = value.map(&:index)
        duplicates = indices.select { |i| indices.count(i) > 1 }.uniq

        if duplicates.empty?
          { valid: true }
        else
          { valid: false, error: "Duplicate macro indices found: #{duplicates.join(', ')}" }
        end
      }, field_name: "indices"

      # Semantic validation: validate each macro
      validates :macros, :custom, phase: :semantic, with: ->(value, options) {
        errors = []
        return { valid: true } if value.nil? || value.empty?

        # Extract only context keys, excluding validation-specific keys like :with
        context = options.slice(:keycode_converter, :reference_converter, :position_map, :config_dir)

        value.each_with_index do |macro, idx|
          next if macro.nil?

          unless macro.respond_to?(:validate!)
            errors << "macro[#{idx}] is not a Macro instance (got #{macro.class})"
            next
          end

          # メタデータからファイル名を取得
          file_path = begin
            metadata = macro.instance_variable_get(:@metadata)
            metadata && metadata[:file_path] ? File.basename(metadata[:file_path]) : nil
          rescue
            nil
          end
          prefix = file_path ? "#{file_path}: " : "macro[#{idx}]: "

          begin
            macro_errors = macro.validate!(context, mode: :collect)
            macro_errors.each { |e| errors << "#{prefix}#{e}" }
          rescue => e
            errors << "#{prefix}validation failed: #{e.message}"
          end
        end
        errors.empty? ? { valid: true } : { valid: false, error: errors.join("; ") }
      }

      def initialize(macros = [])
        @macros = macros
        if macros.size > MAX_SIZE
          raise ArgumentError, "Too many macros: #{macros.size} (max: #{MAX_SIZE})"
        end
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
      def to_qmk_array(keycode_converter:, reference_converter: nil)
        result = Array.new(MAX_SIZE) { [] }
        @macros.each do |macro|
          next if macro.nil?
          result[macro.index] = macro.to_qmk(
            keycode_converter: keycode_converter,
            reference_converter: reference_converter
          )
        end
        result
      end
    end
  end
end
