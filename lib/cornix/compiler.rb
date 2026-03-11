# frozen_string_literal: true

require 'json'
require_relative 'loaders/yaml_loader'
require_relative 'writers/vial_writer'
require_relative 'converters/keycode_converter'
require_relative 'converters/reference_converter'
require_relative 'position_map'

module Cornix
  # 新Compiler - YAML設定 → layout.vil のオーケストレーター
  #
  # アーキテクチャ:
  #   - YamlLoader: config/*.yaml → VialConfig
  #   - VialConfig.to_qmk: VialConfig → QMK Hash（各モデルに委譲）
  #   - VialWriter: QMK Hash → layout.vil (JSON)
  #
  # 責務:
  #   - ローダー・ライター・コンバーターの初期化と連携のみ
  #   - データ変換ロジックは各モデル（Layer, Macro等）が担当
  class Compiler
    def initialize(config_dir)
      @config_dir = config_dir

      # Converters
      aliases_path = File.join(__dir__, 'keycode_aliases.yaml')
      @keycode_converter = Converters::KeycodeConverter.new(aliases_path)
      @reference_converter = Converters::ReferenceConverter.new(config_dir)

      # PositionMap
      @position_map = PositionMap.new("#{config_dir}/position_map.yaml")
    end

    def compile(output_path)
      # YAML → VialConfig
      vial_config = Loaders::YamlLoader.new(@config_dir).load(
        position_map: @position_map,
        keycode_converter: @keycode_converter,
        reference_converter: @reference_converter
      )

      # VialConfig → layout.vil
      Writers::VialWriter.new.write(
        vial_config,
        output_path,
        position_map: @position_map,
        keycode_converter: @keycode_converter,
        reference_converter: @reference_converter
      )

      puts "✓ Compiled: #{output_path}"
    end
  end
end
