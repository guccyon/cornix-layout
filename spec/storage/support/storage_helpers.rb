# frozen_string_literal: true

require 'tmpdir'
require 'fileutils'
require 'yaml'

# spec/storage で使う道具
module StorageHelpers
  TEST_CONFIG = File.expand_path('../../fixtures/test_config', __dir__)
  AUTHORS_CONFIG = File.expand_path('../../../../../authors-keymap/config', __dir__)
  BASELINE_VIL = File.expand_path('../../../../domain-architecture/tmp/baseline/layout.vil', __dir__)

  def notation = Cornix::Mapping::KeycodeNotation.new
  def settings_catalog = Cornix::Mapping::QmkSettingCatalog.default

  def repository(dir) = Cornix::Storage::ConfigRepository.new(dir, notation: notation, settings_catalog: settings_catalog)

  # test_config を一時ディレクトリに複写して yield する
  def with_config_copy(source = TEST_CONFIG)
    Dir.mktmpdir('cornix-storage') do |tmp|
      dir = File.join(tmp, 'config')
      FileUtils.cp_r(source, dir)
      yield dir
    end
  end

  def write_file(dir, rel, text)
    path = File.join(dir, rel)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, text)
  end

  # 読み込みの問題（Problem#to_s の一覧）。問題がなければ []
  def load_problems(dir)
    repository(dir).load
    []
  rescue Cornix::Storage::InvalidConfig => e
    e.problems.map(&:to_s)
  end
end
