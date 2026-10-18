# frozen_string_literal: true

require 'tmpdir'
require 'fileutils'

# 一時ディレクトリを root にした Environment と、spec/fixtures の設定・.vil を置く道具
RSpec.shared_context 'config root' do
  let(:fixtures) { File.expand_path('../../fixtures', __dir__) }
  let(:claude) { FakeClaude.new }
  let(:env) { Cornix::Application::Environment.new(root: @root, claude: claude) }

  around do |example|
    Dir.mktmpdir('cornix-root') { |dir| (@root = dir) && example.run }
  end

  # spec/fixtures/<name> を root/config に複写する
  def install_config(name = 'test_config')
    FileUtils.cp_r(File.join(fixtures, name), env.config_dir)
    env.config_dir
  end

  # spec/fixtures/<name> を root の rel に複写する
  def install_file(name, rel)
    path = File.join(@root, rel)
    FileUtils.mkdir_p(File.dirname(path))
    FileUtils.cp(File.join(fixtures, name), path)
    path
  end

  def config_file(rel) = File.join(env.config_dir, rel)
  def read_config(rel) = File.read(config_file(rel))
  def image(path) = env.vil_file.read(path)
end

# Application::ClaudeCli の代わり（available? と run(prompt) → [成功, 出力]）
class FakeClaude
  attr_accessor :available, :output, :success
  attr_reader :prompts

  def initialize(available: true, output: '', success: true)
    @available = available
    @output = output
    @success = success
    @prompts = []
  end

  def available? = available

  def run(prompt)
    @prompts << prompt
    [success, output]
  end
end
