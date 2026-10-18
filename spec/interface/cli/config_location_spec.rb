# frozen_string_literal: true

require 'spec_helper'
require 'stringio'
require 'tmpdir'
require 'fileutils'
require_relative '../../device/fake_rmk_device'

RSpec.describe 'cornix の設定ディレクトリの指定と init' do
  let(:out) { StringIO.new }
  let(:err) { StringIO.new }
  let(:fixtures) { File.expand_path('../../fixtures', __dir__) }

  around { |example| Dir.mktmpdir { |dir| (@root = File.realpath(dir)) && example.run } }

  def cornix(*argv)
    Cornix::Interface::Cli::Main.new(out: out, err: err, input: StringIO.new).run(argv)
  end

  def image(path) = Cornix::Application::Environment.new.vil_file.read(path)

  describe Cornix::Interface::Cli::GlobalOptions do
    it 'コマンド名の前後から取り出し、-- より後ろは残す' do
      opts, rest = described_class.extract(%w[--profile a compile -o x.vil --config=/c --root /r -- --profile b])
      expect(opts).to eq(profile: 'a', config: '/c', root: '/r')
      expect(rest).to eq(%w[compile -o x.vil -- --profile b])
    end

    it '値がなければ UsageError' do
      expect { described_class.extract(%w[compile --config]) }.to raise_error(Cornix::Interface::Cli::UsageError)
      expect { described_class.extract(%w[compile --profile -o]) }.to raise_error(Cornix::Interface::Cli::UsageError)
    end
  end

  it '--config の設定を compile し、出力は tmp/profiles/<名前>/build/ に分ける' do
    FileUtils.cp_r(File.join(fixtures, 'authors_config'), File.join(@root, 'mine'))
    expect(cornix('compile', '--config', File.join(@root, 'mine'), '--root', @root)).to eq(0)
    output = Dir[File.join(@root, 'tmp', 'profiles', 'mine-*', 'build', 'layout.vil')].first
    expect(out.string).to start_with("設定: mine（--config）\n").and include("✓ Compiled: #{output}")
    expect(image(output)).to eq(image(File.join(fixtures, 'authors_baseline.vil')))
  end

  it '--profile NAME は --root の profiles/NAME を使う' do
    FileUtils.mkdir_p(File.join(@root, 'profiles'))
    FileUtils.cp_r(File.join(fixtures, 'test_config'), File.join(@root, 'profiles', 'alice'))
    expect(cornix('--profile', 'alice', '--root', @root, 'validate')).to eq(0)
    expect(cornix('--profile', 'bob', '--root', @root, 'validate')).to eq(1)
    expect(out.string).to include("Error: #{File.join(@root, 'profiles', 'bob')} not found")
  end

  it '.cornix.yml の誤りは「エラー: …」で exit 1。help は止めない' do
    File.write(File.join(@root, '.cornix.yml'), "- x\n")
    expect(cornix('validate', '--root', @root)).to eq(1)
    expect(err.string).to include('.cornix.yml: profile: NAME か config: PATH を書いたマッピングにしてください')
    expect(cornix('help', '--root', @root)).to eq(0)
    expect(out.string).to include('--config DIR').and include('init')
  end

  it '<root>/config を使うときは「設定: …」を出さない' do
    FileUtils.cp_r(File.join(fixtures, 'test_config'), File.join(@root, 'config'))
    expect(cornix('validate', '--root', @root)).to eq(0)
    expect(out.string).to eq("✓ All validations passed\n")
  end

  it 'pull も --profile の設定ディレクトリと tmp/ を使う' do
    device = FakeRmkDevice.new
    opener = ->(&block) { block.call(Cornix::Device::Session.new(device, definition: FakeRmkDevice::DEFINITION)) }
    main = Cornix::Interface::Cli::Main.new(env_factory: ->(ws) { Cornix::Application::Environment.for(ws, device_opener: opener) },
                                            out: out, err: err, input: StringIO.new)
    expect(main.run(['pull', '--profile', 'p', '--root', @root])).to eq(0), err.string
    expect(out.string).to start_with("設定: profiles/p（--profile）\n")
    expect(File).to exist(File.join(@root, 'tmp', 'profiles', 'p', 'layout.vil'))
    expect(File).to exist(File.join(@root, 'profiles', 'p', 'metadata.yaml'))
  end

  describe 'init' do
    it '--from の .vil から profiles/NAME を作り、次からは .cornix.yml で見つかる' do
      source = File.join(fixtures, 'layout.vil')
      expect(cornix('init', @root, '--profile', 'main', '--from', source)).to eq(0)
      expect(out.string).to include("設定ディレクトリを作りました: #{File.join(@root, 'profiles', 'main')}")
                        .and include("#{source} から設定を書きました")
      expect(File.read(File.join(@root, '.cornix.yml'))).to eq("profile: main\n")

      out.truncate(0)
      Dir.chdir(@root) { expect(cornix('compile')).to eq(0) }
      expect(image(File.join(@root, 'tmp', 'profiles', 'main', 'build', 'layout.vil'))).to eq(image(source))
    end

    it 'DIR を渡すと --config の相対パスは DIR から。DIR がなければ作る' do
      dir = File.join(@root, 'new')
      expect(cornix('init', dir, '--config', 'cfg', '--no-pull')).to eq(0), err.string
      expect(File).to be_directory(File.join(dir, 'cfg'))
      expect(File.read(File.join(dir, '.cornix.yml'))).to eq("config: cfg\n")
    end

    it 'カレントの .cornix.yml が壊れていても、ほかの場所への init は止まらない' do
      File.write(File.join(@root, '.cornix.yml'), "- x\n")
      Dir.chdir(@root) { expect(cornix('init', File.join(@root, 'other'), '--no-pull')).to eq(0), err.string }
    end

    it '--from のファイルがなければ何も作らずに exit 1' do
      expect(cornix('init', @root, '--from', File.join(@root, 'none.vil'))).to eq(1)
      expect(err.string).to include('ファイルがありません')
      expect(Dir.children(@root)).to be_empty
    end

    it '--profile も --config もなければ profiles/default に作り、.cornix.yml で次から使う。既にあれば exit 1' do
      expect(cornix('init', @root, '--no-pull')).to eq(0), err.string
      dir = File.join(@root, 'profiles', 'default')
      expect(Dir.empty?(dir)).to be(true)
      expect(File).not_to exist(File.join(@root, 'config'))
      expect(File.read(File.join(@root, '.cornix.yml'))).to eq("profile: default\n")
      expect(out.string).to include('メモ:').and include('cornix decompile FILE')
      FileUtils.touch(File.join(dir, 'metadata.yaml'))
      expect(cornix('init', @root, '--no-pull')).to eq(1)
      expect(err.string).to include('設定ディレクトリがすでにあります')
    end

    it '.cornix.yml がなく中身のある config/ があれば、指定なしの init は何も作らずに exit 1' do
      FileUtils.mkdir_p(File.join(@root, 'config'))
      FileUtils.touch(File.join(@root, 'config', 'metadata.yaml'))
      expect(cornix('init', @root, '--no-pull')).to eq(1)
      expect(err.string).to include('設定ディレクトリ config/ がすでにあります').and include('--profile default')
      expect(Dir.children(@root)).to eq(['config'])
    end

    it '中身のある config/ があっても --profile を付ければ作り、次からは profiles/NAME が使われることを案内する' do
      FileUtils.mkdir_p(File.join(@root, 'config'))
      FileUtils.touch(File.join(@root, 'config', 'metadata.yaml'))
      expect(cornix('init', @root, '--profile', 'default', '--no-pull')).to eq(0), err.string
      expect(File.read(File.join(@root, '.cornix.yml'))).to eq("profile: default\n")
      expect(out.string).to include('次からは profiles/default/ が使われます')
        .and include("--config #{File.join(@root, 'config')}")
    end

    it '空の config/ や、すでにある .cornix.yml なら止めず、config/ の案内も出さない' do
      FileUtils.mkdir_p(File.join(@root, 'config'))
      expect(cornix('init', @root, '--no-pull')).to eq(0), err.string
      expect(out.string).not_to include('次からは')
      other = File.join(@root, 'other')
      FileUtils.mkdir_p(File.join(other, 'config'))
      FileUtils.touch(File.join(other, 'config', 'metadata.yaml'))
      File.write(File.join(other, '.cornix.yml'), "profile: main\n")
      out.truncate(0)
      expect(cornix('init', other, '--no-pull')).to eq(0), err.string
      expect(out.string).not_to include('次からは')
      expect(File.read(File.join(other, '.cornix.yml'))).to eq("profile: main\n")
    end

    it '.cornix.yml がなければ、今までどおり config/ を使う（後方互換）' do
      source = File.join(fixtures, 'layout.vil')
      expect(cornix('decompile', source, '--root', @root)).to eq(0), err.string
      expect(File).to exist(File.join(@root, 'config', 'metadata.yaml'))
      expect(cornix('compile', '--root', @root)).to eq(0), err.string
      expect(image(File.join(@root, 'tmp', 'build', 'layout.vil'))).to eq(image(source))
    end
  end
end
