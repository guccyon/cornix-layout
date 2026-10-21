# frozen_string_literal: true

require 'spec_helper'
require 'stringio'
require 'json'
require_relative '../../application/support/config_root'
require_relative '../../application/device_environment_context'

# 共通のオプション --json: 結果を JSON.parse できる 1 つの値として標準出力に出す。終了コードは --json なしと同じ
RSpec.shared_context 'cornix --json' do
  let(:out) { StringIO.new }
  let(:err) { StringIO.new }
  let(:input) { StringIO.new }

  def cornix(*argv, **opts)
    out.truncate(0) && out.rewind
    Cornix::Interface::Cli::Main.new(env_factory: ->(_ws) { env }, out: out, err: err, input: input, **opts).run(argv)
  end

  # 標準出力の全体が 1 つの JSON の値であること（ほかの文章を混ぜない）
  def json = JSON.parse(out.string)
end

RSpec.describe 'cornix --json（設定ファイルのコマンド）' do
  include_context 'config root'
  include_context 'cornix --json'

  describe 'validate' do
    it '{ ok, diagnostics: [{ severity, path, message }] } を出し、エラーがあれば exit 1' do
      install_config('authors_config')
      expect(cornix('validate', '--json')).to eq(0)
      expect(json).to include('ok' => true, 'diagnostics' => [])
      expect(json).to have_key('config')

      File.write(config_file('metadata.yaml'), "- 1\n")
      expect(cornix('--json', 'validate')).to eq(1)
      expect(json['ok']).to be(false)
      expect(json['diagnostics'].first).to include('severity' => 'error', 'path' => start_with('metadata.yaml'))
      expect(json['diagnostics'].first['message']).to be_a(String)
      expect(err.string).to be_empty
    end

    it '意味検証の警告は severity: warning で、ok は真のまま' do
      install_config
      File.delete(config_file('layers/9_layer_9.yaml'))
      expect(cornix('validate', '--json')).to eq(0)
      expect(json['ok']).to be(true)
      expect(json['diagnostics']).to eq([{ 'severity' => 'warning', 'path' => 'layers/0_layer_0.yaml: mapping.encoders.right.push',
                                           'message' => 'レイヤー 9 が定義されていません' }])
    end

    it 'config/ がなければ { error } で exit 1' do
      expect(cornix('validate', '--json')).to eq(1)
      expect(json).to eq('error' => "#{env.config_dir} not found")
    end
  end

  describe 'compile' do
    it '{ ok, path, diagnostics } を出す。検証に失敗したら書かずに ok: false で exit 1' do
      install_config('authors_config')
      expect(cornix('compile', '--json')).to eq(0)
      expect(json).to include('ok' => true, 'path' => env.layout_path, 'diagnostics' => [])

      File.write(config_file('metadata.yaml'), "- 1\n")
      File.delete(env.layout_path)
      expect(cornix('compile', '--json')).to eq(1)
      expect(json).to include('ok' => false, 'path' => nil)
      expect(File).not_to exist(env.layout_path)
    end

    it 'config/ がなければ decompile を案内する { error }' do
      expect(cornix('compile', '--json')).to eq(1)
      expect(json).to eq('error' => "#{env.config_dir} not found. Run 'cornix decompile' first to create config files")
    end
  end

  describe 'decompile' do
    it '{ ok, status, input, output_dir, files, lock } を出す。config/ に設定があれば status: config_exists で exit 1' do
      vil = File.join(fixtures, 'layout.vil')
      expect(cornix('decompile', vil, '--json')).to eq(0)
      expect(json).to include('ok' => true, 'status' => 'decompiled', 'input' => vil, 'output_dir' => env.config_dir,
                              'lock' => File.join(env.config_dir, '.decompile.lock'))
      expect(json['files']).to include('metadata.yaml')

      expect(cornix('decompile', vil, '--json')).to eq(1)
      expect(json).to include('ok' => false, 'status' => 'config_exists', 'files' => [])
    end

    it '入力がなければ status: input_missing で exit 1' do
      expect(cornix('decompile', File.join(@root, 'none.vil'), '--json')).to eq(1)
      expect(json).to include('status' => 'input_missing')
    end
  end

  describe 'cleanup' do
    it '{ status, deleted, lock } を出す。ロックがあれば status: protected で exit 1' do
      cornix('decompile', File.join(fixtures, 'layout.vil'))
      expect(cornix('cleanup', '--json')).to eq(1)
      expect(json).to include('status' => 'protected', 'deleted' => [])
      expect(json['lock']).to include('source_file')
    end

    it '-f は y/N で確認するので --json と一緒には使えない' do
      expect(cornix('cleanup', '-f', '--json')).to eq(1)
      expect(json['error']).to include('--json')
    end
  end

  it 'rename / mcp / serve は対象外（{ error } で exit 1）' do
    %w[rename mcp serve].each do |name|
      expect(cornix(name, '--json')).to eq(1)
      expect(json).to eq('error' => "--json は #{name} では使えません")
    end
  end

  it '使い方の誤りも { error } で、標準エラー出力には出さない' do
    expect(cornix('nope', '--json')).to eq(1)
    expect(json).to eq('error' => '知らないコマンドです: nope')
    expect(cornix('compile', 'x', '--json')).to eq(1)
    expect(json['error']).to include('余分な引数: x')
    expect(err.string).to be_empty
  end

  it 'version --json は { version }' do
    expect(cornix('--version', '--json')).to eq(0)
    expect(json).to eq('version' => Cornix::VERSION)
  end

  it '既定以外の設定ディレクトリでも「設定: …」の行を混ぜず、config に設定ディレクトリを入れる' do
    install_config('authors_config')
    workspace = Cornix::Application::Workspace.new(root: @root, config_dir: env.config_dir, profile_name: 'alice',
                                                   source: :option, settings_file: nil)
    other = Cornix::Application::Environment.new(root: @root, config_dir: env.config_dir, workspace: workspace)
    expect(cornix('validate', '--json', env_factory: ->(_ws) { other })).to eq(0)
    expect(json['config']).to eq('config_dir' => env.config_dir, 'profile' => 'alice', 'source' => 'option', 'root' => @root)
  end
