# frozen_string_literal: true

require_relative 'concerns/validatable'

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

        resolved = keycode_converter.resolve(value)
        unless resolved
          return { valid: false, error: "Invalid keycode '#{value}'" }
        end

        { valid: true }
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
      def to_qmk
        [@on_tap, @on_hold, @on_double_tap, @on_tap_hold, @tapping_term]
      end

      # YAML Hash → TapDance
      def self.from_yaml_hash(yaml_hash)
        # メタ情報抽出（存在する場合）
        metadata = yaml_hash.respond_to?(:__metadata) ? yaml_hash.__metadata : {}

        instance = new(
          index: yaml_hash['index'],
          name: yaml_hash['name'],
          description: yaml_hash['description'] || '',
          on_tap: yaml_hash['on_tap'],
          on_hold: yaml_hash['on_hold'],
          on_double_tap: yaml_hash['on_double_tap'],
          on_tap_hold: yaml_hash['on_tap_hold'],
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
          'on_tap' => @on_tap,
          'on_hold' => @on_hold,
          'on_double_tap' => @on_double_tap,
          'on_tap_hold' => @on_tap_hold,
          'tapping_term' => @tapping_term
        }
      end

      # 空のタップダンスか判定（全てKC_NO = 0 または -1 または "KC_NO"）
      def empty?
        [@on_tap, @on_hold, @on_double_tap, @on_tap_hold].all? { |v| v.nil? || v == 0 || v == -1 || v == 'KC_NO' }
      end
    end
  end
end
