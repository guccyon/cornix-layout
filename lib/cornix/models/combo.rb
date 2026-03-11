# frozen_string_literal: true

module Cornix
  module Models
    # 1つのコンボを保持するモデル
    class Combo
      attr_reader :index, :name, :description, :trigger_keys, :output_key

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
        new(
          index: yaml_hash['index'],
          name: yaml_hash['name'],
          description: yaml_hash['description'] || '',
          trigger_keys: yaml_hash['trigger_keys'] || [],
          output_key: yaml_hash['output_key']
        )
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
