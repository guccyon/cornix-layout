# frozen_string_literal: true

require 'yaml'
require_relative 'position_map'
require_relative 'keycode_resolver'

module Cornix
  # 設定ファイルの妥当性を検証
  class Validator
    def initialize(config_dir)
      @config_dir = config_dir
      @errors = []
      @warnings = []

      # KeycodeResolverの初期化
      aliases_path = File.join(File.dirname(__FILE__), 'keycode_aliases.yaml')
      @keycode_resolver = KeycodeResolver.new(aliases_path)

      # PositionMapの初期化（遅延ロード）
      @position_map = nil

      # YAMLパースエラーがあったファイルを記録
      @failed_yaml_files = []
    end

    def validate
      @errors = []
      @warnings = []
      @failed_yaml_files = []

      # Phase 1: High-priority validations
      validate_yaml_syntax
      validate_metadata
      validate_position_map
      validate_layer_indices
      validate_macro_names
      validate_tap_dance_names
      validate_combo_names
      validate_layer_references
      validate_keycodes
      validate_position_references

      if @errors.empty?
        puts "✓ All validations passed"
        @warnings.each { |w| puts "⚠  Warning: #{w}" }
        true
      else
        puts "✗ Validation failed:"
        @errors.each { |e| puts "  Error: #{e}" }
        @warnings.each { |w| puts "  Warning: #{w}" }
        false
      end
    end

    private

    def validate_layer_indices
      layer_files = Dir.glob("#{@config_dir}/layers/*.yaml")
      indices = []

      layer_files.each do |file|
        basename = File.basename(file)
        match = basename.match(/^(\d+)_/)

        unless match
          @errors << "Invalid layer filename: #{basename} (must start with number)"
          next
        end

        index = match[1].to_i

        if index >= 10
          @errors << "Layer index out of range: #{index} (must be 0-9)"
        end

        if indices.include?(index)
          @errors << "Duplicate layer index: #{index}"
        end

        indices << index
      end
    end

    def validate_macro_names
      validate_unique_names('macros', 'Macro')
    end

    def validate_tap_dance_names
      validate_unique_names('tap_dance', 'Tap dance')
    end

    def validate_combo_names
      validate_unique_names('combos', 'Combo')
    end

    def validate_unique_names(dir, type)
      files = Dir.glob("#{@config_dir}/#{dir}/*.yaml")
      names = []

      files.each do |file|
        next if @failed_yaml_files.include?(file)

        config = YAML.load_file(file)
        name = config['name']

        unless name
          @errors << "#{type} file missing 'name' field: #{File.basename(file)}"
          next
        end

        if names.include?(name)
          @errors << "Duplicate #{type.downcase} name: #{name}"
        end

        names << name
      end
    end

    def validate_layer_references
      # マクロとタップダンスの名前→インデックスマッピングを構築
      macro_names = build_name_index('macros')
      td_names = build_name_index('tap_dance')

      # 各レイヤーをチェック
      Dir.glob("#{@config_dir}/layers/*.yaml").each do |file|
        next if @failed_yaml_files.include?(file)

        layer = YAML.load_file(file)
        mapping = layer['mapping'] || layer['overrides'] || {}

        mapping.each do |symbol, keycode|
          # MACRO(name) 参照をチェック
          if keycode.to_s.match(/MACRO\((\w+)\)/)
            name = $1
            unless macro_names.include?(name) || name.match?(/^\d+$/)
              @errors << "Layer #{File.basename(file)}: Unknown macro '#{name}'"
            end
          end

          # TD(name) 参照をチェック
          if keycode.to_s.match(/TD\((\w+)\)/)
            name = $1
            unless td_names.include?(name) || name.match?(/^\d+$/)
              @errors << "Layer #{File.basename(file)}: Unknown tap dance '#{name}'"
            end
          end
        end
      end
    end

    def build_name_index(dir)
      files = Dir.glob("#{@config_dir}/#{dir}/*.yaml")
      names = []

      files.each do |file|
        next if @failed_yaml_files.include?(file)

        config = YAML.load_file(file)
        names << config['name'] if config['name']
      end

      names
    end

    # Phase 1 validations

    def validate_yaml_syntax
      # 全YAMLファイルの構文をチェック
      yaml_files = Dir.glob("#{@config_dir}/**/*.yaml")

      yaml_files.each do |file|
        begin
          YAML.load_file(file)
        rescue Psych::SyntaxError => e
          @errors << "YAML syntax error in #{file}: #{e.message}"
          @failed_yaml_files << file
        rescue StandardError => e
          @errors << "Error reading #{file}: #{e.message}"
          @failed_yaml_files << file
        end
      end
    end

    def validate_metadata
      metadata_path = "#{@config_dir}/metadata.yaml"

      unless File.exist?(metadata_path)
        @errors << "Missing required file: metadata.yaml"
        return
      end

      begin
        metadata = YAML.load_file(metadata_path)

        # 必須フィールドのチェック
        required_fields = %w[keyboard version uid vial_protocol via_protocol]
        required_fields.each do |field|
          unless metadata.key?(field)
            @errors << "metadata.yaml: Missing required field '#{field}'"
          end
        end

        # vendor_product_id の形式チェック（存在する場合）
        if metadata['vendor_product_id']
          vpid = metadata['vendor_product_id'].to_s
          unless vpid.match?(/^0x[0-9A-Fa-f]{4}$/)
            @errors << "metadata.yaml: Invalid vendor_product_id format '#{vpid}' (expected 0xXXXX)"
          end
        end

        # matrix の検証（存在する場合）
        if metadata['matrix']
          matrix = metadata['matrix']
          unless matrix.is_a?(Hash)
            @errors << "metadata.yaml: 'matrix' must be a hash"
          else
            if matrix['rows'] && !matrix['rows'].is_a?(Integer)
              @errors << "metadata.yaml: matrix.rows must be an integer"
            elsif matrix['rows'] && matrix['rows'] <= 0
              @errors << "metadata.yaml: matrix.rows must be positive"
            end

            if matrix['cols'] && !matrix['cols'].is_a?(Integer)
              @errors << "metadata.yaml: matrix.cols must be an integer"
            elsif matrix['cols'] && matrix['cols'] <= 0
              @errors << "metadata.yaml: matrix.cols must be positive"
            end
          end
        end
      rescue Psych::SyntaxError => e
        @errors << "metadata.yaml: YAML syntax error: #{e.message}"
      rescue StandardError => e
        @errors << "metadata.yaml: Error reading file: #{e.message}"
      end
    end

    def validate_position_map
      # position_map.yamlの妥当性をチェック
      position_map_path = "#{@config_dir}/position_map.yaml"

      unless File.exist?(position_map_path)
        @warnings << "position_map.yaml not found"
        return
      end

      # YAMLパースエラーがある場合はスキップ
      if @failed_yaml_files.include?(position_map_path)
        return
      end

      begin
        position_map_data = YAML.load_file(position_map_path)

        # シンボルの重複チェック
        symbol_locations = {}  # symbol => [locations]

        ['left_hand', 'right_hand'].each do |hand|
          next unless position_map_data[hand]

          position_map_data[hand].each do |row_key, row_data|
            next unless row_data.is_a?(Hash)

            row_data.each do |col, symbol|
              next if symbol.nil? || symbol.to_s.empty?

              symbol_str = symbol.to_s
              location = "#{hand}.#{row_key}[#{col}]"

              if symbol_locations[symbol_str]
                symbol_locations[symbol_str] << location
              else
                symbol_locations[symbol_str] = [location]
              end
            end
          end
        end

        # 重複しているシンボルを報告
        symbol_locations.each do |symbol, locations|
          if locations.size > 1
            @errors << "position_map.yaml: Duplicate symbol '#{symbol}' at: #{locations.join(', ')}"
          end
        end
      rescue StandardError => e
        @errors << "position_map.yaml: Error reading file: #{e.message}"
      end
    end

    def validate_keycodes
      # レイヤー内のキーコードをチェック
      Dir.glob("#{@config_dir}/layers/*.yaml").each do |file|
        next unless File.exist?(file)
        next if @failed_yaml_files.include?(file)

        begin
          layer = YAML.load_file(file)
          mapping = layer['mapping'] || layer['overrides'] || {}

          mapping.each do |symbol, keycode|
            next if keycode.nil? || keycode.to_s.empty?

            # キーコードを検証
            unless valid_keycode?(keycode.to_s)
              @errors << "Layer #{File.basename(file)}, symbol '#{symbol}': Invalid keycode '#{keycode}'"
            end
          end
        rescue StandardError => e
          # YAML構文エラーは validate_yaml_syntax で既に報告済み
        end
      end
    end

    def valid_keycode?(keycode)
      # 再帰的にキーコードを検証
      keycode = keycode.strip

      # 関数形式のキーコード（例: MO(3), LSFT(A), LT(1, Space)）
      match = keycode.match(/^(\w+)\((.+)\)$/)
      if match
        function_name = match[1]
        args = match[2]

        # 関数名が有効なキーコードまたはエイリアスか確認
        unless valid_simple_keycode?(function_name)
          return false
        end

        # MACRO, TD, COMBOの引数は名前/インデックスなので、キーコード検証をスキップ
        if function_name.match?(/^(MACRO|TD|COMBO)$/)
          return true
        end

        # 引数を検証（カンマ区切りをサポート）
        args.split(',').each do |arg|
          arg = arg.strip
          # 数値引数は常に許容（レイヤー番号、インデックス等）
          next if arg.match?(/^\d+$/)

          # 引数が有効なキーコードか再帰的にチェック
          unless valid_keycode?(arg)
            return false
          end
        end

        return true
      end

      # シンプルなキーコード
      valid_simple_keycode?(keycode)
    end

    def valid_simple_keycode?(keycode)
      # KeycodeResolverで解決を試行
      resolved = @keycode_resolver.resolve(keycode)

      # エイリアスが解決された場合、またはQMK形式のキーコード
      if resolved != keycode || keycode.start_with?('KC_') || keycode == 'NO'
        return true
      end

      # 特殊なキーコード・関数名（MACRO, TD, COMBOなど）
      if keycode.match?(/^(MACRO|TD|COMBO|USER|SAFE_RANGE|MO|TO|OSL|TG|TT|DF|LT\d*|LSFT|LCTL|LGUI|LALT|RSFT|RCTL|RGUI|RALT|LSFT_T|LCTL_T|LGUI_T|LALT_T|RSFT_T|RCTL_T|RGUI_T|RALT_T|OSM)$/)
        return true
      end

      false
    end

    def validate_position_references
      # position_map.yamlを読み込み
      position_map_path = "#{@config_dir}/position_map.yaml"

      unless File.exist?(position_map_path)
        # validate_position_mapで既に警告済み
        return
      end

      # position_map.yamlがYAMLエラーの場合もスキップ
      if @failed_yaml_files.include?(position_map_path)
        return
      end

      begin
        @position_map = PositionMap.new(position_map_path) unless @position_map
        valid_symbols = extract_all_symbols(@position_map)

        # 各レイヤーのシンボルをチェック
        Dir.glob("#{@config_dir}/layers/*.yaml").each do |file|
          next unless File.exist?(file)
          next if @failed_yaml_files.include?(file)

          begin
            layer = YAML.load_file(file)
            mapping = layer['mapping'] || layer['overrides'] || {}

            mapping.keys.each do |symbol|
              unless valid_symbols.include?(symbol.to_s)
                @errors << "Layer #{File.basename(file)}: Unknown position symbol '#{symbol}'"
              end
            end
          rescue StandardError => e
            # YAML構文エラーは validate_yaml_syntax で既に報告済み
          end
        end
      rescue StandardError => e
        @errors << "Error reading position_map.yaml: #{e.message}"
      end
    end

    def extract_all_symbols(position_map)
      symbols = []

      # 左手と右手の全シンボルを抽出
      [:left, :right].each do |hand|
        4.times do |row|
          7.times do |col|
            symbol = position_map.symbol_at(hand, row, col)
            symbols << symbol if symbol
          end
        end
      end

      symbols.uniq
    end
  end
end
