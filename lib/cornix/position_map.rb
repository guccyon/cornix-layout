# frozen_string_literal: true

require 'yaml'

module Cornix
  # position_map.yamlの処理を担当（階層パス対応）
  class PositionMap
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
