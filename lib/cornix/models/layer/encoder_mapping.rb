# frozen_string_literal: true

require_relative '../concerns/validatable'
require_relative '../../keycode_parser'
require_relative '../../modifier_expression_compiler'

module Cornix
  module Models
    class Layer
      # EncoderMapping: エンコーダーのマッピング
      #
      # 左右のエンコーダーのキーマッピングを保持します。
      # - push: プッシュボタン
      # - ccw: 反時計回り
      # - cw: 時計回り
      class EncoderMapping
        include Concerns::Validatable

        attr_reader :left, :right

        # === バリデーション定義 ===

        validates :left, :presence, message: "left encoder cannot be nil", allow_nil: false
        validates :right, :presence, message: "right encoder cannot be nil", allow_nil: false
        validates :left, :type, is: Hash, message: "must be a Hash", allow_nil: false
        validates :right, :type, is: Hash, message: "must be a Hash", allow_nil: false

        # セマンティック検証: 各エンコーダーアクションのキーコード解決
        [:left, :right].each do |side|
          validates side, :custom, phase: :semantic, with: ->(value, options) {
            return { valid: true } if value.nil?
            return { valid: true } unless options[:keycode_converter]

            errors = []
            [:push, :ccw, :cw].each do |action|
              keycode = value[action]
              next if keycode.nil?

              begin
                parsed = KeycodeParser.parse(keycode)
                # 参照式（TapDance('name') 等）は reference_converter がある場合のみ検証する
                next if parsed.is_a?(Hash) && parsed[:type] == :reference && options[:reference_converter].nil?

                resolved = EncoderMapping.resolve_keycode(
                  keycode, options[:keycode_converter], options[:reference_converter]
                )
                errors << "#{side}.#{action}: Invalid keycode '#{keycode}'" if resolved.nil?
              rescue => e
                errors << "#{side}.#{action}: keycode '#{keycode}' cannot be resolved: #{e.message}"
              end
            end

            if errors.empty?
              { valid: true }
            else
              { valid: false, error: errors.join("; ") }
            end
          }
        end

        # @param left [Hash] 左エンコーダー { push: 'KC_MUTE', ccw: 'KC_VOLD', cw: 'KC_VOLU' }
        # @param right [Hash] 右エンコーダー { push: 'KC_MUTE', ccw: 'KC_VOLD', cw: 'KC_VOLU' }
        def initialize(left:, right:)
          @left = left
          @right = right
        end

        # QMK エンコーダー配列に変換（2行2列の配列）
        #
        # @param keycode_converter [KeycodeConverter] キーコード解決器
        # @param reference_converter [ReferenceConverter, nil] 参照解決器
        # @return [Array<Array<Integer>>] [[left_ccw, left_cw], [right_ccw, right_cw]]
        def to_qmk(keycode_converter, reference_converter: nil)
          [
            [resolve(@left[:ccw], keycode_converter, reference_converter), resolve(@left[:cw], keycode_converter, reference_converter)],
            [resolve(@right[:ccw], keycode_converter, reference_converter), resolve(@right[:cw], keycode_converter, reference_converter)]
          ]
        end

        # プッシュボタンのキーコードを QMK 形式に変換
        #
        # プッシュボタンは layout 配列側に書き込まれるため、encoder_layout とは別に解決する
        #
        # @param side [Symbol] :left または :right
        # @param keycode_converter [KeycodeConverter] キーコード解決器
        # @param reference_converter [ReferenceConverter, nil] 参照解決器
        # @return [String, nil]
        def push_to_qmk(side, keycode_converter, reference_converter: nil)
          encoder = side == :left ? @left : @right
          resolve(encoder[:push], keycode_converter, reference_converter)
        end

        # キーコード（エイリアス・修飾キー表現・参照式）を QMK 形式に解決する
        #
        # @return [String, Integer, nil] 解決できない場合は nil
        # @raise [ArgumentError] 参照式を reference_converter なしで解決しようとした場合
        def self.resolve_keycode(raw_value, keycode_converter, reference_converter = nil)
          return nil if raw_value.nil?

          parsed = KeycodeParser.parse(raw_value)
          if parsed.is_a?(Hash)
            case parsed[:type]
            when :modifier_expression
              return ModifierExpressionCompiler.to_qmk(parsed, keycode_converter)
            when :reference
              raise ArgumentError, "reference_converter is required to resolve '#{raw_value}'" if reference_converter.nil?

              return reference_converter.resolve(parsed)
            end
          end
          keycode_converter.resolve(raw_value)
        end

        # YAMLハッシュから EncoderMapping を構築（Factory Method）
        #
        # @param yaml_encoders [Hash, nil] YAML形式のエンコーダーハッシュ
        # @return [EncoderMapping]
        def self.from_yaml_hash(yaml_encoders)
          return new(left: {}, right: {}) if yaml_encoders.nil?

          left_encoder = yaml_encoders['left'] || {}
          right_encoder = yaml_encoders['right'] || {}

          new(
            left: {
              push: left_encoder['push'] || left_encoder[:push],
              ccw: left_encoder['ccw'] || left_encoder[:ccw],
              cw: left_encoder['cw'] || left_encoder[:cw]
            },
            right: {
              push: right_encoder['push'] || right_encoder[:push],
              ccw: right_encoder['ccw'] || right_encoder[:ccw],
              cw: right_encoder['cw'] || right_encoder[:cw]
            }
          )
        end

        private

        def resolve(raw_value, keycode_converter, reference_converter)
          self.class.resolve_keycode(raw_value, keycode_converter, reference_converter)
        end
      end
    end
  end
end
