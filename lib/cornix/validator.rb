# frozen_string_literal: true

require 'yaml'
require_relative 'position_map'

module Cornix
  # 設定ファイルの妥当性を検証
  class Validator
    def initialize(config_dir)
      @config_dir = config_dir
      @errors = []
      @warnings = []
    end

    def validate
      @errors = []
      @warnings = []

      validate_layer_indices
      validate_macro_names
      validate_tap_dance_names
      validate_combo_names
      validate_layer_references

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
        config = YAML.load_file(file)
        names << config['name'] if config['name']
      end

      names
    end
  end
end
