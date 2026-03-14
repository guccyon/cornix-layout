# frozen_string_literal: true

require_relative 'thumb_keys'
require_relative 'key_mapping'
require_relative '../concerns/validatable'

module Cornix
  module Models
    class Layer
      # HandMapping: 左右統一された手のマッピング
      #
      # 左手と右手の構造は同一のため、`hand` フィールドで識別します。
      # 物理座標変換は `to_qmk` メソッドで PositionMap を使って実行します。
      #
      # 主な特徴：
      # - hand: :left または :right
      # - row0-3: 標準グリッドキー（Array<KeyMapping>）
      # - thumb_keys: ThumbKeys オブジェクト（Null Object Pattern）
      class HandMapping
        include Concerns::Validatable

        attr_reader :hand, :row0, :row1, :row2, :row3, :thumb_keys, :_yaml_keys

        # === バリデーション定義 ===

        validates :hand, :inclusion, in: [:left, :right], message: "must be :left or :right"

        # YAMLから構築した場合、必須キーの存在確認（@_yaml_keys をチェック）
        validates :_yaml_keys, :custom, with: ->(value) {
          # from_qmk 等の場合は @_yaml_keys が設定されないのでスキップ
          return { valid: true } if value.nil?

          required_keys = ['row0', 'row1', 'row2', 'row3', 'thumb_keys']
          missing_keys = required_keys - value

          if missing_keys.empty?
            { valid: true }
          else
            { valid: false, error: "Missing required keys: #{missing_keys.join(', ')}" }
          end
        }, field_name: "yaml_keys"

        validates :row0, :length, max: 6, message: "size exceeds 6"
        validates :row1, :length, max: 6, message: "size exceeds 6"
        validates :row2, :length, max: 6, message: "size exceeds 6"
        validates :row3, :length, max: 3, message: "size exceeds 3"

        # ThumbKeysの検証
        validates :thumb_keys, :custom, with: ->(value) {
          return { valid: false, error: "cannot be nil" } if value.nil?

          if value.respond_to?(:structurally_valid?)
            errors = value.structural_errors
            if errors.empty?
              { valid: true }
            else
              { valid: false, error: errors.map { |e| "thumb_keys: #{e}" }.join("; ") }
            end
          else
            { valid: true }
          end
        }

        # 全KeyMappingの検証（構造）
        [:row0, :row1, :row2, :row3].each do |row_name|
          validates row_name, :custom, with: ->(value) {
            return { valid: false, error: "cannot be nil" } if value.nil?
            return { valid: false, error: "must be an Array" } unless value.is_a?(Array)

            errors = []
            value.each_with_index do |key, idx|
              next if key.is_a?(NullKeyMapping)

              if key.respond_to?(:structurally_valid?)
                key_errors = key.structural_errors
                key_errors.each do |e|
                  errors << "#{row_name}[#{idx}] (#{key.symbol}): #{e}"
                end
              end
            end

            if errors.empty?
              { valid: true }
            else
              { valid: false, error: errors.join("; ") }
            end
          }
        end

        # セマンティック検証
        validates :thumb_keys, :custom, phase: :semantic, with: ->(value, options) {
          return { valid: true } if value.nil?

          if value.respond_to?(:semantic_errors)
            # Extract only context keys, excluding validation-specific keys like :with
            context = options.slice(:keycode_converter, :reference_converter, :position_map, :config_dir)
            errors = value.semantic_errors(context)
            if errors.empty?
              { valid: true }
            else
              { valid: false, error: errors.map { |e| "thumb_keys: #{e}" }.join("; ") }
            end
          else
            { valid: true }
          end
        }

        [:row0, :row1, :row2, :row3].each do |row_name|
          validates row_name, :custom, phase: :semantic, with: ->(value, options) {
            return { valid: true } if value.nil?
            return { valid: false, error: "must be an Array" } unless value.is_a?(Array)

            # Extract only context keys, excluding validation-specific keys like :with
            context = options.slice(:keycode_converter, :reference_converter, :position_map, :config_dir)

            errors = []
            value.each do |key|
              next if key.is_a?(NullKeyMapping)

              if key.respond_to?(:semantic_errors)
                key_errors = key.semantic_errors(context)
                key_errors.each do |e|
                  errors << "#{row_name} (#{key.symbol}): #{e}"
                end
              end
            end

            if errors.empty?
              { valid: true }
            else
              { valid: false, error: errors.join("; ") }
            end
          }
        end

        # @param hand [Symbol] :left または :right
        # @param row0 [Array<KeyMapping>] Row 0（最大6要素）
        # @param row1 [Array<KeyMapping>] Row 1（最大6要素）
        # @param row2 [Array<KeyMapping>] Row 2（最大6要素）
        # @param row3 [Array<KeyMapping>] Row 3（最大3要素、標準グリッドキーのみ）
        # @param thumb_keys [ThumbKeys] 親指キー（3要素固定）
        def initialize(hand:, row0:, row1:, row2:, row3:, thumb_keys:)
          @hand = hand
          @row0 = row0
          @row1 = row1
          @row2 = row2
          @row3 = row3
          @thumb_keys = thumb_keys
        end

        # 全てのキーマッピングを配列で返す
        #
        # @return [Array<KeyMapping>]
        def all_keys
          [row0, row1, row2, row3, thumb_keys.to_array].flatten
        end

        # QMK 2次元配列に変換（物理座標変換を含む）
        #
        # @param position_map [PositionMap] 物理座標マッピング
        # @param keycode_converter [KeycodeConverter] キーコード解決器
        # @param reference_converter [ReferenceConverter, nil] 参照解決器
        # @return [Array<Array<Integer>>] 4行7列の QMK 配列（一部）
        def to_qmk(position_map:, keycode_converter:, reference_converter: nil)
          layout = Array.new(4) { Array.new(7, -1) }

          # row0-3（標準グリッドキー）
          [row0, row1, row2, row3].each_with_index do |row, logical_row|
            row.each do |key_mapping|
              coord = key_mapping.logical_coord
              phys_row = position_map.physical_row(@hand, coord[:row])
              phys_col = position_map.physical_col(@hand, coord[:row], coord[:col])

              # ローカル4×7配列内の相対行に変換
              # 左手: absolute rows 0-3 → local 0-3
              # 右手: absolute rows 4-7 → local 0-3 (subtract 4)
              local_row = @hand == :left ? phys_row : phys_row - 4

              qmk_code = key_mapping.to_qmk(keycode_converter, reference_converter: reference_converter)
              layout[local_row][phys_col] = qmk_code
            end
          end

          # 親指キー（Row 3, Cols 3-5）
          thumb_keys.to_array.each_with_index do |key_mapping, idx|
            phys_row = position_map.thumb_physical_row(@hand)
            phys_col = position_map.thumb_physical_col(@hand, idx)

            # ローカル4×7配列内の相対行に変換
            # 左手: absolute rows 0-3 → local 0-3
            # 右手: absolute rows 4-7 → local 0-3 (subtract 4)
            local_row = @hand == :left ? phys_row : phys_row - 4

            qmk_code = key_mapping.to_qmk(keycode_converter, reference_converter: reference_converter)
            layout[local_row][phys_col] = qmk_code
          end

          layout
        end

        # QMK 2次元配列から HandMapping を構築（Factory Method）
        #
        # @param hand [Symbol] :left または :right
        # @param layout_2d [Array<Array<Integer>>] 8行7列の QMK 配列
        # @param position_map [PositionMap] 物理座標マッピング
        # @param keycode_converter [KeycodeConverter] キーコード解決器
        # @param reference_converter [ReferenceConverter, nil] 参照解決器
        # @return [HandMapping]
        def self.from_qmk(hand:, layout_2d:, position_map:, keycode_converter:, reference_converter: nil)
          rows = []
          hand_key = hand == :left ? 'left_hand' : 'right_hand'

          # row0-3（標準グリッドキー）
          ['row0', 'row1', 'row2', 'row3'].each_with_index do |row_key, logical_row|
            row_symbols = position_map.data[hand_key][row_key]
            row_mappings = []

            row_symbols.each_with_index do |symbol, logical_col|
              phys_row = position_map.physical_row(hand, logical_row)
              phys_col = position_map.physical_col(hand, logical_row, logical_col)
              qmk_keycode = layout_2d[phys_row][phys_col]

              next if qmk_keycode == -1

              keycode = keycode_converter.reverse_resolve(qmk_keycode)
              row_mappings << KeyMapping.new(
                symbol: symbol,
                keycode: keycode,
                logical_coord: { hand: hand, row: logical_row, col: logical_col }
              )
            end

            rows << row_mappings
          end

          # 親指キー
          thumb_array = []
          thumb_symbols = position_map.data[hand_key]['thumb_keys']
          thumb_symbols.each_with_index do |symbol, idx|
            phys_row = position_map.thumb_physical_row(hand)
            phys_col = position_map.thumb_physical_col(hand, idx)
            qmk_keycode = layout_2d[phys_row][phys_col]

            next if qmk_keycode == -1

            keycode = keycode_converter.reverse_resolve(qmk_keycode)
            thumb_array << KeyMapping.new(
              symbol: symbol,
              keycode: keycode,
              logical_coord: { hand: hand, row: 3, col: 3 + idx }
            )
          end

          thumb_keys_obj = ThumbKeys.from_array(thumb_array)

          new(
            hand: hand,
            row0: rows[0],
            row1: rows[1],
            row2: rows[2],
            row3: rows[3],
            thumb_keys: thumb_keys_obj
          )
        end

        # YAMLハッシュから HandMapping を構築（Factory Method）
        #
        # @param hand [Symbol] :left または :right
        # @param yaml_hand [Hash] YAML形式のハッシュ
        # @param position_map [PositionMap] 物理座標マッピング
        # @return [HandMapping]
        def self.from_yaml_hash(hand:, yaml_hand:, position_map:)
          return empty(hand) if yaml_hand.nil?

          # Store original YAML keys for validation
          original_yaml_keys = yaml_hand.keys

          hand_key = hand == :left ? 'left_hand' : 'right_hand'
          rows = []

          # row0-3（標準グリッドキー）
          ['row0', 'row1', 'row2', 'row3'].each_with_index do |row_key, logical_row|
            yaml_row = yaml_hand[row_key] || {}
            row_symbols = position_map.data[hand_key][row_key]
            row_mappings = []

            # position_mapに存在するsymbolに対するマッピング
            row_symbols.each_with_index do |symbol, logical_col|
              keycode = yaml_row[symbol]
              next if keycode.nil?

              row_mappings << KeyMapping.new(
                symbol: symbol,
                keycode: keycode,
                logical_coord: { hand: hand, row: logical_row, col: logical_col }
              )
            end

            # YAMLにあるがposition_mapに存在しないキーを検出
            yaml_row.each do |symbol, keycode|
              unless row_symbols.include?(symbol)
                # 無効なsymbolでKeyMappingを作成（バリデーションでエラーになる）
                row_mappings << KeyMapping.new(
                  symbol: symbol,
                  keycode: keycode,
                  logical_coord: { hand: hand, row: logical_row, col: 0 }
                )
              end
            end

            rows << row_mappings
          end

          # 親指キー
          yaml_thumbs = yaml_hand['thumb_keys'] || {}
          thumb_symbols = position_map.data[hand_key]['thumb_keys']
          factory = ->(symbol:, keycode:, logical_coord:) do
            KeyMapping.new(symbol: symbol, keycode: keycode, logical_coord: { hand: hand }.merge(logical_coord))
          end
          thumb_keys_obj = ThumbKeys.from_yaml_hash(yaml_thumbs, thumb_symbols, factory)

          instance = new(
            hand: hand,
            row0: rows[0],
            row1: rows[1],
            row2: rows[2],
            row3: rows[3],
            thumb_keys: thumb_keys_obj
          )

          # Store original YAML keys for validation
          instance.instance_variable_set(:@_yaml_keys, original_yaml_keys)

          instance
        end

        # YAML形式のハッシュに変換
        #
        # @return [Hash] YAML形式のハッシュ
        def to_yaml_hash
          {
            'row0' => build_row_hash(row0),
            'row1' => build_row_hash(row1),
            'row2' => build_row_hash(row2),
            'row3' => build_row_hash(row3),
            'thumb_keys' => thumb_keys.to_yaml_hash
          }
        end

        # 空の HandMapping を生成（Factory Method）
        #
        # @param hand [Symbol] :left または :right
        # @return [HandMapping]
        def self.empty(hand)
          new(
            hand: hand,
            row0: [],
            row1: [],
            row2: [],
            row3: [],
            thumb_keys: ThumbKeys.new
          )
        end

        private

        # Array<KeyMapping> を Hash に変換
        #
        # @param row_mappings [Array<KeyMapping>]
        # @return [Hash<String, String>]
        def build_row_hash(row_mappings)
          hash = {}
          row_mappings.each do |key_mapping|
            hash[key_mapping.symbol] = key_mapping.to_yaml
          end
          hash
        end
      end
    end
  end
end
