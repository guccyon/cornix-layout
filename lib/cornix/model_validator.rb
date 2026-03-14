# frozen_string_literal: true

require 'yaml'
require_relative 'position_map'
require_relative 'converters/keycode_converter'
require_relative 'keycode_parser'
require_relative 'converters/reference_converter'
require_relative 'loaders/yaml_loader'
require_relative 'models/vial_config'

module Cornix
  # ModelValidator - ファイルシステム検証とモデル検証のオーケストレーター
  #
  # 責務:
  # - ファイルシステムレベル検証（YAML構文、ファイル名、一意性）
  # - モデル検証の統括（モデルのValidatableに委譲）
  # - 検証モード制御（:strict vs :collect）
  class ModelValidator
    def initialize(config_dir)
      @config_dir = config_dir
      @errors = []
      @warnings = []
      @failed_yaml_files = []

      # Converters初期化
      aliases_path = File.join(File.dirname(__FILE__), 'keycode_aliases.yaml')
      @keycode_converter = Converters::KeycodeConverter.new(aliases_path)
      @reference_converter = Converters::ReferenceConverter.new(config_dir)
      @position_map = nil  # 遅延ロード
    end

    # メイン検証エントリーポイント
    # @param mode [Symbol] :strict (fail-fast) または :collect (全エラー蓄積)
    # @return [Boolean] 検証が成功した場合true
    def validate(mode: :collect)
      @errors = []
      @warnings = []
      @failed_yaml_files = []

      # Phase 1: ファイルシステム検証（常にcollect）
      validate_file_system
      return report_results if @errors.any?

      # Phase 2: モデル検証（モードに応じる）
      validate_models(mode: mode)

      report_results
    end

    private

    # ファイルシステムレベルの検証
    def validate_file_system
      validate_yaml_syntax
      validate_layer_indices
      validate_macro_names
      validate_tap_dance_names
      validate_combo_names
    end

    # モデルレベルの検証
    # @param mode [Symbol] :strict (fail-fast) または :collect (全エラー蓄積)
    def validate_models(mode:)
      # VialConfigをロード（メタ情報付き、検証なし）
      loader = Loaders::YamlLoader.new(@config_dir)

      begin
        vial_config = loader.load(
          position_map: load_position_map,
          keycode_converter: @keycode_converter,
          reference_converter: @reference_converter,
          validate: false  # ここでは検証しない
        )
      rescue => e
        @errors << "Failed to load configuration: #{e.message}"
        return
      end

      # コンテキスト構築
      context = build_validation_context

      # モードに応じた検証実行
      case mode
      when :strict
        # Fail-fast: 最初のエラーで例外
        begin
          vial_config.validate!(context, mode: :strict)
        rescue Models::Concerns::ValidationError => e
          @errors.concat(e.errors)
        end
      when :collect
        # Collect: 全エラー収集
        errors = vial_config.validate!(context, mode: :collect)
        @errors.concat(errors)
      end
    rescue Models::Concerns::ValidationError => e
      # strict modeで到達（例外が上がる）
      @errors.concat(e.errors)
    end

    # 検証コンテキストを構築
    def build_validation_context
      {
        keycode_converter: @keycode_converter,
        reference_converter: @reference_converter,
        position_map: load_position_map,
        config_dir: @config_dir
      }
    end

    # 検証結果を報告
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

    # PositionMapを遅延ロード
    def load_position_map
      return @position_map if @position_map

      position_map_path = "#{@config_dir}/position_map.yaml"
      unless File.exist?(position_map_path)
        # デフォルトのposition_mapを使用
        position_map_path = File.join(File.dirname(__FILE__), 'position_map.yaml')
      end

      @position_map = PositionMap.new(position_map_path)
    rescue => e
      @warnings << "Could not load position_map: #{e.message}"
      nil
    end

    # === ファイルシステム検証メソッド ===

    # YAML構文チェック
    def validate_yaml_syntax
      yaml_files = Dir.glob("#{@config_dir}/**/*.{yaml,yml}")

      yaml_files.each do |file|
        begin
          YAML.load_file(file)
        rescue Psych::SyntaxError => e
          @errors << "#{file}: YAML syntax error: #{e.message}"
          @failed_yaml_files << file
        rescue => e
          @errors << "#{file}: Error reading file: #{e.message}"
          @failed_yaml_files << file
        end
      end
    end

    # レイヤーファイル名の重複・範囲チェック
    def validate_layer_indices
      layers_dir = "#{@config_dir}/layers"
      return unless Dir.exist?(layers_dir)

      layer_files = Dir.glob("#{layers_dir}/*.{yaml,yml}").sort
      indices = []

      layer_files.each do |file|
        next if @failed_yaml_files.include?(file)

        # ファイル名からインデックスを抽出（例: 0_base.yaml → 0）
        basename = File.basename(file, '.*')
        if basename =~ /^(\d+)_/
          index = $1.to_i

          # 範囲チェック（0-9）
          unless (0..9).include?(index)
            @errors << "#{file}: Layer index #{index} out of range (must be 0-9)"
          end

          # 重複チェック
          if indices.include?(index)
            @errors << "#{file}: Duplicate layer index #{index}"
          end
          indices << index
        else
          @warnings << "#{file}: Layer filename does not start with index (e.g., 0_base.yaml)"
        end
      end

      # 連続性チェック（警告のみ）
      if indices.any?
        expected = (0...indices.size).to_a
        missing = expected - indices
        if missing.any?
          @warnings << "layers/: Missing layer indices: #{missing.join(', ')}"
        end
      end
    end

    # マクロ名の一意性チェック
    def validate_macro_names
      validate_collection_names(
        dir: "#{@config_dir}/macros",
        type: "macro",
        field: "name"
      )
    end

    # タップダンス名の一意性チェック
    def validate_tap_dance_names
      validate_collection_names(
        dir: "#{@config_dir}/tap_dance",
        type: "tap_dance",
        field: "name"
      )
    end

    # コンボ名の一意性チェック
    def validate_combo_names
      validate_collection_names(
        dir: "#{@config_dir}/combos",
        type: "combo",
        field: "name"
      )
    end

    # コレクション名の一意性チェック（共通処理）
    def validate_collection_names(dir:, type:, field:)
      return unless Dir.exist?(dir)

      files = Dir.glob("#{dir}/*.{yaml,yml}").sort
      names = {}  # name => [files]

      files.each do |file|
        next if @failed_yaml_files.include?(file)

        begin
          data = YAML.load_file(file)
          name = data[field]

          if name.nil? || name.to_s.empty?
            @warnings << "#{file}: #{type} has no '#{field}' field"
          else
            names[name] ||= []
            names[name] << file
          end
        rescue => e
          # Already handled in validate_yaml_syntax
        end
      end

      # 重複チェック
      names.each do |name, file_list|
        if file_list.size > 1
          @errors << "Duplicate #{type} name '#{name}' in: #{file_list.map { |f| File.basename(f) }.join(', ')}"
        end
      end
    end

    # valid_position_symbol? ヘルパー（後方互換性のため残す）
    def valid_position_symbol?(symbol)
      symbol.match?(/^[a-zA-Z0-9_-]+$/)
    end
  end
end
