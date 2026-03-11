# frozen_string_literal: true

require_relative '../concerns/validatable'

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
                options[:keycode_converter].resolve(keycode)
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
            [keycode_converter.resolve(@left[:ccw]), keycode_converter.resolve(@left[:cw])],
            [keycode_converter.resolve(@right[:ccw]), keycode_converter.resolve(@right[:cw])]
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
      end
    end
  end
end
