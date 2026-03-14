# frozen_string_literal: true

require_relative 'concerns/validatable'

module Cornix
  module Models
    # 1つのコンボを保持するモデル
    class Combo
      include Concerns::Validatable

      attr_reader :index, :name, :description, :trigger_keys, :output_key

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
      validates :trigger_keys, :presence
      validates :trigger_keys, :type, is: Array
      validates :trigger_keys, :custom, with: ->(value) {
        return { valid: true } if value.nil?  # presenceで検証済み

        if value.size <= 4
          { valid: true }
        else
          { valid: false, error: "cannot have more than 4 trigger keys" }
        end
      }
      validates :output_key, :presence

      # Semantic validations
      validates :trigger_keys, :custom, phase: :semantic, with: ->(value, options) {
        return { valid: true } if value.nil? || value.empty?

        keycode_converter = options[:keycode_converter]
        unless keycode_converter
          return { valid: false, error: 'keycode_converter is required' }
        end

        errors = []
        value.each_with_index do |key, idx|
          # KC_NO, 0, -1 は許可（空値）
          next if key.nil? || key == 0 || key == -1 || key == 'KC_NO'

          resolved = keycode_converter.resolve(key)
          unless resolved
            errors << "trigger_keys[#{idx}]: Invalid keycode '#{key}'"
          end
        end

        if errors.empty?
          { valid: true }
        else
          { valid: false, error: errors.join('; ') }
        end
      }

      validates :output_key, :custom, phase: :semantic, with: ->(value, options) {
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
      }

      def initialize(index:, name:, description:, trigger_keys:, output_key:)
        @index = index            # 0-31
        @name = name              # 'Bracket Pair'
        @description = description
        @trigger_keys = trigger_keys  # Array[Integer] (最大4要素)
        @output_key = output_key      # Integer (QMK code)
      end

      # QMK配列 → Combo
      def self.from_qmk(index, qmk_array)
        # QMK配列: [key1, key2, key3, key4, output_key]
        # trigger_keys は最初の4要素（0と-1を除く）
        trigger_keys = qmk_array[0..3].reject { |k| k == 0 || k == -1 }
        output_key = qmk_array[4]

        new(
          index: index,
          name: "Combo #{index}",  # デフォルト名
          description: '',
          trigger_keys: trigger_keys,
          output_key: output_key
        )
      end

      # Combo → QMK配列
      def to_qmk
        # 4要素にパディング（不足分は0で埋める）
        padded_triggers = (@trigger_keys + [0, 0, 0, 0])[0..3]
        padded_triggers + [@output_key]
      end

      # YAML Hash → Combo
      def self.from_yaml_hash(yaml_hash)
        # メタ情報抽出（存在する場合）
        metadata = yaml_hash.respond_to?(:__metadata) ? yaml_hash.__metadata : {}

        instance = new(
          index: yaml_hash['index'],
          name: yaml_hash['name'],
          description: yaml_hash['description'] || '',
          trigger_keys: yaml_hash['trigger_keys'] || [],
          output_key: yaml_hash['output_key']
        )

        # メタ情報保存
        instance.instance_variable_set(:@metadata, metadata)

        instance
      end

      # Combo → YAML Hash
      def to_yaml_hash
        {
          'index' => @index,
          'name' => @name,
          'description' => @description,
          'trigger_keys' => @trigger_keys,
          'output_key' => @output_key
        }
      end

      # 空のコンボか判定（trigger_keysとoutput_keyが全てKC_NO = 0 または -1 または "KC_NO"）
      def empty?
        trigger_empty = @trigger_keys.nil? || @trigger_keys.empty? || @trigger_keys.all? { |k| k == 0 || k == -1 || k == 'KC_NO' }
        output_empty = @output_key.nil? || @output_key == 0 || @output_key == -1 || @output_key == 'KC_NO'
        trigger_empty && output_empty
      end
    end
  end
end
