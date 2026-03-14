# frozen_string_literal: true

require 'yaml'
require_relative 'models/concerns/validatable'

module Cornix
  # position_map.yamlの処理を担当（階層パス対応）
  class PositionMap
    include Models::Concerns::Validatable

    attr_reader :data

    # === バリデーション定義 ===

    # 必須キー定義
    REQUIRED_TOP_KEYS = %w[left_hand right_hand encoders].freeze
    REQUIRED_HAND_KEYS = %w[row0 row1 row2 row3 thumb_keys].freeze
    REQUIRED_ENCODER_KEYS = %w[left right].freeze
    REQUIRED_ENCODER_SUB_KEYS = %w[push ccw cw].freeze

    # 各rowの要素数
    EXPECTED_ROW_COUNTS = {
      'row0' => 6,
      'row1' => 6,
      'row2' => 6,
      'row3' => 3,
      'thumb_keys' => 3
    }.freeze

    # 構造検証: data が Hash であること
    validates :data, :type, is: Hash, message: "must be a Hash"

    # 構造検証: 必須キーの存在と構造の完全性
    validates :data, :custom, with: ->(value) {
      return { valid: true } if value.nil? || !value.is_a?(Hash)

      errors = []

      # 1. トップレベルキーの存在確認
      REQUIRED_TOP_KEYS.each do |key|
        unless value.key?(key)
          errors << "Missing required key: #{key}"
        end
      end
      return { valid: false, error: errors.join("; ") } unless errors.empty?

      # 2. left_hand/right_handの構造確認
      %w[left_hand right_hand].each do |hand|
        hand_data = value[hand]
        unless hand_data.is_a?(Hash)
          errors << "#{hand} must be a Hash"
          next
        end

        REQUIRED_HAND_KEYS.each do |row_key|
          unless hand_data.key?(row_key)
            errors << "#{hand}: Missing required key #{row_key}"
            next
          end

          row_data = hand_data[row_key]
          unless row_data.is_a?(Array)
            errors << "#{hand}.#{row_key} must be an Array"
            next
          end

          expected_count = EXPECTED_ROW_COUNTS[row_key]
          actual_count = row_data.size
          if actual_count != expected_count
            errors << "#{hand}.#{row_key}: Expected #{expected_count} elements, got #{actual_count}"
          end

          # シンボル名形式チェック
          row_data.each_with_index do |symbol, idx|
            next if symbol.nil? || symbol.to_s.empty?
            unless symbol.to_s.match?(/^[a-zA-Z0-9_-]+$/)
              errors << "#{hand}.#{row_key}[#{idx}]: Invalid symbol '#{symbol}' (must match /^[a-zA-Z0-9_-]+$/)"
            end
          end
        end
      end

      # 3. encodersの構造確認
      encoders_data = value['encoders']
      unless encoders_data.is_a?(Hash)
        errors << "encoders must be a Hash"
        return { valid: false, error: errors.join("; ") }
      end

      REQUIRED_ENCODER_KEYS.each do |encoder_key|
        unless encoders_data.key?(encoder_key)
          errors << "encoders: Missing required key #{encoder_key}"
          next
        end

        encoder_data = encoders_data[encoder_key]
        unless encoder_data.is_a?(Hash)
          errors << "encoders.#{encoder_key} must be a Hash"
          next
        end

        REQUIRED_ENCODER_SUB_KEYS.each do |sub_key|
          unless encoder_data.key?(sub_key)
            errors << "encoders.#{encoder_key}: Missing required key #{sub_key}"
          end
        end

        # シンボル名形式チェック
        encoder_data.each do |sub_key, symbol|
          next if symbol.nil? || symbol.to_s.empty?
          unless symbol.to_s.match?(/^[a-zA-Z0-9_-]+$/)
            errors << "encoders.#{encoder_key}.#{sub_key}: Invalid symbol '#{symbol}' (must match /^[a-zA-Z0-9_-]+$/)"
          end
        end
      end

      if errors.empty?
        { valid: true }
      else
        { valid: false, error: errors.join("; ") }
      end
    }, field_name: "structure"

    # セマンティック検証: スコープ内でシンボル重複なし
    validates :data, :custom, phase: :semantic, with: ->(value) {
      return { valid: true } if value.nil? || !value.is_a?(Hash)

      duplicates = PositionMap.find_duplicate_symbols_in_data(value)
      if duplicates.empty?
        { valid: true }
      else
        errors = duplicates.map { |sym, locs| "Duplicate symbol '#{sym}' at: #{locs.join(', ')}" }
        { valid: false, error: errors.join("; ") }
      end
    }, field_name: "symbols"

    # シンボル抽出ヘルパー（クラスメソッド）
    def self.extract_all_symbols_from_data(data)
      symbols = []

      # left_hand と right_hand
      ['left_hand', 'right_hand'].each do |hand_key|
        hand_data = data[hand_key]
        next unless hand_data

        # row0-3
        ['row0', 'row1', 'row2', 'row3'].each do |row_key|
          row = hand_data[row_key]
          next unless row
          symbols.concat(row.compact.reject(&:empty?))
        end

        # thumb_keys
        thumb_keys = hand_data['thumb_keys']
        symbols.concat(thumb_keys.compact.reject(&:empty?)) if thumb_keys
      end

      # encoders
      if data['encoders']
        ['left', 'right'].each do |side|
          encoder = data['encoders'][side]
          next unless encoder
          encoder.each_value do |symbol|
            symbols << symbol if symbol && !symbol.to_s.empty?
          end
        end
      end

      symbols.map(&:to_s)
    end

    # 重複シンボル検出ヘルパー（クラスメソッド）
    def self.find_duplicate_symbols_in_data(data)
      symbol_locations = Hash.new { |h, k| h[k] = [] }

      # left_hand と right_hand
      ['left_hand', 'right_hand'].each do |hand_key|
        hand_data = data[hand_key]
        next unless hand_data

        # row0-3
        ['row0', 'row1', 'row2', 'row3'].each do |row_key|
          row = hand_data[row_key]
          next unless row
          row.each_with_index do |symbol, idx|
            next if symbol.nil? || symbol.to_s.empty?
            symbol_locations[symbol.to_s] << "#{hand_key}.#{row_key}[#{idx}]"
          end
        end

        # thumb_keys
        thumb_keys = hand_data['thumb_keys']
        if thumb_keys
          thumb_keys.each_with_index do |symbol, idx|
            next if symbol.nil? || symbol.to_s.empty?
            symbol_locations[symbol.to_s] << "#{hand_key}.thumb_keys[#{idx}]"
          end
        end
      end

      # encoders
      if data['encoders']
        ['left', 'right'].each do |side|
          encoder = data['encoders'][side]
          next unless encoder
          encoder.each do |key, symbol|
            next if symbol.nil? || symbol.to_s.empty?
            symbol_locations[symbol.to_s] << "encoders.#{side}.#{key}"
          end
        end
      end

      # 重複のみを返す
      symbol_locations.select { |_symbol, locs| locs.size > 1 }
    end

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

    # シンボルが存在するか確認
    # @param symbol [String] シンボル名
    # @return [Boolean] シンボルが存在する場合true
    def symbol_exists?(symbol)
      return false if symbol.nil? || symbol.to_s.empty?

      # 階層パスとして検索
      return true if @path_to_position.key?(symbol.to_s)

      # 末尾一致で検索（後方互換性）
      @path_to_position.keys.any? { |path| path.end_with?(".#{symbol}") }
    end

    # 全てのシンボルを抽出（末尾のみ）
    # @return [Array<String>] シンボル名の配列
    def extract_all_symbols
      PositionMap.extract_all_symbols_from_data(@data)
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
        next unless hand_data.is_a?(Hash)

        # row0-3
        ['row0', 'row1', 'row2', 'row3'].each_with_index do |row_key, row_idx|
          row = hand_data[row_key]
          next unless row.is_a?(Array)

          row.each_with_index do |symbol, col_idx|
            next if symbol.nil? || symbol.to_s.empty?
            path = "#{hand_key}.#{row_key}.#{symbol}"
            map[path] = { hand: hand, row: row_idx, col: col_idx }
          end
        end

        # thumb_keys
        thumb_keys = hand_data['thumb_keys']
        if thumb_keys.is_a?(Array)
          thumb_keys.each_with_index do |symbol, idx|
            col_idx = 3 + idx  # 親指キーはcol 3-5
            path = "#{hand_key}.thumb_keys.#{symbol}"
            map[path] = { hand: hand, row: 3, col: col_idx }
          end
        end
      end

      # encoders のマッピング
      if @data['encoders'].is_a?(Hash)
        ['left', 'right'].each do |side|
          hand = side == 'left' ? :left : :right
          encoder = @data['encoders'][side]
          next unless encoder.is_a?(Hash)

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
      end

      map
    end
  end
end
