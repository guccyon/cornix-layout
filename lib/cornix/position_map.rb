# frozen_string_literal: true

require 'yaml'

module Cornix
  # position_map.yamlの処理を担当
  class PositionMap
    def initialize(yaml_path)
      @data = YAML.load_file(yaml_path)
    end

    def symbol_at(hand, row, col)
      # Guard against negative indices
      return nil if row < 0 || col < 0

      hand_key = hand == :left ? 'left_hand' : 'right_hand'
      row_key = "row#{row}"

      @data[hand_key]&.dig(row_key, col)
    end

    def find_position(symbol)
      # Reject nil or empty symbols early
      return nil if symbol.nil? || symbol.to_s.empty?

      # シンボル名から物理位置を検索
      [:left, :right].each do |hand|
        4.times do |row|
          7.times do |col|
            return { hand: hand, row: row, col: col } if symbol_at(hand, row, col) == symbol
          end
        end
      end
      nil
    end
  end
end
