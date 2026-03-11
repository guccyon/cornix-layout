# frozen_string_literal: true

# 新しいコンポーネントを require
require_relative 'layer/keycode_value'
require_relative 'layer/key_mappable'
require_relative 'layer/null_key_mapping'
require_relative 'layer/key_mapping'
require_relative 'layer/thumb_keys'
require_relative 'layer/hand_mapping'
require_relative 'layer/encoder_mapping'
require_relative 'concerns/validatable'

module Cornix
  module Models
    # レイヤーモデル（リファクタ後）
    #
    # 責務：
    # - 左手・右手・エンコーダーのマッピングを統合
    # - QMK形式とYAML形式の相互変換を HandMapping に委譲
    # - メタデータ（name, description, index）の管理
    class Layer
      include Concerns::Validatable

      attr_reader :name, :description, :index, :left_hand, :right_hand, :encoders

      # === バリデーション定義 ===

      validates :name, :presence, message: "cannot be blank"
      validates :name, :length, max: 50, message: "too long (max 50 chars)"
      validates :index, :range, min: 0, max: 9, message: "must be 0-9"

      # ネストしたオブジェクトの検証（構造）
      validates :left_hand, :custom, with: ->(value) {
        return { valid: false, error: "cannot be nil" } if value.nil?

        if value.respond_to?(:structurally_valid?)
          errors = value.structural_errors
          if errors.empty?
            { valid: true }
          else
            { valid: false, error: errors.map { |e| "left_hand: #{e}" }.join("; ") }
          end
        else
          { valid: true }
        end
      }

      validates :right_hand, :custom, with: ->(value) {
        return { valid: false, error: "cannot be nil" } if value.nil?

        if value.respond_to?(:structurally_valid?)
          errors = value.structural_errors
          if errors.empty?
            { valid: true }
          else
            { valid: false, error: errors.map { |e| "right_hand: #{e}" }.join("; ") }
          end
        else
          { valid: true }
        end
      }

      validates :encoders, :custom, with: ->(value) {
        return { valid: false, error: "cannot be nil" } if value.nil?

        if value.respond_to?(:structurally_valid?)
          errors = value.structural_errors
          if errors.empty?
            { valid: true }
          else
            { valid: false, error: errors.map { |e| "encoders: #{e}" }.join("; ") }
          end
        else
          { valid: true }
        end
      }

      # セマンティック検証
      validates :left_hand, :custom, phase: :semantic, with: ->(value, options) {
        return { valid: true } if value.nil?

        if value.respond_to?(:semantic_errors)
          errors = value.semantic_errors(options)
          if errors.empty?
            { valid: true }
          else
            { valid: false, error: errors.map { |e| "left_hand: #{e}" }.join("; ") }
          end
        else
          { valid: true }
        end
      }

      validates :right_hand, :custom, phase: :semantic, with: ->(value, options) {
        return { valid: true } if value.nil?

        if value.respond_to?(:semantic_errors)
          errors = value.semantic_errors(options)
          if errors.empty?
            { valid: true }
          else
            { valid: false, error: errors.map { |e| "right_hand: #{e}" }.join("; ") }
          end
        else
          { valid: true }
        end
      }

      validates :encoders, :custom, phase: :semantic, with: ->(value, options) {
        return { valid: true } if value.nil?

        if value.respond_to?(:semantic_errors)
          errors = value.semantic_errors(options)
          if errors.empty?
            { valid: true }
          else
            { valid: false, error: errors.map { |e| "encoders: #{e}" }.join("; ") }
          end
        else
          { valid: true }
        end
      }

      # @param name [String] レイヤー名
      # @param description [String] レイヤー説明
      # @param index [Integer] レイヤーインデックス（0-9）
      # @param left_hand [HandMapping] 左手のマッピング
      # @param right_hand [HandMapping] 右手のマッピング
      # @param encoders [EncoderMapping] エンコーダーのマッピング
      def initialize(name:, description:, index:, left_hand:, right_hand:, encoders:)
        @name = name
        @description = description
        @index = index
        @left_hand = left_hand      # HandMapping
        @right_hand = right_hand    # HandMapping
        @encoders = encoders        # EncoderMapping
      end

      # QMK 2次元配列 → Layer（Factory Method）
      #
      # @param index [Integer] レイヤーインデックス
      # @param layout_2d [Array<Array<Integer>>] 8行7列の QMK 配列
      # @param encoder_2d [Array<Array<Integer>>] エンコーダー配列
      # @param position_map [PositionMap] 物理座標マッピング
      # @param keycode_converter [KeycodeConverter] キーコード解決器
      # @param reference_converter [ReferenceConverter, nil] 参照解決器
      # @return [Layer]
      def self.from_qmk(index, layout_2d, encoder_2d, position_map, keycode_converter, reference_converter: nil)
        left_hand = HandMapping.from_qmk(
          hand: :left,
          layout_2d: layout_2d,
          position_map: position_map,
          keycode_converter: keycode_converter,
          reference_converter: reference_converter
        )

        right_hand = HandMapping.from_qmk(
          hand: :right,
          layout_2d: layout_2d,
          position_map: position_map,
          keycode_converter: keycode_converter,
          reference_converter: reference_converter
        )

        encoders = build_encoder_mapping(layout_2d, encoder_2d, keycode_converter)

        new(
          name: "Layer #{index}",
          description: '',
          index: index,
          left_hand: left_hand,
          right_hand: right_hand,
          encoders: encoders
        )
      end

      # Layer → QMK形式（Hash）
      #
      # @param position_map [PositionMap] 物理座標マッピング
      # @param keycode_converter [KeycodeConverter] キーコード解決器
      # @param reference_converter [ReferenceConverter, nil] 参照解決器
      # @return [Hash] { 'layout' => Array, 'encoder_layout' => Array }
      def to_qmk(position_map:, keycode_converter:, reference_converter: nil)
        # 左手・右手の to_qmk を呼び出し、8×7 配列にマージ
        left_layout = @left_hand.to_qmk(
          position_map: position_map,
          keycode_converter: keycode_converter,
          reference_converter: reference_converter
        )

        right_layout = @right_hand.to_qmk(
          position_map: position_map,
          keycode_converter: keycode_converter,
          reference_converter: reference_converter
        )

        # 左手（Row 0-3）と右手（Row 4-7）を concat（シンプル）
        layout = left_layout + right_layout

        # エンコーダープッシュボタンを layout に書き込み
        left_pos = position_map.encoder_push_position(:left)
        right_pos = position_map.encoder_push_position(:right)
        layout[left_pos[:row]][left_pos[:col]] = keycode_converter.resolve(@encoders.left[:push])
        layout[right_pos[:row]][right_pos[:col]] = keycode_converter.resolve(@encoders.right[:push])

        {
          'layout' => layout,
          'encoder_layout' => @encoders.to_qmk(keycode_converter)
        }
      end

      # YAML Hash → Layer（Factory Method）
      #
      # @param yaml_hash [Hash] YAML形式のハッシュ
      # @param position_map [PositionMap] 物理座標マッピング
      # @return [Layer]
      def self.from_yaml_hash(yaml_hash, position_map)
        # 階層化構造から HandMapping, EncoderMapping を構築
        mapping = yaml_hash['mapping'] || {}

        left_hand = HandMapping.from_yaml_hash(
          hand: :left,
          yaml_hand: mapping['left_hand'],
          position_map: position_map
        )

        right_hand = HandMapping.from_yaml_hash(
          hand: :right,
          yaml_hand: mapping['right_hand'],
          position_map: position_map
        )

        encoders = EncoderMapping.from_yaml_hash(mapping['encoders'])

        new(
          name: yaml_hash['name'],
          description: yaml_hash['description'] || '',
          index: yaml_hash['index'],
          left_hand: left_hand,
          right_hand: right_hand,
          encoders: encoders
        )
      end

      # Layer → YAML Hash（階層化構造）
      #
      # @param keycode_converter [KeycodeConverter] キーコード解決器
      # @param reference_converter [ReferenceConverter] 参照解決器
      # @return [Hash] YAML形式のハッシュ
      def to_yaml_hash(keycode_converter:, reference_converter:)
        {
          'name' => @name,
          'description' => @description,
          'index' => @index,
          'mapping' => {
            'left_hand' => @left_hand.to_yaml_hash,
            'right_hand' => @right_hand.to_yaml_hash,
            'encoders' => {
              'left' => {
                'push' => @encoders.left[:push],
                'ccw' => @encoders.left[:ccw],
                'cw' => @encoders.left[:cw]
              },
              'right' => {
                'push' => @encoders.right[:push],
                'ccw' => @encoders.right[:ccw],
                'cw' => @encoders.right[:cw]
              }
            }
          }
        }
      end

      private

      # === エンコーダーマッピング構築（QMK → Layer のみ）===

      # QMK配列からエンコーダーマッピングを構築
      #
      # @param layout_2d [Array<Array<Integer>>] 8行7列の QMK 配列
      # @param encoder_2d [Array<Array<Integer>>] エンコーダー配列
      # @param keycode_converter [KeycodeConverter] キーコード解決器
      # @return [EncoderMapping]
      def self.build_encoder_mapping(layout_2d, encoder_2d, keycode_converter)
        left_pos = { row: 2, col: 6 }
        right_pos = { row: 5, col: 6 }

        left_push = keycode_converter.reverse_resolve(layout_2d[left_pos[:row]][left_pos[:col]])
        left_ccw = keycode_converter.reverse_resolve(encoder_2d[0][0])
        left_cw = keycode_converter.reverse_resolve(encoder_2d[0][1])

        right_push = keycode_converter.reverse_resolve(layout_2d[right_pos[:row]][right_pos[:col]])
        right_ccw = keycode_converter.reverse_resolve(encoder_2d[1][0])
        right_cw = keycode_converter.reverse_resolve(encoder_2d[1][1])

        EncoderMapping.new(
          left: { push: left_push, ccw: left_ccw, cw: left_cw },
          right: { push: right_push, ccw: right_ccw, cw: right_cw }
        )
      end
    end
  end
end
