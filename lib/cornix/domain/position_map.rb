# frozen_string_literal: true

require_relative 'checks'
require_relative 'key_position'

module Cornix
  module Domain
    # キーの名前（position_map.yaml のシンボル）と位置の対応表。Cornix の配列の知識はすべてここに置く。
    #
    #   論理位置   KeyPosition(hand, row, col)。左右それぞれ row0〜row2 が 6 キー、row3 が 3 キー、親指が 3 キー
    #   物理位置   layout.vil の layout[row][col]（8 行 × 7 列）
    #              左手: そのまま（row 0〜3）。親指は row 3 の col 3〜5
    #              右手: 行 +4、列は反転（row0〜2 は 5 - col、row3 は 2 - col、親指は 5 - 親指番号）
    #              エンコーダのプッシュは左 (2, 6)・右 (5, 6)。それ以外の col 6 はキーがない（.vil の -1）
    #
    # シンボルは手とグループ（row0〜row3, thumb）の中で一意。グループが違えば同じ名前でもよい
    # （設定ファイルでは親指を旧名の thumb_keys でも書ける。読み替えは Storage がする）。
    class PositionMap
      HANDS = { 'left_hand' => :left, 'right_hand' => :right }.freeze
      # グループ => [論理行, 先頭の論理列, キーの数]
      GROUPS = {
        'row0' => [0, 0, 6],
        'row1' => [1, 0, 6],
        'row2' => [2, 0, 6],
        'row3' => [3, 0, 3],
        'thumb' => [3, 3, 3]
      }.freeze
      ENCODER_SIDES = %i[left right].freeze
      ENCODER_ACTIONS = %w[push ccw cw].freeze
      SYMBOL_FORMAT = /\A[a-zA-Z0-9_-]+\z/
      MATRIX_ROWS = 8
      MATRIX_COLS = 7
      ENCODER_PUSH = { left: [2, 6].freeze, right: [5, 6].freeze }.freeze

      # position_map.yaml を読み込んだ Hash（親指は thumb）から作る
      def self.from_h(hash)
        Parser.new(hash).call.then { |groups, encoders| new(groups: groups, encoders: encoders) }
      end
      private_class_method :new

      # groups:   { 'left_hand' => { 'row0' => [シンボル, ...], ... }, 'right_hand' => {...} }
      # encoders: { left: { 'push' => シンボル, 'ccw' => ..., 'cw' => ... }, right: {...} }
      def initialize(groups:, encoders:)
        @groups = groups
        @encoders = encoders
        build_tables
        freeze
      end

      # ('left_hand', 'row0', 'tab') の位置。なければ nil
      def position(hand_key, group_key, symbol)
        @by_symbol.dig(hand_key.to_s, group_key.to_s, symbol.to_s)
      end

      # 位置の [グループ, シンボル]。なければ nil
      def symbol(position) = @by_position[position]

      # 'left_hand' / 'right_hand'
      def hand_key(position) = HANDS.key(position.hand)

      # "left_hand.row0.tab" の形のパス
      def path(position)
        group, sym = symbol(position)
        [hand_key(position), group, sym].join('.')
      end

      # layout.vil の [row, col]
      def matrix(position) = @matrix.fetch(position)

      # layout.vil の [row, col] にあるキーの位置。キーがない（-1 の位置・プッシュ・範囲外）なら nil
      def position_at(row, col) = @by_matrix[[row, col]]

      def encoder_push_matrix(side) = ENCODER_PUSH.fetch(Checks.one_of!(side, ENCODER_SIDES, 'エンコーダの左右'))

      # すべての位置（左手 row0〜row3・親指、右手 row0〜row3・親指の定義順）
      def positions = @positions

      # グループのシンボル（定義順）
      def symbols(hand_key, group_key) = @groups.dig(hand_key.to_s, group_key.to_s)

      # エンコーダの操作（'push' / 'ccw' / 'cw'）のシンボル
      def encoder_symbol(side, action) = @encoders.dig(side, action.to_s)

      # position_map.yaml の形の Hash
      def to_h
        h = @groups.transform_values { |groups| groups.transform_values(&:dup) }
        h['encoders'] = @encoders.to_h { |side, actions| [side.to_s, actions.dup] }
        h
      end

      def ==(other) = other.is_a?(PositionMap) && other.to_h == to_h
      alias eql? ==
      def hash = to_h.hash

      private

      def build_tables
        @positions = []
        @by_symbol = {}
        @by_position = {}
        @matrix = {}
        HANDS.each do |hand_key, hand|
          GROUPS.each do |group_key, (row, first_col, _)|
            @groups.dig(hand_key, group_key).each_with_index do |sym, i|
              add(hand_key, group_key, sym, KeyPosition.new(hand: hand, row: row, col: first_col + i))
            end
          end
        end
        @by_matrix = @matrix.invert.freeze
        [@positions, @by_symbol, @by_position, @matrix].each(&:freeze)
      end

      def add(hand_key, group_key, sym, pos)
        @positions << pos
        ((@by_symbol[hand_key] ||= {})[group_key] ||= {})[sym] = pos
        @by_position[pos] = [group_key, sym].freeze
        @matrix[pos] = physical(pos).freeze
      end

      def physical(pos)
        return [pos.row, pos.col] if pos.left?

        col = if pos.thumb? then 5 - (pos.col - KeyPosition::THUMB_COLS.begin)
              elsif pos.row == 3 then 2 - pos.col
              else 5 - pos.col
              end
        [pos.row + 4, col]
      end
    end
  end
end

require_relative 'position_map/parser'
