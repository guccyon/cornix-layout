# frozen_string_literal: true

require_relative 'config_loader'
require_relative 'config_writer'
require_relative 'diagnostic_locator'
require_relative 'problems'
require_relative 'yaml_file'
require_relative 'config_files'

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
    #   repo.position_map_path         # config/position_map.yaml（.yml）の絶対パス。なければ nil
    #   ConfigRepository.read_position_map(path)   # position_map.yaml の形式のファイル → Domain::PositionMap
    #
    # ファイルの構成は ConfigFiles、各ファイルの形は Schema::*File を参照
    class ConfigRepository
      attr_reader :dir

      def initialize(dir, notation:, settings_catalog:, shortcut_catalog: Mapping::ShortcutCatalog.default)
        @dir = dir.to_s
        @notation = notation
        @settings_catalog = settings_catalog
        @shortcut_catalog = shortcut_catalog
      end

      def load
        ConfigLoader.new(@dir, notation: @notation, settings_catalog: @settings_catalog,
                               shortcut_catalog: @shortcut_catalog).load
      end

      def save(profile)
        Domain::Checks.instance!(profile, Domain::Profile, '保存するプロファイル')
        ConfigWriter.new(@dir, notation: @notation, settings_catalog: @settings_catalog).save(profile)
      end

      # Domain::Diagnostic（path はモデル内のパス）→ path を「ファイル: キーの位置」にした Domain::Diagnostic
      def locate(diagnostic) = DiagnosticLocator.new(@dir).locate(diagnostic)

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
