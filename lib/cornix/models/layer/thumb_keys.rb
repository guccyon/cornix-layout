# frozen_string_literal: true

require_relative 'null_key_mapping'
require_relative '../concerns/validatable'

module Cornix
  module Models
    class Layer
      # ThumbKeys: 親指キーの3つのマッピング（Null Object Pattern）
      #
      # 親指キーは固定で3つ（left, middle, right）のマッピングを持ちます。
      # デフォルトでは NULL_KEY（NullKeyMapping）が設定され、nilチェックが不要になります。
      #
      # 主な特徴：
      # - 固定フィールド: left, middle, right（配列インデックスより安全）
      # - Null Object Pattern: デフォルト値は NULL_KEY（-1 / nil を返す）
      # - ポリモーフィック: KeyMapping も NullKeyMapping も同じインターフェース
      class ThumbKeys
        include Concerns::Validatable

        attr_reader :left, :middle, :right

        # === バリデーション定義 ===

        validates :left, :presence, message: "left thumb key cannot be nil", allow_nil: false
        validates :middle, :presence, message: "middle thumb key cannot be nil", allow_nil: false
        validates :right, :presence, message: "right thumb key cannot be nil", allow_nil: false

        # 各キーの構造検証（NULL_KEYは許容）
        [:left, :middle, :right].each do |thumb_key|
          validates thumb_key, :custom, with: ->(value) {
            return { valid: true } if value.is_a?(NullKeyMapping)

            if value.respond_to?(:structurally_valid?)
              errors = value.structural_errors
              if errors.empty?
                { valid: true }
              else
                { valid: false, error: errors.join("; ") }
              end
            else
              { valid: true }
            end
          }
        end

        # セマンティック検証: 各キーのセマンティック検証
        [:left, :middle, :right].each do |thumb_key|
          validates thumb_key, :custom, phase: :semantic, with: ->(value, options) {
            return { valid: true } if value.is_a?(NullKeyMapping)

            if value.respond_to?(:semantic_errors)
              # Extract only context keys, excluding validation-specific keys like :with
              context = options.slice(:keycode_converter, :reference_converter, :position_map, :config_dir)
              errors = value.semantic_errors(context)
              if errors.empty?
                { valid: true }
              else
                { valid: false, error: errors.join("; ") }
              end
            else
              { valid: true }
            end
          }
        end

        # @param left [KeyMapping, NullKeyMapping] 左親指キー（デフォルト: NULL_KEY）
        # @param middle [KeyMapping, NullKeyMapping] 中央親指キー（デフォルト: NULL_KEY）
        # @param right [KeyMapping, NullKeyMapping] 右親指キー（デフォルト: NULL_KEY）
        def initialize(left: NULL_KEY, middle: NULL_KEY, right: NULL_KEY)
          @left = left
          @middle = middle
          @right = right
        end

        # QMK数値コード配列に変換（3要素固定）
        #
        # @param keycode_converter [KeycodeConverter] キーコード解決器
        # @param reference_converter [ReferenceConverter, nil] 参照解決器
        # @return [Array<String, Integer>] QMKキーコード配列（3要素）
        def to_qmk_array(keycode_converter, reference_converter: nil)
          [@left, @middle, @right].map do |key|
            key.to_qmk(keycode_converter, reference_converter: reference_converter)
          end
        end

        # YAML形式のハッシュに変換（nilは除外）
        #
        # @return [Hash<String, String>] { 'left' => 'Tab', 'middle' => 'Space' }
        def to_yaml_hash
          {
            'left' => @left.to_yaml,
            'middle' => @middle.to_yaml,
            'right' => @right.to_yaml
          }.compact  # nil を除外
        end

        # 配列から ThumbKeys を構築（Factory Method）
        #
        # @param array [Array<KeyMapping, NullKeyMapping, nil>] キーマッピング配列（最大3要素）
        # @return [ThumbKeys]
        def self.from_array(array)
          new(
            left: array[0] || NULL_KEY,
            middle: array[1] || NULL_KEY,
            right: array[2] || NULL_KEY
          )
        end

        # YAMLハッシュから ThumbKeys を構築（Factory Method）
        #
        # @param yaml_hash [Hash] YAML形式のハッシュ { 'left' => 'Tab', ... }
        # @param thumb_symbols [Array<String>] position_map のシンボル配列（例: ['left', 'middle', 'right']）
        # @param keycode_value_factory [Proc] KeycodeValue を生成するファクトリ
        # @return [ThumbKeys]
        def self.from_yaml_hash(yaml_hash, thumb_symbols, keycode_value_factory)
          yaml_hash ||= {}

          left_key = build_key_mapping(yaml_hash, thumb_symbols[0], 0, keycode_value_factory)
          middle_key = build_key_mapping(yaml_hash, thumb_symbols[1], 1, keycode_value_factory)
          right_key = build_key_mapping(yaml_hash, thumb_symbols[2], 2, keycode_value_factory)

          new(left: left_key, middle: middle_key, right: right_key)
        end

        # 全てのキーを配列で返す（配列インターフェース互換性のため）
        #
        # @return [Array<KeyMapping, NullKeyMapping>]
        def to_array
          [@left, @middle, @right]
        end

        private

        # YAMLハッシュから単一の KeyMapping を構築
        #
        # @param yaml_hash [Hash] YAML形式のハッシュ
        # @param symbol [String] position_map のシンボル
        # @param index [Integer] 配列インデックス（0-2）
        # @param keycode_value_factory [Proc] KeycodeValue を生成するファクトリ
        # @return [KeyMapping, NullKeyMapping]
        def self.build_key_mapping(yaml_hash, symbol, index, keycode_value_factory)
          keycode = yaml_hash[symbol]
          return NULL_KEY if keycode.nil?

          keycode_value_factory.call(
            symbol: symbol,
            keycode: keycode,
            logical_coord: { row: 3, col: 3 + index }  # 親指キーは row 3, col 3-5
          )
        end
      end
    end
  end
end
