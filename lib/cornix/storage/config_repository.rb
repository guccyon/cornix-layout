# frozen_string_literal: true

require_relative 'config_loader'
require_relative 'config_writer'
require_relative 'diagnostic_locator'

module Cornix
  module Storage
    # 設定ディレクトリ（config/*.yaml）と Domain::Profile の読み書き。
    #
    #   repo = ConfigRepository.new('config', notation: Mapping::KeycodeNotation.new,
    #                               settings_catalog: Mapping::QmkSettingCatalog.default)
    #   profile = repo.load            # 問題があれば InvalidConfig（すべての問題を「ファイル: キーの位置: 内容」で並べる）
    #   repo.save(profile)             # => 書いたファイルの相対パスの一覧
    #   repo.locate(diagnostic)        # Profile#diagnostics のパスをファイル上の位置にした Diagnostic
    #
    # ファイルの構成は ConfigFiles、各ファイルの形は Schema::*File を参照
    class ConfigRepository
      attr_reader :dir

      def initialize(dir, notation:, settings_catalog:)
        @dir = dir.to_s
        @notation = notation
        @settings_catalog = settings_catalog
      end

      def load = ConfigLoader.new(@dir, notation: @notation, settings_catalog: @settings_catalog).load

      def save(profile)
        Domain::Checks.instance!(profile, Domain::Profile, '保存するプロファイル')
        ConfigWriter.new(@dir, notation: @notation, settings_catalog: @settings_catalog).save(profile)
      end

      # Domain::Diagnostic（path はモデル内のパス）→ path を「ファイル: キーの位置」にした Domain::Diagnostic
      def locate(diagnostic) = DiagnosticLocator.new(@dir).locate(diagnostic)
    end
  end
end
