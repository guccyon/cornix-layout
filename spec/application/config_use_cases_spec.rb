# frozen_string_literal: true

require 'spec_helper'
require 'yaml'
require_relative 'support/config_root'

RSpec.describe 'Application の設定ファイルのユースケース' do
  include_context 'config root'

  describe Cornix::Application::Validate do
    subject(:validate) { described_class.new(env) }

    it '問題がなければ errors も warnings もない' do
      install_config
      report = validate.call
      expect(report).to be_valid
      expect(report.warnings).to eq([])
      expect(report.profile).to be_a(Cornix::Domain::Profile)
    end

    it '構造の問題は「ファイル: キーの位置: 内容」ですべて errors にする' do
      install_config
      File.write(config_file('layers/0_layer_0.yaml'), read_config('layers/0_layer_0.yaml').sub(/tab: .*/, 'tab: Nope'))
      File.write(config_file('macros/00_macro.yaml'), "name: [\n")
      report = validate.call
      expect(report).not_to be_valid
      expect(report.errors).to include(a_string_starting_with('layers/0_layer_0.yaml: mapping.left_hand.row0.tab: '))
        .and include(a_string_starting_with('macros/00_macro.yaml: YAML の文法エラー'))
      expect(report.profile).to be_nil
    end

    it '意味検証の結果は位置を付けて errors / warnings に分ける' do
      install_config
      File.write(config_file('macros/01_macro.yaml'), read_config('macros/01_macro.yaml').sub('name: Macro 1', 'name: Macro 0'))
      File.delete(config_file('layers/9_layer_9.yaml'))
      report = validate.call
      expect(report.errors).to eq(['macros/01_macro.yaml: name: マクロの名前が重複しています: Macro 0'])
      expect(report.warnings).to eq(['layers/0_layer_0.yaml: mapping.encoders.right.push: レイヤー 9 が定義されていません'])
      expect(report.profile).to be_a(Cornix::Domain::Profile)
    end

    it 'config/ がなければ ConfigNotFound' do
      expect { validate.call }.to raise_error(Cornix::Application::ConfigNotFound) { |e| expect(e.dir).to eq(env.config_dir) }
    end
  end

  describe Cornix::Application::Compile do
    it 'test_config を compile すると spec/fixtures/layout.vil と同じ 16bit 値になる' do
      install_config
      result = described_class.new(env).call
      expect(result).to be_compiled
      expect(result.path).to eq(env.layout_path)
      expect(image(env.layout_path)).to eq(image(File.join(fixtures, 'layout.vil')))
    end

    it 'output を指定できる' do
      install_config
      path = File.join(@root, 'out.vil')
      expect(described_class.new(env).call(output: path).path).to eq(path)
      expect(File).to exist(path)
    end

    it '検証の errors があれば何も書かない' do
      install_config
      File.write(config_file('metadata.yaml'), "- 1\n")
      result = described_class.new(env).call
      expect(result).not_to be_compiled
      expect(result.report.errors).not_to be_empty
      expect(File).not_to exist(env.layout_path)
    end
  end

  describe Cornix::Application::Decompile do
    subject(:decompile) { described_class.new(env) }

    it '既定では tmp/layout.vil を config/ にし、テンプレートの position_map とロックファイルを置く' do
      input = install_file('layout.vil', 'tmp/layout.vil')
      result = decompile.call
      expect(result).to be_decompiled
      expect(result.input).to eq(input)
      expect(result.files).to include('metadata.yaml', 'position_map.yaml', 'layers/0_layer.yaml')
      expect(File.read(config_file('position_map.yaml'))).to eq(File.read(env.position_map_template))
      expect(result.position_map).to eq(env.position_map_template)
      lock = YAML.safe_load_file(result.lock)
      expect(lock.keys).to eq(%w[decompiled_at source_file checksum])
      expect(lock['source_file']).to eq(input)
      expect(lock['checksum']).to eq(Digest::SHA256.file(input).hexdigest)
    end

    it 'decompile → compile で元の .vil と同じ 16bit 値に戻る' do
      %w[layout.vil authors_baseline.vil].each_with_index do |name, i|
        root = File.join(@root, "case#{i}")
        e = Cornix::Application::Environment.new(root: root)
        source = File.join(fixtures, name)
        expect(described_class.new(e).call(input: source)).to be_decompiled
        expect(Cornix::Application::Compile.new(e).call).to be_compiled
        expect(e.vil_file.read(e.layout_path)).to eq(e.vil_file.read(source)), name
      end
    end

    it 'config/ に position_map.yaml があればそれを使い、そのまま残す' do
      FileUtils.mkdir_p(env.config_dir)
      custom = File.read(File.join(fixtures, 'authors_config/position_map.yaml'))
      File.write(config_file('position_map.yaml'), "# 自分の配置\n#{custom}")
      result = decompile.call(input: File.join(fixtures, 'authors_baseline.vil'))
      expect(result.position_map).to eq(config_file('position_map.yaml'))
      expect(read_config('position_map.yaml')).to eq("# 自分の配置\n#{custom}")
      expect(Cornix::Application::Compile.new(env).call).to be_compiled
    end

    it 'config/ に position_map.yml があれば position_map.yaml は残さない' do
      FileUtils.mkdir_p(env.config_dir)
      FileUtils.cp(env.position_map_template, config_file('position_map.yml'))
      decompile.call(input: File.join(fixtures, 'layout.vil'))
      expect(File).not_to exist(config_file('position_map.yaml'))
      expect(Cornix::Application::Validate.new(env).call).to be_valid
    end

    it '入力がなければ :input_missing' do
      expect(decompile.call(input: File.join(@root, 'none.vil')).status).to eq(:input_missing)
      expect(File).not_to exist(env.config_dir)
    end

    it 'config/ の layers/ か macros/ に何かあれば何もしない' do
      %w[layers macros].each do |sub|
        root = File.join(@root, sub)
        e = Cornix::Application::Environment.new(root: root)
        FileUtils.mkdir_p(File.join(e.config_dir, sub))
        File.write(File.join(e.config_dir, sub, 'x.yaml'), "a: 1\n")
        result = described_class.new(e).call(input: File.join(fixtures, 'layout.vil'))
        expect(result.status).to eq(:config_exists)
        expect(Dir.children(e.config_dir)).to eq([sub])
      end
    end
  end

  describe Cornix::Application::Cleanup do
    subject(:cleanup) { described_class.new(env) }

    it '消すものがなければ :nothing' do
      expect(cleanup.call.status).to eq(:nothing)
    end

    it 'ロックがなければ config/ と compile の出力（tmp/build/layout.vil）を消す' do
      install_config
      install_file('layout.vil', 'tmp/build/layout.vil')
      result = cleanup.call
      expect([result.status, result.deleted]).to eq([:cleaned, %w[config/ tmp/build/layout.vil]])
      expect(File).not_to exist(env.config_dir)
      expect(File).not_to exist(env.layout_path)
    end

    it 'compile の出力が root の外なら、消したものは絶対パスで示す' do
      outside = Dir.mktmpdir
      path = File.join(outside, 'out.vil')
      File.write(path, '{}')
      e = Cornix::Application::Environment.new(root: "#{@root}/", layout_path: path)
      expect(described_class.new(e).call.deleted).to eq([path])
      expect(File).not_to exist(path)
    ensure
      FileUtils.rm_rf(outside)
    end

    it 'ロックがあれば force でなければ消さず、force なら confirm が真のときだけ消す' do
      Cornix::Application::Decompile.new(env).call(input: File.join(fixtures, 'layout.vil'))
      result = cleanup.call
      expect(result.status).to eq(:protected)
      expect(result.lock.keys).to eq(%w[decompiled_at source_file checksum])
      asked = []
      expect(cleanup.call(force: true, confirm: ->(lock) { asked << lock && false }).status).to eq(:cancelled)
      expect(asked.size).to eq(1)
      expect(File).to exist(env.config_dir)
      expect(cleanup.call(force: true, confirm: ->(_) { true }).deleted).to eq(['config/'])
    end

    it 'カレントディレクトリではなく Environment の root の下を消す' do
      install_config
      Dir.chdir(Dir.tmpdir) { cleanup.call }
      expect(File).not_to exist(env.config_dir)
    end
  end
end
