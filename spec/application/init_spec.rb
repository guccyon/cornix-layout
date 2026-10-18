# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require_relative 'device_environment_context'

RSpec.describe Cornix::Application::Init do
  include_context 'device environment'

  let(:fixtures) { File.expand_path('../fixtures', __dir__) }

  def init(profile: nil, config: nil, opener: self.opener, **opts)
    ws = Cornix::Application::Workspace.resolve(cwd: @root, root: @root, default_root: @root, env: {},
                                                profile: profile, config: config)
    described_class.new(Cornix::Application::Environment.for(ws, device_opener: opener)).call(**opts)
  end

  def read(rel) = File.read(File.join(@root, rel))

  it 'デバイスから読んで設定を書き、.cornix.yml と .gitignore を作る' do
    result = init(profile: 'main')
    dir = File.join(@root, 'profiles', 'main')
    expect(result.config_dir).to eq(dir)
    expect(result.imported_from).to eq(:device)
    expect(result.created).to eq(['profiles/main/', '.cornix.yml', '.gitignore'])
    expect(read('.cornix.yml')).to eq("profile: main\n")
    expect(read('.gitignore')).to eq("tmp/\n.decompile.lock\n")
    expect(result.files).to include('metadata.yaml')
    expect(File).to exist(File.join(dir, 'position_map.yaml'))
    expect(File).to exist(File.join(@root, 'tmp', 'profiles', 'main', 'layout.vil'))
    expect(result.notes).to be_empty
  end

  it '書いた設定は tmp/profiles/<名前>/build/layout.vil に compile され、元の .vil と同じになる' do
    source = File.join(fixtures, 'layout.vil')
    init(profile: 'main', from: source)
    ws = Cornix::Application::Workspace.resolve(cwd: @root, env: {}, default_root: @root)
    compiled = Cornix::Application::Compile.new(Cornix::Application::Environment.for(ws)).call.path
    expect(compiled).to eq(File.join(@root, 'tmp', 'profiles', 'main', 'build', 'layout.vil'))
    expect(env.vil_file.read(compiled)).to eq(env.vil_file.read(source))
  end

  it 'profiles/ の外なら「config: 相対パス」。既定の置き場所でも root の外なら .cornix.yml を作る' do
    init(config: File.join(@root, 'keymaps', 'a'), pull: false)
    expect(read('.cornix.yml')).to eq("config: keymaps/a\n")
  end

  it '--from の .vil から書ける' do
    source = File.join(fixtures, 'layout.vil')
    result = init(from: source)
    expect(result.imported_from).to eq(source)
    expect(result.config_dir).to eq(File.join(@root, 'config'))
    expect(read('.cornix.yml')).to eq("config: config\n")
    expect { init(profile: 'x', from: File.join(@root, 'none.vil')) }.to raise_error(Cornix::ConfigError, /ファイルがありません/)
    expect(File).not_to exist(File.join(@root, 'profiles', 'x'))
  end

  it 'デバイスにつながらなければ空のディレクトリを作って案内する' do
    failing = ->(&) { raise Cornix::DeviceError, 'Cornix が見つかりません' }
    result = init(profile: 'main', opener: failing)
    expect(result.imported_from).to be_nil
    expect(result.device_error).to eq('Cornix が見つかりません')
    expect(Dir.empty?(result.config_dir)).to be(true)
    expect(result.notes).to contain_exactly(include('cornix pull').and(include('cornix decompile FILE')))
  end

  it '中身のある設定ディレクトリは上書きしない' do
    FileUtils.mkdir_p(File.join(@root, 'profiles', 'main'))
    File.write(File.join(@root, 'profiles', 'main', 'metadata.yaml'), "a: 1\n")
    expect { init(profile: 'main') }.to raise_error(Cornix::ConfigError, /すでにあります/)
  end

  it '.cornix.yml があれば変えず、使い方を案内する。.gitignore には足りない行だけ足す' do
    File.write(File.join(@root, '.cornix.yml'), "profile: main\n")
    File.write(File.join(@root, '.gitignore'), "/tmp/\n*.log")
    result = init(profile: 'second', pull: false)
    expect(read('.cornix.yml')).to eq("profile: main\n")
    expect(read('.gitignore')).to eq("/tmp/\n*.log\n.decompile.lock\n")
    expect(result.created).to eq(['profiles/second/', '.gitignore（.decompile.lock を追加）'])
    expect(result.notes).to include(include('--profile second'))
  end

  it '中身のある config/ とは別の場所に作って .cornix.yml を書いたら、次から使われる場所が変わることを案内する' do
    FileUtils.mkdir_p(File.join(@root, 'config'))
    File.write(File.join(@root, 'config', 'metadata.yaml'), "a: 1\n")
    result = init(profile: 'default', pull: false)
    expect(read('.cornix.yml')).to eq("profile: default\n")
    expect(result.notes).to include(include('次からは profiles/default/ が使われます')
                                      .and(include("--config #{File.join(@root, 'config')}")))
  end
end
