# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'

RSpec.describe Cornix::Application::Workspace do
  around { |example| Dir.mktmpdir { |dir| (@dir = File.realpath(dir)) && example.run } }

  let(:tool) { File.join(@dir, 'tool') }
  let(:work) { File.join(@dir, 'work') }

  before { FileUtils.mkdir_p([tool, File.join(work, 'sub')]) }

  def resolve(cwd: work, env: {}, **opts) = described_class.resolve(cwd: cwd, env: env, default_root: tool, **opts)

  it '何も指定がなければ default_root（既定は Cornix::ROOT）の config/。tmp/ も今までどおり' do
    ws = resolve
    expect([ws.config_dir, ws.source, ws.root, ws.tmp_dir]).to eq([File.join(tool, 'config'), :default, tool, File.join(tool, 'tmp')])
    expect(ws).to be_default
    expect(described_class.resolve(env: {}).config_dir).to eq(File.join(Cornix::ROOT, 'config'))
  end

  it '--config はカレントからの相対パス。tmp/ は tmp/profiles/<名前>-<パスのハッシュ>/ に分ける' do
    ws = resolve(config: 'mine')
    expect(ws.config_dir).to eq(File.join(work, 'mine'))
    expect(ws.source).to eq(:option)
    expect(ws.tmp_dir).to match(%r{\A#{Regexp.escape(File.join(tool, 'tmp', 'profiles', 'mine-'))}\h{8}\z})
    expect(ws.description).to eq("#{File.join(work, 'mine')}（--config）")
  end

  it '同じ名前の別のディレクトリは tmp/ を分ける' do
    a = resolve(config: File.join(@dir, 'a', 'config'))
    b = resolve(config: File.join(@dir, 'b', 'config'))
    expect(a.tmp_dir).not_to eq(b.tmp_dir)
  end

  it '<root>/config を指していれば、どう指定しても既定の置き場所として扱う' do
    ws = resolve(config: File.join(tool, 'config'))
    expect(ws).to be_default
    expect(ws.tmp_dir).to eq(File.join(tool, 'tmp'))
  end

  it '--profile NAME は root の profiles/NAME' do
    ws = resolve(profile: 'alice')
    expect(ws.config_dir).to eq(File.join(tool, 'profiles', 'alice'))
    expect(ws.description).to eq('profiles/alice（--profile）')
    expect { resolve(profile: '../x') }.to raise_error(Cornix::ConfigError, /プロファイル名/)
  end

  it '優先順: --config > CORNIX_CONFIG > --profile > .cornix.yml' do
    File.write(File.join(work, '.cornix.yml'), "profile: bob\n")
    env = { 'CORNIX_CONFIG' => '/env/cfg' }
    expect(resolve(config: '/opt/cfg', profile: 'a', env: env).config_dir).to eq('/opt/cfg')
    expect(resolve(profile: 'a', env: env).source).to eq(:env)
    expect(resolve(profile: 'a').config_dir).to eq(File.join(work, 'profiles', 'a'))
    expect(resolve.config_dir).to eq(File.join(work, 'profiles', 'bob'))
  end

  it '.cornix.yml はカレントから親へたどり、そのディレクトリが root になる' do
    File.write(File.join(work, '.cornix.yml'), "config: keymap\n")
    ws = resolve(cwd: File.join(work, 'sub'))
    expect([ws.config_dir, ws.source, ws.root, ws.settings_file])
      .to eq([File.join(work, 'keymap'), :cornix_yml, work, File.join(work, '.cornix.yml')])
  end

  it '--root を渡すとそこの .cornix.yml だけを見る' do
    File.write(File.join(work, '.cornix.yml'), "profile: bob\n")
    expect(resolve(cwd: File.join(work, 'sub'), root: tool).config_dir).to eq(File.join(tool, 'config'))
    expect(resolve(cwd: tool, root: work).config_dir).to eq(File.join(work, 'profiles', 'bob'))
  end

  it '.cornix.yml の誤りは ConfigError' do
    path = File.join(work, '.cornix.yml')
    { "profile: a\nconfig: b\n" => /どちらか 1 つ/, "- a\n" => /マッピング/, '' => /マッピング/,
      "a: [\n" => /YAML として読めません/ }.each do |text, message|
      File.write(path, text)
      expect { resolve }.to raise_error(Cornix::ConfigError, message)
    end
  end
end
