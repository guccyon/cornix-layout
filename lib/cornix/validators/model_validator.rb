# frozen_string_literal: true

require 'yaml'
require_relative '../position_map'
require_relative '../converters/keycode_converter'
require_relative '../keycode_parser'
require_relative '../converters/reference_converter'
require_relative '../modifier_expression_compiler'
require_relative '../models/metadata'
require_relative '../models/layer'

module Cornix
  module Validators
    # 設定ファイルの妥当性を検証
    class ModelValidator
      def initialize(config_dir)
        @config_dir = config_dir
        @errors = []
        @warnings = []

        # KeycodeConverterの初期化
        aliases_path = File.join(File.dirname(__FILE__), '../keycode_aliases.yaml')
        @keycode_converter = Converters::KeycodeConverter.new(aliases_path)

        # ReferenceConverterの初期化
        @reference_converter = Converters::ReferenceConverter.new(config_dir)

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

    # モデルインスタンスの検証（新規）
    #
    # @param model [Object] Validatableを含むモデルインスタンス
    # @param file_path [String, nil] エラーメッセージ用のファイルパス
    # @return [Boolean] 検証が成功した場合true
    def validate_model(model, file_path: nil)
      context = build_validation_context(file_path)

      # 構造検証
      structural_errors = model.structural_errors
      structural_errors.each do |error|
        add_error(file_path, error)
      end

      # 意味検証
      semantic_errors = model.semantic_errors(context)
      semantic_errors.each do |error|
        add_error(file_path, error)
      end

      structural_errors.empty? && semantic_errors.empty?
    end

    # バッチモデル検証（新規）
    #
    # @param models_with_paths [Array<Array(Object, String)>] [[model, file_path], ...]
    # @return [Boolean] 全ての検証が成功した場合true
    def validate_models(models_with_paths)
      @errors = []
      @warnings = []

      models_with_paths.each do |model, file_path|
        validate_model(model, file_path: file_path)
      end

      report_results
    end

    private

    # 検証コンテキストを構築
    #
    # @param file_path [String, nil] エラーメッセージ用のファイルパス
    # @return [Hash] 検証コンテキスト
    def build_validation_context(file_path)
      {
        keycode_converter: @keycode_converter,
        reference_converter: @reference_converter,
        position_map: load_position_map,
        file_path: file_path
      }
    end

    # 検証結果を報告
    #
    # @return [Boolean] エラーがない場合true
    def report_results
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

    # エラーを追加
    #
    # @param file_path [String, nil] ファイルパス
    # @param message [String] エラーメッセージ
    def add_error(file_path, message)
      if file_path
        @errors << "#{file_path}: #{message}"
      else
        @errors << message
      end
    end

    # PositionMapを遅延ロード
    #
    # @return [PositionMap, nil]
    def load_position_map
      return @position_map if @position_map

      position_map_path = File.join(@config_dir, 'position_map.yaml')
      @position_map = PositionMap.new(position_map_path) if File.exist?(position_map_path)
      @position_map
    end

    # 階層構造をフラット化（新構造の場合）、またはそのままフラット（旧構造の場合）
    def extract_flat_mapping(mapping)
      flat = {}

      if mapping.is_a?(Hash)
        mapping.each do |key, value|
          if %w[left_hand right_hand].include?(key)
            # 階層構造: row0, row1, ..., thumb_keys の下のマッピング
            value.each do |row_key, row_data|
              if row_data.is_a?(Hash)
                row_data.each do |symbol, keycode|
                  # 階層パスとして保存: "left_hand.thumb_keys.left"
                  path = "#{key}.#{row_key}.#{symbol}"
                  flat[path] = keycode
                end
              end
            end
          elsif key == 'encoders'
            # encoders のみ left/right 構造を持つ
            value.each do |side, side_data|
              if side_data.is_a?(Hash)
                side_data.each do |action, keycode|
                  # 階層パスとして保存: "encoders.left.push"
                  path = "encoders.#{side}.#{action}"
                  flat[path] = keycode
                end
              end
            end
          else
            # フラット構造の直接マッピング（レガシー互換性）
            flat[key] = value unless value.is_a?(Hash) || value.is_a?(Array)
          end
        end
      end

      flat
    end

    # Levenshtein距離を計算（類似度判定用）
    def levenshtein_distance(str1, str2)
      return str2.length if str1.empty?
      return str1.length if str2.empty?

      matrix = Array.new(str1.length + 1) { Array.new(str2.length + 1) }

      (0..str1.length).each { |i| matrix[i][0] = i }
      (0..str2.length).each { |j| matrix[0][j] = j }

      (1..str1.length).each do |i|
        (1..str2.length).each do |j|
          cost = str1[i - 1] == str2[j - 1] ? 0 : 1
          matrix[i][j] = [
            matrix[i - 1][j] + 1,      # deletion
            matrix[i][j - 1] + 1,      # insertion
            matrix[i - 1][j - 1] + cost # substitution
          ].min
        end
      end

      matrix[str1.length][str2.length]
    end

    # 類似した名前を見つける
    def find_similar_names(target, candidates, threshold: 3)
      return [] if candidates.empty?

      target_lower = target.downcase

      similarities = candidates.map do |candidate|
        candidate_lower = candidate.downcase

        # 完全一致
        if candidate_lower == target_lower
          distance = 0
        # 部分一致（候補が対象を含む）
        elsif candidate_lower.include?(target_lower)
          distance = 1
        # 部分一致（対象が候補を含む）
        elsif target_lower.include?(candidate_lower)
          distance = 1
        else
          # Levenshtein距離
          distance = levenshtein_distance(target_lower, candidate_lower)
        end

        { name: candidate, distance: distance }
      end

      # 距離が閾値以下のものを返す（部分一致は常に含まれる）
      similar = similarities.select { |s| s[:distance] <= threshold || s[:distance] == 1 }
                            .sort_by { |s| [s[:distance], s[:name]] }
                            .map { |s| s[:name] }

      similar.take(3) # 最大3件まで
    end

    # 有効な参照関数名
    VALID_REFERENCE_FUNCTIONS = %w[Macro TapDance Combo].freeze

    # 参照関数名のタイポをチェック
    def suggest_reference_function(function_name)
      return nil if VALID_REFERENCE_FUNCTIONS.include?(function_name)

      similar = find_similar_names(function_name, VALID_REFERENCE_FUNCTIONS, threshold: 2)
      similar.first
    end

    def validate_layer_indices
      layer_files = Dir.glob("#{@config_dir}/layers/*.{yaml,yml}")
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
      # 各レイヤーをチェック
      Dir.glob("#{@config_dir}/layers/*.{yaml,yml}").each do |file|
        next if @failed_yaml_files.include?(file)

        layer = YAML.load_file(file)
        mapping_or_overrides = layer['mapping'] || layer['overrides'] || {}

        # 階層構造をフラット化
        flat_mapping = extract_flat_mapping(mapping_or_overrides)

        flat_mapping.each do |symbol, keycode|
          # Parse using KeycodeParser
          parsed = KeycodeParser.parse(keycode.to_s)

          if parsed[:type] == :reference
            function_name = parsed[:function]
            arg = parsed[:args][0]

            # 1. 関数名のタイポチェック
            unless VALID_REFERENCE_FUNCTIONS.include?(function_name)
              suggestion = suggest_reference_function(function_name)
              error_msg = "Layer #{File.basename(file)}, symbol '#{symbol}': Invalid reference function '#{function_name}'"
              if suggestion
                error_msg += " (Did you mean '#{suggestion}'?)"
              end
              @errors << error_msg
              next
            end

            # 2. Name-based参照の存在チェック
            if arg[:type] == :string
              result = @reference_converter.validate_reference(parsed)

              unless result[:valid]
                error_msg = "Layer #{File.basename(file)}, symbol '#{symbol}': #{result[:error]}"

                # 類似名のサジェスト
                reference_name = arg[:value]
                candidates = case function_name
                when 'Macro'
                  get_all_macro_names
                when 'TapDance'
                  get_all_tap_dance_names
                when 'Combo'
                  get_all_combo_names
                else
                  []
                end

                similar = find_similar_names(reference_name, candidates, threshold: 3)
                if similar.any?
                  error_msg += " (Did you mean: #{similar.map { |s| "'#{s}'" }.join(', ')}?)"
                end

                @errors << error_msg
              end
            end
          end
        end
      end
    end

    # マクロ名を全て取得
    def get_all_macro_names
      files = Dir.glob("#{@config_dir}/macros/*.{yaml,yml}")
      files.map do |file|
        next if @failed_yaml_files.include?(file)
        config = YAML.load_file(file) rescue next
        config['name']
      end.compact
    end

    # タップダンス名を全て取得
    def get_all_tap_dance_names
      files = Dir.glob("#{@config_dir}/tap_dance/*.{yaml,yml}")
      files.map do |file|
        next if @failed_yaml_files.include?(file)
        config = YAML.load_file(file) rescue next
        config['name']
      end.compact
    end

    # コンボ名を全て取得
    def get_all_combo_names
      files = Dir.glob("#{@config_dir}/combos/*.{yaml,yml}")
      files.map do |file|
        next if @failed_yaml_files.include?(file)
        config = YAML.load_file(file) rescue next
        config['name']
      end.compact
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
            next unless row_data.is_a?(Array)

            row_data.each_with_index do |symbol, col|
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

        # エンコーダーのチェック
        if position_map_data['encoders']
          ['left', 'right'].each do |side|
            if position_map_data['encoders'][side]
              encoder = position_map_data['encoders'][side]
              ['push', 'ccw', 'cw'].each do |key|
                next unless encoder[key]
                symbol_str = encoder[key].to_s
                location = "encoders.#{side}.#{key}"

                if symbol_locations[symbol_str]
                  symbol_locations[symbol_str] << location
                else
                  symbol_locations[symbol_str] = [location]
                end
              end
            end
          end
        end

        # 重複しているシンボルを報告
        # Note: 階層構造では同じシンボル名が異なるパスで使用されることは有効
        # 例: left_hand.thumb_keys.left と right_hand.row3.left は異なるパス
        # symbol_locations.each do |symbol, locations|
        #   if locations.size > 1
        #     @errors << "position_map.yaml: Duplicate symbol '#{symbol}' at: #{locations.join(', ')}"
        #   end
        # end

        # シンボル名がYAMLクォート不要な文字のみで構成されているかチェック
        symbol_locations.keys.each do |symbol|
          unless valid_position_symbol?(symbol)
            @errors << "position_map.yaml: Invalid symbol '#{symbol}' - only alphanumeric characters, underscores, and hyphens are allowed (YAML quote-free symbols only)"
          end
        end
      rescue StandardError => e
        @errors << "position_map.yaml: Error reading file: #{e.message}"
      end
    end

    def validate_keycodes
      # レイヤー内のキーコードをチェック
      Dir.glob("#{@config_dir}/layers/*.{yaml,yml}").each do |file|
        next unless File.exist?(file)
        next if @failed_yaml_files.include?(file)

        begin
          layer = YAML.load_file(file)
          mapping_or_overrides = layer['mapping'] || layer['overrides'] || {}

          # 階層構造をフラット化
          flat_mapping = extract_flat_mapping(mapping_or_overrides)

          flat_mapping.each do |symbol, keycode|
            next if keycode.nil? || keycode.to_s.empty?

            keycode_str = keycode.to_s
            error_found = false

            # タイポされた参照関数を検出（KeycodeParserでは:aliasとして解析される）
            if keycode_str =~ /^([A-Za-z_]+)\(/
              function_name = Regexp.last_match(1)

              # QMK組み込み関数（大文字）はスキップ
              # MACRO, TD, COMBO, MO, TO, OSL, TG, TT, DF, LT, LSFT, SGUI, LCA, USER, etc.
              is_qmk_builtin = function_name.match?(/^(MACRO|TD|COMBO|USER\d*|SAFE_RANGE|MO|TO|OSL|TG|TT|DF|LT\d*|LSFT|LCTL|LGUI|LALT|RSFT|RCTL|RGUI|RALT|SGUI|LCA|LSFT_T|LCTL_T|LGUI_T|LALT_T|RSFT_T|RCTL_T|RGUI_T|RALT_T|OSM)$/)

              # 参照関数のように見えるがタイポしている場合（QMK組み込みでない場合のみ）
              unless is_qmk_builtin || VALID_REFERENCE_FUNCTIONS.include?(function_name)
                suggestion = suggest_reference_function(function_name)
                if suggestion
                  error_msg = "Layer #{File.basename(file)}, symbol '#{symbol}': Invalid reference function '#{function_name}' (Did you mean '#{suggestion}'?)"
                  @errors << error_msg
                  error_found = true
                end
              end
            end

            # キーコードを検証（タイポエラーが見つかっていない場合のみ）
            unless error_found || valid_keycode?(keycode_str)
              @errors << "Layer #{File.basename(file)}, symbol '#{symbol}': Invalid keycode '#{keycode}'"
            end
          end
        rescue StandardError
          # YAML構文エラーは validate_yaml_syntax で既に報告済み
        end
      end
    end

    def valid_keycode?(keycode)
      keycode = keycode.strip

      # Parse using KeycodeParser
      parsed = KeycodeParser.parse(keycode)

      case parsed[:type]
      when :reference
        # Reference format validation (Macro, TapDance, Combo)
        # Function name validation is done in validate_layer_references
        arg = parsed[:args][0]
        if arg[:type] == :string
          # Name reference - actual validation in validate_layer_references
          return true
        elsif arg[:type] == :number
          # Index reference - validate range
          index = arg[:value]
          return index >= 0 && index < 32  # QMK max
        else
          return false
        end

      when :function
        # Validate function name and arguments
        unless valid_simple_keycode?(parsed[:name])
          return false
        end

        # Validate arguments recursively
        parsed[:args].each do |arg|
          next if arg[:type] == :number

          unless valid_keycode?(KeycodeParser.unparse(arg))
            return false
          end
        end

        return true

      when :modifier_expression
        # Validate modifier names
        parsed[:modifiers].each do |mod|
          unless valid_modifier?(mod)
            @errors << "Invalid modifier name: #{mod} in expression '#{keycode}'"
            return false
          end
        end

        # Validate key
        key = parsed[:key]
        return valid_simple_keycode?(key)

      when :keycode, :legacy_macro, :legacy_tap_dance
        # Valid formats
        return true

      when :alias
        # Validate that the alias is resolvable
        return valid_simple_keycode?(parsed[:value])

      when :number
        # Pure number is valid (for layer indices)
        return true

      else
        false
      end
    end

    def valid_simple_keycode?(keycode)
      # KeycodeConverterで解決を試行
      resolved = @keycode_converter.resolve(keycode)

      # エイリアスが解決された場合、またはQMK形式のキーコード
      if resolved != keycode || keycode.start_with?('KC_') || keycode == 'NO'
        return true
      end

      # 特殊なキーコード・関数名（MACRO, TD, COMBOなど）
      # SGUI, LCA, USER なども追加
      if keycode.match?(/^(MACRO|TD|COMBO|USER\d*|SAFE_RANGE|MO|TO|OSL|TG|TT|DF|LT\d*|LSFT|LCTL|LGUI|LALT|RSFT|RCTL|RGUI|RALT|SGUI|LCA|LSFT_T|LCTL_T|LGUI_T|LALT_T|RSFT_T|RCTL_T|RGUI_T|RALT_T|OSM)$/)
        return true
      end

      false
    end

    def valid_modifier?(modifier)
      # Check if modifier name is recognized by ModifierExpressionCompiler
      Cornix::ModifierExpressionCompiler::MODIFIER_TO_FUNCTION.key?(modifier)
    end

    def valid_position_symbol?(symbol)
      # Position map symbols must be quote-free in YAML
      # Only alphanumeric characters, underscores, and hyphens are allowed
      # This prevents symbols like "'", ";", "-" (standalone), etc.
      symbol.match?(/^[a-zA-Z0-9_-]+$/)
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
        Dir.glob("#{@config_dir}/layers/*.{yaml,yml}").each do |file|
          next unless File.exist?(file)
          next if @failed_yaml_files.include?(file)

          begin
            layer = YAML.load_file(file)
            mapping_or_overrides = layer['mapping'] || layer['overrides'] || {}

            # 階層構造をフラット化
            flat_mapping = extract_flat_mapping(mapping_or_overrides)

            flat_mapping.keys.each do |symbol|
              unless valid_symbols.include?(symbol.to_s)
                @errors << "Layer #{File.basename(file)}: Unknown position symbol '#{symbol}'"
              end
            end
          rescue StandardError
            # YAML構文エラーは validate_yaml_syntax で既に報告済み
          end
        end
      rescue StandardError => e
        @errors << "Error reading position_map.yaml: #{e.message}"
      end
    end

    def extract_all_symbols(position_map)
      paths = []

      # position_map.yamlから階層パスを抽出
      position_map_path = "#{@config_dir}/position_map.yaml"
      if File.exist?(position_map_path)
        begin
          position_map_data = YAML.load_file(position_map_path)

          # 左手と右手の全階層パスを抽出（row0, row1, ..., thumb_keys）
          ['left_hand', 'right_hand'].each do |hand|
            if position_map_data[hand]
              position_map_data[hand].each do |row_key, row_data|
                if row_data.is_a?(Array)
                  row_data.each do |symbol|
                    next if symbol.nil? || symbol.to_s.empty?
                    paths << "#{hand}.#{row_key}.#{symbol}"
                  end
                elsif row_data.is_a?(Hash)
                  # 親指キーのような構造
                  row_data.each do |key, symbol|
                    next if symbol.nil? || symbol.to_s.empty?
                    paths << "#{hand}.#{row_key}.#{symbol}"
                  end
                end
              end
            end
          end

          # エンコーダー階層パスも抽出
          if position_map_data['encoders']
            ['left', 'right'].each do |side|
              if position_map_data['encoders'][side]
                encoder = position_map_data['encoders'][side]
                ['push', 'ccw', 'cw'].each do |action|
                  if encoder[action]
                    paths << "encoders.#{side}.#{action}"
                  end
                end
              end
            end
          end
        rescue StandardError
          # Ignore errors - position_map may not exist
        end
      end

      paths.uniq
    end
    end
  end
end