end

RSpec.describe 'cornix --json（キーボードのコマンド）' do
  include_context 'device environment'
  include_context 'cornix --json'

  let(:edit) { ->(v) { v['layout'][1][0][1] = 'KC_BSPC' } }
  let(:report) { Cornix::Application::ValidationReport.new }
  let(:compile) do
    fake = lambda do |output: nil|
      Cornix::Application::CompileResult.new(report: report, path: write_vil(output || env.layout_path, &edit))
    end
    ->(_env) { fake }
  end

  def top(*argv) = cornix(*argv, use_cases: { compile: compile })

  describe 'status' do
    it '{ config, compile, diff } を出し、差分があれば exit 2（書き込みなし）' do
      expect(top('status', '--json')).to eq(2)
      expect(json.keys).to eq(%w[config compile diff])
      expect(json['compile']).to include('ok' => true, 'path' => env.layout_path)
      diff = json['diff']
      expect(diff).to include('source' => env.layout_path, 'empty' => false, 'warnings' => [])
      expect(diff['token']).to match(/\A\h+\z/)
      expect(diff['changes']).to eq([{ 'description' => 'レイヤー1 (0,1): KC_NO → KC_BSPACE', 'kind' => 'set_keycode',
                                       'layer' => 1, 'row' => 0, 'col' => 1, 'from' => 0, 'to' => 0x2A }])
      expect(device.writes).to be_empty
    end

    it '検証に失敗したらキーボードを開かず、diff: nil で exit 1' do
      failed = Cornix::Application::ValidationReport.new(diagnostics: [Cornix::Domain::Diagnostic.error('a.yaml', '壊れている')])
      compile_failure = ->(_env) { ->(**) { Cornix::Application::CompileResult.new(report: failed) } }
      expect(cornix('status', '--json', use_cases: { compile: compile_failure })).to eq(1)
      expect(json['compile']).to eq('ok' => false, 'path' => nil,
                                    'diagnostics' => [{ 'severity' => 'error', 'path' => 'a.yaml', 'message' => '壊れている' }])
      expect(json['diff']).to be_nil
      expect(opens).to be_empty
    end
  end

  describe 'apply / restore' do
    it '--yes がなければ compile もキーボードを開くこともせずに { error } で exit 1' do
      expect(top('apply', '--json')).to eq(1)
      expect(json['error']).to include('--yes')
      expect(File).not_to exist(env.layout_path)
      expect(top('restore', '--json')).to eq(1)
      expect(cornix('device', 'apply', '--json')).to eq(1)
      expect(opens).to be_empty
      expect(input.pos).to eq(0)
    end

    it 'apply --yes --json は { config, compile, apply } を出し、restore --yes --json で戻す' do
      expect(top('apply', '--yes', '--json')).to eq(0)
      backup = env.snapshot_store.latest(kind: 'pre-apply').path
      expect(json['apply']).to include('written' => true, 'cancelled' => false, 'applied' => 1, 'backup' => backup,
                                       'remaining' => [], 'success' => true)
      expect(json['apply']['changes'].map { |c| c['description'] }).to eq(['レイヤー1 (0,1): KC_NO → KC_BSPACE'])
      expect(device.keymap[1][0][1]).to eq(0x2A)

      expect(top('restore', '--yes', '--json')).to eq(0)
      expect(json.keys).to eq(%w[config source token changes warnings written cancelled applied backup remaining success])
      expect(json).to include('source' => backup, 'applied' => 1)
      expect(device.keymap[1][0][1]).to eq(0)
    end
  end

  describe 'device' do
    it 'diff は PlanResult、read は { path, vil }、backup は { path } を出す' do
      vil = write_vil(File.join(@root, 'a.vil'), &edit)
      expect(cornix('device', 'diff', vil, '--json')).to eq(0)
      expect(json).to include('source' => vil, 'empty' => false)

      expect(cornix('device', 'read', '--json')).to eq(0)
      expect(json['path']).to be_nil
      expect(json['vil']['layout'][0][0][0]).to eq('KC_A')

      expect(cornix('device', 'backup', '--json')).to eq(0)
      expect(json).to eq('path' => env.snapshot_store.latest(kind: 'backup').path)
    end

    it 'info は --json でも同じ JSON（MCP の keyboard_info と同じ中身）' do
      expect(cornix('device', 'info', '--json')).to eq(0)
      expect(json).to include('name' => 'Fake', 'layers' => 2)
    end

    it 'デバイスのエラーも { error } で exit 1' do
      failing = ->(**) { raise Cornix::DeviceError, 'Cornix が見つかりません' }
      broken = Cornix::Application::Environment.new(root: @root, device_opener: failing)
      expect(cornix('device', 'info', '--json', env_factory: ->(_ws) { broken })).to eq(1)
      expect(json).to eq('error' => 'Cornix が見つかりません')
    end

    it '知らない操作は使い方を出さずに { error }' do
      expect(cornix('device', 'bogus', '--json')).to eq(1)
      expect(json['error']).to include('bogus')
    end
  end

  it 'snapshots は { config, dir, snapshots: [{ name, kind, time, path }] }（なければ空の一覧）' do
    expect(cornix('snapshots', '--json')).to eq(0)
    expect(json).to include('snapshots' => [])
    cornix('device', 'backup')
    expect(cornix('snapshots', '--json', '--kind', 'backup')).to eq(0)
    expect(json['snapshots'].map { |s| s['kind'] }).to eq(['backup'])
    expect(json['snapshots'].first.keys).to eq(%w[name kind time path])
  end
end
