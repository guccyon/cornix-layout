# frozen_string_literal: true

require 'yaml'

module Cornix
  # position_map.yamlの処理を担当（階層パス対応）
  class PositionMap
    attr_reader :data

    def initialize(yaml_path)
      @data = YAML.load_file(yaml_path)
      # 階層パスからフラットマップへの変換キャッシュ
      @path_to_position = build_path_map
      # 物理位置から階層パスへの逆引きマップ（後方互換性用）
      @position_to_path = @path_to_position.invert
    end

    # 階層パス（例: "left_hand.thumb_keys.left"）から物理位置を取得
    def find_position(path_or_symbol)
      # まず階層パスとして検索
      position = @path_to_position[path_or_symbol]
      return position if position

      # 後方互換: シンボルとしても検索（全パスから末尾一致）
      @path_to_position.each do |path, pos|
        if path.end_with?(".#{path_or_symbol}")
          return pos
        end
      end

      nil
    end

    # 全ての有効な階層パスを返す
    def all_paths
      @path_to_position.keys
    end

    # 物理位置から階層パスを取得（逆引き）
    def path_at(hand, row, col)
      key = { hand: hand, row: row, col: col }
      @position_to_path[key]
    end

    # 後方互換性: 物理位置からシンボルを取得（旧API）
    def symbol_at(hand, row, col)
      # Guard against negative indices
      return nil if row < 0 || col < 0

      path = path_at(hand, row, col)
      return nil unless path

      # パスの末尾（シンボル）を返す
      path.split('.').last
    end

    # === 座標変換メソッド（Phase 1拡張） ===

    # 親指キーの物理行（固定値）
    THUMB_PHYSICAL_ROW = { left: 3, right: 7 }.freeze

    # エンコーダープッシュの物理位置（固定値）
    ENCODER_PUSH_POSITION = {
      left:  { row: 2, col: 6 },
      right: { row: 5, col: 6 }
    }.freeze

    # 論理行 → 物理行
    # @param hand [Symbol] :left または :right
    # @param logical_row [Integer] 0-3
    # @return [Integer] 物理行 (0-7)
    def physical_row(hand, logical_row)
      raise ArgumentError, "Invalid hand: #{hand}" unless [:left, :right].include?(hand)
      raise ArgumentError, "Invalid logical_row: #{logical_row}" unless (0..3).include?(logical_row)

      hand == :right ? logical_row + 4 : logical_row
    end

    # 論理列 → 物理列（右手の逆順処理を内包）
    # @param hand [Symbol] :left または :right
    # @param logical_row [Integer] 0-3
    # @param logical_col [Integer] 0-5 (row0-2), 0-2 (row3)
    # @return [Integer] 物理列 (0-5 または 0-2)
    def physical_col(hand, logical_row, logical_col)
      raise ArgumentError, "Invalid hand: #{hand}" unless [:left, :right].include?(hand)
      raise ArgumentError, "Invalid logical_row: #{logical_row}" unless (0..3).include?(logical_row)

      # 左手: そのまま
      return logical_col if hand == :left

      # 右手: 逆順処理
      max_col = (logical_row == 3) ? 2 : 5  # row3は3要素（0-2）、それ以外は6要素（0-5）
      max_col - logical_col
    end

    # 親指キーの物理行
    # @param hand [Symbol] :left または :right
    # @return [Integer] 物理行
    def thumb_physical_row(hand)
      raise ArgumentError, "Invalid hand: #{hand}" unless THUMB_PHYSICAL_ROW.key?(hand)
      THUMB_PHYSICAL_ROW[hand]
    end

    # 親指キーの物理列
    # @param hand [Symbol] :left または :right
    # @param thumb_idx [Integer] 0-2 (論理インデックス)
    # @return [Integer] 物理列
    def thumb_physical_col(hand, thumb_idx)
      raise ArgumentError, "Invalid hand: #{hand}" unless [:left, :right].include?(hand)
      raise ArgumentError, "Invalid thumb_idx: #{thumb_idx}" unless (0..2).include?(thumb_idx)

      hand == :left ? 3 + thumb_idx : 5 - thumb_idx
    end

    # エンコーダープッシュの物理位置
    # @param side [Symbol] :left または :right
    # @return [Hash] { row: Integer, col: Integer }
    def encoder_push_position(side)
      raise ArgumentError, "Invalid side: #{side}" unless ENCODER_PUSH_POSITION.key?(side)
      ENCODER_PUSH_POSITION[side]
    end

    private

    def build_path_map
      map = {}

      # left_hand と right_hand のマッピング
      ['left_hand', 'right_hand'].each do |hand_key|
        hand = hand_key == 'left_hand' ? :left : :right
        hand_data = @data[hand_key]

        # row0-3
        ['row0', 'row1', 'row2', 'row3'].each_with_index do |row_key, row_idx|
          row = hand_data[row_key]
          row.each_with_index do |symbol, col_idx|
            next if symbol.nil? || symbol.to_s.empty?
            path = "#{hand_key}.#{row_key}.#{symbol}"
            map[path] = { hand: hand, row: row_idx, col: col_idx }
          end
        end

        # thumb_keys
        thumb_keys = hand_data['thumb_keys']
        thumb_keys.each_with_index do |symbol, idx|
          col_idx = 3 + idx  # 親指キーはcol 3-5
          path = "#{hand_key}.thumb_keys.#{symbol}"
          map[path] = { hand: hand, row: 3, col: col_idx }
        end
      end

      # encoders のマッピング
      ['left', 'right'].each do |side|
        hand = side == 'left' ? :left : :right
        encoder = @data['encoders'][side]
        row_idx = hand == :left ? 2 : 5  # エンコーダープッシュの行

        encoder.each do |key, symbol|
          path = "encoders.#{side}.#{key}"
          case key
          when 'push'
            map[path] = { hand: hand, row: row_idx, col: 6 }
          when 'ccw', 'cw'
            # エンコーダー回転は特別扱い（encoder_layoutから取得）
            encoder_idx = hand == :left ? 0 : 1
            rotation_idx = key == 'ccw' ? 0 : 1
            map[path] = { hand: hand, encoder: encoder_idx, rotation: rotation_idx }
          end
        end
      end

      map
    end
  end
end
