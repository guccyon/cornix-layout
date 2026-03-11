# frozen_string_literal: true

require 'yaml'
require 'fileutils'
require_relative 'writer_helpers'

module Cornix
  module Writers
    # YamlWriter - VialConfig → config/*.yaml
    class YamlWriter
      def initialize(output_dir)
        @output_dir = output_dir
      end

      # VialConfig を YAML ファイルとして config/ に書き込み
      def write(vial_config, keycode_converter:, reference_converter:)
        # ディレクトリ作成
        FileUtils.mkdir_p(@output_dir)
        FileUtils.mkdir_p("#{@output_dir}/settings")
        FileUtils.mkdir_p("#{@output_dir}/layers")
        FileUtils.mkdir_p("#{@output_dir}/macros")
        FileUtils.mkdir_p("#{@output_dir}/tap_dance")
        FileUtils.mkdir_p("#{@output_dir}/combos")

        # YAML Hash に変換
        yaml_hashes = vial_config.to_yaml_hashes(
          keycode_converter: keycode_converter,
          reference_converter: reference_converter
        )

        # メタデータ
        write_yaml("#{@output_dir}/metadata.yaml", yaml_hashes[:metadata])

        # 設定
        write_yaml("#{@output_dir}/settings/qmk_settings.yaml", yaml_hashes[:settings])

        # レイヤー
        yaml_hashes[:layers].each_with_index do |layer_hash, index|
          filename = "#{index}_#{sanitize_filename(layer_hash['name'])}.yaml"
          write_yaml("#{@output_dir}/layers/#{filename}", layer_hash)
        end

        # マクロ
        yaml_hashes[:macros].each do |macro_hash|
          index = macro_hash['index']
          name = macro_hash['name']
          # デフォルト名（"Macro N"形式）の場合は種別名のみ、カスタム名の場合はカスタム名
          suffix = name.match?(/^Macro \d+$/) ? 'macro' : sanitize_filename(name)
          filename = "#{index.to_s.rjust(2, '0')}_#{suffix}.yaml"
          write_yaml("#{@output_dir}/macros/#{filename}", macro_hash)
        end

        # タップダンス
        yaml_hashes[:tap_dances].each do |tap_dance_hash|
          index = tap_dance_hash['index']
          name = tap_dance_hash['name']
          # デフォルト名（"TapDance N"形式）の場合は種別名のみ、カスタム名の場合はカスタム名
          suffix = name.match?(/^TapDance \d+$/) ? 'tap_dance' : sanitize_filename(name)
          filename = "#{index.to_s.rjust(2, '0')}_#{suffix}.yaml"
          write_yaml("#{@output_dir}/tap_dance/#{filename}", tap_dance_hash)
        end

        # コンボ
        yaml_hashes[:combos].each do |combo_hash|
          index = combo_hash['index']
          name = combo_hash['name']
          # デフォルト名（"Combo N"形式）の場合は種別名のみ、カスタム名の場合はカスタム名
          suffix = name.match?(/^Combo \d+$/) ? 'combo' : sanitize_filename(name)
          filename = "#{index.to_s.rjust(2, '0')}_#{suffix}.yaml"
          write_yaml("#{@output_dir}/combos/#{filename}", combo_hash)
        end
      end

      private

      # YAML書き込み（クォート最適化付き）
      def write_yaml(path, data)
        yaml_string = YAML.dump(data)
        optimized = WriterHelpers.minimize_quotes(yaml_string)
        File.write(path, optimized)
      end

      # ファイル名のサニタイズ
      def sanitize_filename(name)
        name
          .downcase
          .gsub(/[^a-z0-9]+/, '_')  # 英数字以外をアンダースコアに
          .gsub(/^_+|_+$/, '')      # 先頭・末尾のアンダースコア削除
          .gsub(/_+/, '_')          # 連続するアンダースコアを1つに
      end
    end
  end
end
