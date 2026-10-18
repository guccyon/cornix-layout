# frozen_string_literal: true

require_relative 'checks'

module Cornix
  module Domain
    # キーの論理位置（.claude/architecture/coordinate_system.md の論理座標）。
    # 左右の手それぞれに 4 行 × 6 列。row3 の col 0〜2 が row3 のキー、col 3〜5 が親指キー。
    # layout.vil の物理座標（マトリクス）への変換は PositionMap だけが行う。
    class KeyPosition < Data.define(:hand, :row, :col)
      HANDS = %i[left right].freeze
      ROWS = (0..3)
      COLS = (0..5)
      THUMB_ROW = 3
      THUMB_COLS = (3..5)

      def initialize(hand:, row:, col:)
        Checks.one_of!(hand, HANDS, '手')
        Checks.integer!(row, ROWS, '論理行')
        Checks.integer!(col, COLS, '論理列')
        super
      end

      def left? = hand == :left
      def right? = hand == :right
      def thumb? = row == THUMB_ROW && THUMB_COLS.cover?(col)
      def to_s = "#{hand}(#{row}, #{col})"
    end
  end
end
