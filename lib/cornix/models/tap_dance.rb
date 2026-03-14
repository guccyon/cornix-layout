# frozen_string_literal: true

require_relative 'concerns/validatable'
require_relative '../keycode_parser'

module Cornix
  module Models
    # 1つのタップダンスを保持するモデル
    class TapDance
      include Concerns::Validatable

      attr_reader :index, :name, :description, :on_tap, :on_hold, :on_double_tap,
                  :on_tap_hold, :tapping_term

      # Structural validations
      validates :index, :presence
      validates :index, :type, is: Integer
      validates :index, :custom, with: ->(value) {
        if value >= 0 && value < 32
          { valid: true }
        else
          { valid: false, error: "must be between 0 and 31" }
        end
      }
      validates :name, :presence
      validates :name, :type, is: String
      validates :tapping_term, :type, is: Integer

      # Semantic validations
      validates :on_tap, :custom, phase: :semantic, with: ->(value, options) {
        validate_keycode_field(value, 'on_tap', options)
      }

      validates :on_hold, :custom, phase: :semantic, with: ->(value, options) {
        validate_keycode_field(value, 'on_hold', options)
      }

      validates :on_double_tap, :custom, phase: :semantic, with: ->(value, options) {
        validate_keycode_field(value, 'on_double_tap', options)
      }

      validates :on_tap_hold, :custom, phase: :semantic, with: ->(value, options) {
        validate_keycode_field(value, 'on_tap_hold', options)
      }

      def self.validate_keycode_field(value, field_name, options)
        # KC_NO, 0, -1, nil は許可（空値）
        return { valid: true } if value.nil? || value == 0 || value == -1 || value == 'KC_NO'

        keycode_converter = options[:keycode_converter]
        unless keycode_converter
          return { valid: false, error: 'keycode_converter is required' }
        end

        # まずkeycode_converterで解決を試みる
        resolved = keycode_converter.resolve(value)
        return { valid: true } if resolved

        # 参照式（Macro/TapDance）はreference_converterで解決を試みる
        reference_converter = options[:reference_converter]
        if reference_converter
          begin
            parsed = KeycodeParser.parse(value)
            if parsed[:type] == :reference
              reference_converter.resolve(parsed)
              return { valid: true }
            end
          rescue StandardError
            # fallthrough to error
          end
        end

        { valid: false, error: "Invalid keycode '#{value}'" }
      end

      def initialize(index:, name:, description:, on_tap:, on_hold:, on_double_tap:,
                     on_tap_hold:, tapping_term:)
        @index = index            # 0-31
        @name = name              # 'Escape or Layer'
        @description = description
        @on_tap = on_tap          # Integer (QMK code)
        @on_hold = on_hold        # Integer (QMK code)
        @on_double_tap = on_double_tap  # Integer (QMK code)
        @on_tap_hold = on_tap_hold      # Integer (QMK code)
        @tapping_term = tapping_term    # Integer (milliseconds)
      end

      # QMK配列 → TapDance
      def self.from_qmk(index, qmk_array)
        new(
          index: index,
          name: "TapDance #{index}",  # デフォルト名
          description: '',
          on_tap: qmk_array[0],
          on_hold: qmk_array[1],
          on_double_tap: qmk_array[2],
          on_tap_hold: qmk_array[3],
          tapping_term: qmk_array[4]
        )
      end

      # TapDance → QMK配列
      #
      # @param keycode_converter [KeycodeConverter] キーコード解決器
      # @param reference_converter [ReferenceConverter, nil] 参照解決器
      def to_qmk(keycode_converter: nil, reference_converter: nil)
        actions = [@on_tap, @on_hold, @on_double_tap, @on_tap_hold].map do |value|
          resolve_action_value(value, keycode_converter, reference_converter)
        end
        actions + [@tapping_term]
      end

      # YAML Hash → TapDance
      #
      # actionsキー下にネストされた形式（推奨）とトップレベル形式（後方互換）の両方をサポート
      def self.from_yaml_hash(yaml_hash)
        # メタ情報抽出（存在する場合）
        metadata = yaml_hash.respond_to?(:__metadata) ? yaml_hash.__metadata : {}

        # actions: キー下にネストされた形式を優先、なければトップレベルから読む
        actions = yaml_hash['actions'] || yaml_hash

        instance = new(
          index: yaml_hash['index'],
          name: yaml_hash['name'],
          description: yaml_hash['description'] || '',
          on_tap: actions['on_tap'],
          on_hold: actions['on_hold'],
          on_double_tap: actions['on_double_tap'],
          on_tap_hold: actions['on_tap_hold'],
          tapping_term: yaml_hash['tapping_term']
        )

        # メタ情報保存
        instance.instance_variable_set(:@metadata, metadata)

        instance
      end

      # TapDance → YAML Hash
      def to_yaml_hash
        {
          'index' => @index,
          'name' => @name,
          'description' => @description,
          'actions' => {
            'on_tap' => @on_tap,
            'on_hold' => @on_hold,
            'on_double_tap' => @on_double_tap,
            'on_tap_hold' => @on_tap_hold
          },
          'tapping_term' => @tapping_term
        }
      end

      # 空のタップダンスか判定（全てKC_NO = 0 または -1 または "KC_NO"）
      def empty?
        [@on_tap, @on_hold, @on_double_tap, @on_tap_hold].all? { |v| v.nil? || v == 0 || v == -1 || v == 'KC_NO' }
      end

      private

      # アクション値をQMK形式に解決する
      def resolve_action_value(value, keycode_converter, reference_converter)
        return value if value.nil? || value.is_a?(Integer) || value == 'KC_NO'
        return value unless keycode_converter

        resolved = keycode_converter.resolve(value)
        return resolved if resolved

        if reference_converter
          begin
            parsed = KeycodeParser.parse(value)
            return reference_converter.resolve(parsed) if parsed[:type] == :reference
          rescue StandardError
            # fallthrough
          end
        end

        value
      end
    end
  end
end
