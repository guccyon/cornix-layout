# frozen_string_literal: true

require 'json'
require 'fileutils'
require_relative 'loaders/vial_loader'
require_relative 'writers/yaml_writer'
require_relative 'converters/keycode_converter'
require_relative 'converters/reference_converter'
require_relative 'position_map'

module Cornix
  # 新Decompiler - layout.vil → YAML設定 のオーケストレーター
  #
  # アーキテクチャ:
  #   - VialLoader: layout.vil (JSON) → VialConfig
  #   - VialConfig.to_yaml_hashes: VialConfig → YAML Hash（各モデルに委譲）
  #   - YamlWriter: YAML Hash → config/*.yaml
  #
  # 責務:
  #   - ローダー・ライター・コンバーターの初期化と連携のみ
  #   - データ変換ロジックは各モデル（Layer, Macro等）が担当
  class Decompiler
    def initialize(vil_path)
      @vil_path = vil_path

      # Position Map テンプレート
      @position_map_template_path = File.join(__dir__, 'position_map.yaml')
      unless File.exist?(@position_map_template_path)
        raise "Missing required template: #{@position_map_template_path}"
      end
      @position_map = PositionMap.new(@position_map_template_path)

      # Converters
      aliases_path = File.join(__dir__, 'keycode_aliases.yaml')
      @keycode_converter = Converters::KeycodeConverter.new(aliases_path)
    end

    def decompile(output_dir)
      FileUtils.mkdir_p(output_dir)

      # Position Map テンプレートをコピー
      FileUtils.cp(@position_map_template_path, "#{output_dir}/position_map.yaml")

      # layout.vil → VialConfig
      vial_config = Loaders::VialLoader.new(@vil_path).load(
        position_map: @position_map,
        keycode_converter: @keycode_converter
      )

      # ReferenceConverter（output_dirでマクロ等のファイルを参照）
      reference_converter = Converters::ReferenceConverter.new(output_dir)

      # VialConfig → YAML files
      Writers::YamlWriter.new(output_dir).write(
        vial_config,
        keycode_converter: @keycode_converter,
        reference_converter: reference_converter
      )

      puts "✓ Decompilation completed: #{output_dir}"
    end
  end
end
