# frozen_string_literal: true

module Cornix
  module Models
    # 1つのマクロを保持するモデル
    class Macro
      attr_reader :index, :name, :description, :sequence

      def initialize(index:, name:, description:, sequence:)
        @index = index            # 0-31
        @name = name              # 'End of Line'
        @description = description
        @sequence = sequence      # Array[Integer] (QMK codes)
      end

      # QMK配列（Vial形式） → Macro
      def self.from_qmk(index, qmk_array)
        # Vialのネスト配列形式をそのまま保存
        # Vial: [['tap', 'KC_A', 'KC_B'], ['down', 'KC_LSHIFT']]
        new(
          index: index,
          name: "Macro #{index}",  # デフォルト名
          description: '',
          sequence: qmk_array
        )
      end

      # Macro → QMK配列（Vial形式: ネストされた配列）
      def to_qmk
        # YAMLのHash形式をVialのネスト配列形式に変換
        # YAML: [{action: 'tap', keys: ['KC_A', 'KC_B']}]
        # Vial: [['tap', 'KC_A', 'KC_B']]
        @sequence.map do |step|
          if step.is_a?(Hash)
            action = step['action']
            keys = step['keys']
            keys = [keys] unless keys.is_a?(Array)
            [action] + keys
          else
            # 既にVial形式（配列）の場合はそのまま
            step
          end
        end
      end

      # YAML Hash → Macro
      def self.from_yaml_hash(yaml_hash)
        new(
          index: yaml_hash['index'],
          name: yaml_hash['name'],
          description: yaml_hash['description'] || '',
          sequence: yaml_hash['sequence']
        )
      end

      # Macro → YAML Hash（読みやすい構造化形式）
      def to_yaml_hash
        # Vialの配列形式をYAMLのHash形式に変換
        # Vial: [['tap', 'KC_A', 'KC_B']]
        # YAML: [{action: 'tap', keys: ['KC_A', 'KC_B']}]
        yaml_sequence = @sequence.map do |step|
          if step.is_a?(Array)
            {
              'action' => step[0],
              'keys' => step[1..-1]
            }
          else
            # 既にHash形式の場合はそのまま
            step
          end
        end

        {
          'index' => @index,
          'name' => @name,
          'description' => @description,
          'sequence' => yaml_sequence
        }
      end

      # 空のマクロか判定
      def empty?
        @sequence.nil? || @sequence.empty?
      end
    end
  end
end
