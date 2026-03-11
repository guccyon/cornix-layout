# frozen_string_literal: true

module Cornix
  module Models
    # 1つのタップダンスを保持するモデル
    class TapDance
      attr_reader :index, :name, :description, :on_tap, :on_hold, :on_double_tap,
                  :on_tap_hold, :tapping_term

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
        new(
          index: yaml_hash['index'],
          name: yaml_hash['name'],
          description: yaml_hash['description'] || '',
          on_tap: yaml_hash['on_tap'],
          on_hold: yaml_hash['on_hold'],
          on_double_tap: yaml_hash['on_double_tap'],
          on_tap_hold: yaml_hash['on_tap_hold'],
          tapping_term: yaml_hash['tapping_term']
        )
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
