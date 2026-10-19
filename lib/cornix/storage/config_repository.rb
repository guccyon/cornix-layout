# frozen_string_literal: true

require_relative 'config_loader'
require_relative 'config_writer'
require_relative 'diagnostic_locator'
require_relative 'problems'
require_relative 'yaml_file'
require_relative 'config_files'
require_relative 'file_source'

module Cornix
  module Storage
    # 設定ディレクトリ（config/*.yaml）と Domain::Profile の読み書き。
    #
    #   repo = ConfigRepository.new('config', notation: Mapping::KeycodeNotation.new,
    #                               settings_catalog: Mapping::QmkSettingCatalog.default)
    #                               # shortcut_catalog: 同梱のショートカット（既定は Mapping::ShortcutCatalog.default）
    #   profile = repo.load            # 問題があれば InvalidConfig（すべての問題を「ファイル: キーの位置: 内容」で並べる）
    #   repo.save(profile)             # => 書いたファイルの相対パスの一覧
    #   repo.locate(diagnostic)        # Profile#diagnostics のパスをファイル上の位置にした Diagnostic
    #   repo.address(model_path)       # => [ファイル, キーの道筋]（DiagnosticLocator#address）
    #   repo.position_map_path         # config/position_map.yaml（.yml）の絶対パス。なければ nil
    #   ConfigRepository.read_position_map(path)   # position_map.yaml の形式のファイル → Domain::PositionMap
    #
    # 読むファイルは source（FileSource）から。既定はディスクの dir で、FileSource::Overlay を渡すと保存前の中身で
    # 読み、検証できる（save と position_map_path はいつもディスク）。
    # ファイルの構成は ConfigFiles、各ファイルの形は Schema::*File を参照
    class ConfigRepository
      attr_reader :dir, :source

      def initialize(dir, notation:, settings_catalog:, shortcut_catalog: Mapping::ShortcutCatalog.default,
                     source: FileSource::Disk.new(dir))
        @dir = dir.to_s
        @source = source
        @notation = notation
        @settings_catalog = settings_catalog
        @shortcut_catalog = shortcut_catalog
      end

      def load
        ConfigLoader.new(@dir, notation: @notation, settings_catalog: @settings_catalog,
                               shortcut_catalog: @shortcut_catalog, source: @source).load
      end

      def save(profile)
        Domain::Checks.instance!(profile, Domain::Profile, '保存するプロファイル')
        ConfigWriter.new(@dir, notation: @notation, settings_catalog: @settings_catalog).save(profile)
      end

      # Domain::Diagnostic（path はモデル内のパス）→ path を「ファイル: キーの位置」にした Domain::Diagnostic
      def locate(diagnostic) = locator.locate(diagnostic)

      # モデル内のパス → [ファイル, キーの道筋]（Address の形）。指せなければ nil
      def address(model_path) = locator.address(model_path)

      private def locator = DiagnosticLocator.new(@dir, source: @source)

      def position_map_path
        rel = ConfigFiles.single_file(@dir, ConfigFiles::POSITION_MAP)
        rel && File.join(@dir, rel)
      end

      # position_map.yaml の形式のファイル（設定ディレクトリのもの、または lib/cornix/position_map.yaml のテンプレート）を
      # 読んで Domain::PositionMap にする。問題があれば InvalidConfig
      def self.read_position_map(path)
        problems = Problems.new
        file = File.basename(path.to_s)
        data = begin
          YamlFile.read(path)
        rescue YamlFile::Unreadable => e
          problems.add(file, nil, e.message)
          :unreadable
        end
        position_map = data != :unreadable && Schema::PositionMapFile.read(data, Schema::Context.new(file, problems))
        problems.raise_if_any!
        position_map
      end
    end
  end
end
