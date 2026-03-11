# frozen_string_literal: true

require_relative 'key_mappable'
require_relative 'keycode_value'
require_relative '../concerns/validatable'

module Cornix
  module Models
    class Layer
      # KeyMapping: 単一キーのマッピング
      #
      # position_map 上のシンボル名と、キーコード値の対応を表現します。
      #
      # 主な特徴：
      # - symbol: position_map上のシンボル名（例: 'Q', 'tab'）
      # - keycode: KeycodeValue オブジェクト（PlainKeycode, ReferenceKeycode, FunctionKeycode のいずれか）
      # - logical_coord: 論理座標（{ hand: :left/:right, row: 0-3, col: 0-5 }）
      class KeyMapping
        include KeyMappable
        include Concerns::Validatable

        attr_reader :symbol, :keycode, :logical_coord

        # === バリデーション定義 ===

        validates :symbol, :presence, message: "cannot be nil or empty"
        validates :symbol, :format, with: /^[a-zA-Z0-9_-]+$/,
                  message: "contains invalid characters (only [a-zA-Z0-9_-] allowed)",
                  allow_nil: true

        validates :keycode, :presence, message: "cannot be nil"

        validates :logical_coord, :type, is: Hash, message: "must be a Hash"

        validates :logical_coord, :custom, with: ->(value) {
          return { valid: false, error: "must be a Hash" } unless value.is_a?(Hash)

          errors = []
          unless [:left, :right].include?(value[:hand])
            errors << "hand must be :left or :right"
          end

          unless value[:row].is_a?(Integer) && (0..3).include?(value[:row])
            errors << "row must be 0-3"
          end

          unless value[:col].is_a?(Integer) && (0..5).include?(value[:col])
            errors << "col must be 0-5"
          end

          if errors.empty?
            { valid: true }
          else
            { valid: false, error: errors.join(", ") }
          end
        }, field_name: "logical_coord"

        # セマンティック検証: キーコード解決
        validates :keycode, :custom, phase: :semantic, with: ->(value, options) {
          return { valid: true } if value.nil?
          return { valid: true } unless options[:keycode_converter]

          begin
            value.to_qmk(
              options[:keycode_converter],
              reference_converter: options[:reference_converter]
            )
            { valid: true }
          rescue => e
            { valid: false, error: "keycode '#{value}' cannot be resolved: #{e.message}" }
          end
        }

        # セマンティック検証: Position Map参照
        validates :symbol, :custom, phase: :semantic, with: ->(value, options) {
          return { valid: true } if value.nil? || value.to_s.empty?
          return { valid: true } unless options[:position_map]

          if options[:position_map].symbol_exists?(value)
            { valid: true }
          else
            { valid: false, error: "symbol '#{value}' not found in position_map" }
          end
        }

        # @param symbol [String] position_map上のシンボル名
        # @param keycode [KeycodeValue, String] キーコード値（String の場合は自動的に KeycodeValue に変換）
        # @param logical_coord [Hash] 論理座標
        def initialize(symbol:, keycode:, logical_coord:)
          @symbol = symbol
          @keycode = keycode.is_a?(KeycodeValue) ? keycode : KeycodeValue.from_yaml(keycode)
          @logical_coord = logical_coord
        end

        # QMK数値コードに変換
        #
        # @param keycode_converter [KeycodeConverter] キーコード解決器
        # @param reference_converter [ReferenceConverter, nil] 参照解決器
        # @return [String, Integer] QMKキーコード
        def to_qmk(keycode_converter, reference_converter: nil)
          @keycode.to_qmk(keycode_converter, reference_converter: reference_converter)
        end

        # YAML形式の文字列に変換
        #
        # @return [String] YAML値（エイリアス形式）
        def to_yaml
          @keycode.to_s
        end
      end
    end
  end
end
