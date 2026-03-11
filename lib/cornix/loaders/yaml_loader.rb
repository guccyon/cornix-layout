# frozen_string_literal: true

require 'yaml'
require_relative '../models/vial_config'

module Cornix
  module Loaders
    # YamlLoader - config/*.yaml → VialConfig
    class YamlLoader
      def initialize(config_dir)
        @config_dir = config_dir
      end

      # config/ ディレクトリから YAML ファイルを読み込んで VialConfig に変換
      def load(position_map:, keycode_converter:, reference_converter:)
        unless Dir.exist?(@config_dir)
          raise "Config directory not found: #{@config_dir}"
        end

        # メタデータ
        metadata_hash = load_yaml_file("#{@config_dir}/metadata.yaml")

        # 設定
        settings_hash = load_yaml_file("#{@config_dir}/settings/qmk_settings.yaml")

        # レイヤー
        layers_hashes = load_layers

        # マクロ
        macros_hashes = load_collection("#{@config_dir}/macros")

        # タップダンス
        tap_dances_hashes = load_collection("#{@config_dir}/tap_dance")

        # コンボ
        combos_hashes = load_collection("#{@config_dir}/combos")

        Models::VialConfig.from_yaml_hashes(
          metadata_hash: metadata_hash,
          settings_hash: settings_hash,
          layers_hashes: layers_hashes,
          macros_hashes: macros_hashes,
          tap_dances_hashes: tap_dances_hashes,
          combos_hashes: combos_hashes,
          position_map: position_map,
          keycode_converter: keycode_converter,
          reference_converter: reference_converter
        )
      end

      private

      def load_yaml_file(path)
        return {} unless File.exist?(path)
        YAML.load_file(path) || {}
      end

      def load_layers
        layers_dir = "#{@config_dir}/layers"
        return [] unless Dir.exist?(layers_dir)

        layer_files = Dir.glob("#{layers_dir}/*.{yaml,yml}").sort
        layer_files.map do |file|
          load_yaml_file(file)
        end
      end

      def load_collection(dir_path)
        return [] unless Dir.exist?(dir_path)

        files = Dir.glob("#{dir_path}/*.{yaml,yml}").sort
        files.map do |file|
          load_yaml_file(file)
        end
      end
    end
  end
end
