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
                if parsed.is_a?(Hash) && parsed[:type] == :modifier_expression
                  ModifierExpressionCompiler.to_qmk(parsed, options[:keycode_converter])
                else
                  options[:keycode_converter].resolve(keycode)
                end
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
        # @return [Array<Array<Integer>>] [[left_ccw, left_cw], [right_ccw, right_cw]]
        def to_qmk(keycode_converter)
          [
            [resolve_keycode(@left[:ccw], keycode_converter), resolve_keycode(@left[:cw], keycode_converter)],
            [resolve_keycode(@right[:ccw], keycode_converter), resolve_keycode(@right[:cw], keycode_converter)]
          ]
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

        def resolve_keycode(raw_value, keycode_converter)
          return nil if raw_value.nil?
          parsed = KeycodeParser.parse(raw_value)
          if parsed.is_a?(Hash) && parsed[:type] == :modifier_expression
            return ModifierExpressionCompiler.to_qmk(parsed, keycode_converter)
          end
          keycode_converter.resolve(raw_value)
        end
      end
    end
  end
end
