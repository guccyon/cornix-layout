# frozen_string_literal: true

require 'spec_helper'
require 'stringio'
require_relative '../../application/device_environment_context'

# 直下の pull / status / apply / restore（compile と device のショートカット）。
# FakeRmkDevice は Cornix と形が違うので、compile は「FakeRmkDevice の形の .vil を書くもの」に差し替える
RSpec.describe 'cornix pull / status / apply / restore' do
  include_context 'device environment'

  let(:out) { StringIO.new }
  let(:err) { StringIO.new }
  let(:input) { StringIO.new }
  let(:compiled) { [] }
  let(:report) { Cornix::Application::ValidationReport.new }
  let(:edit) { ->(v) { v['layout'][1][0][1] = 'KC_BSPC' } }
  let(:compile) do
    fake = lambda do |output: nil|
      path = write_vil(output || env.layout_path, &edit)
      compiled << path
      Cornix::Application::CompileResult.new(report: report, path: path)
    end
    ->(_env) { fake }
  end

  def cornix(*argv)
    out.truncate(0) && out.rewind
    Cornix::Interface::Cli::Main.new(env_factory: ->(_ws) { env }, use_cases: { compile: compile },
                                     out: out, err: err, input: input).run(argv)
  end

  it 'compile は既定で tmp/build/layout.vil に書き、-o で出力先を変えられる' do
    expect(env.layout_path).to eq(File.join(@root, 'tmp', 'build', 'layout.vil'))
    expect(cornix('compile')).to eq(0)
    expect(out.string).to end_with("✓ Compilation completed: #{env.layout_path}\n")
    other = File.join(@root, 'out', 'other.vil')
    expect(cornix('compile', '-o', other)).to eq(0)
    expect(compiled).to eq([env.layout_path, other])
  end

  describe 'status' do
    it 'compile してから、その出力とキーボードの差分を表示する（書き込みなし。差分があれば exit 2）' do
      expect(cornix('status')).to eq(2)
      expect(compiled).to eq([env.layout_path])
      expect(out.string).to start_with('🔍 Validating configuration...')
      expect(out.string).to end_with("✓ Compiled: #{env.layout_path}\n\n差分 1 件:\n  - レイヤー1 (0,1): KC_NO → KC_BSPACE\n")
      expect(device.writes).to be_empty
    end

    context '差分がなければ' do
      let(:edit) { ->(_v) {} }

      it 'exit 0' do
        expect(cornix('status')).to eq(0)
        expect(out.string).to end_with("✓ キーボードとの差分はありません\n")
      end
    end

    it '検証に失敗したらキーボードを開かずに exit 1' do
      failed = Cornix::Application::CompileResult.new(report: Cornix::Application::ValidationReport.new(diagnostics: [Cornix::Domain::Diagnostic.error('', '壊れている')]))
      compile_failure = ->(_env) { ->(**) { failed } }
      result = Cornix::Interface::Cli::Main.new(env_factory: ->(_ws) { env }, use_cases: { compile: compile_failure },
                                                out: out, err: err, input: input).run(['status'])
      expect(result).to eq(1)
      expect(out.string).to include('❌ Validation failed.')
      expect(opens).to be_empty
    end

    it 'config/ がなければ decompile を案内して exit 1' do
      result = Cornix::Interface::Cli::Main.new(env_factory: ->(_ws) { env }, out: out, err: err, input: input).run(['status'])
      expect(result).to eq(1)
      expect(out.string).to include("Run 'cornix decompile' first")
      expect(opens).to be_empty
    end
  end

  describe 'apply' do
    it '--yes なら compile の出力を確認せずに書き込み、読み戻して検証する' do
      expect(cornix('apply', '--yes')).to eq(0)
      expect(device.keymap[1][0][1]).to eq(0x2A)
      expect(opens.size).to eq(1)
      expect(out.string).to end_with(<<~TEXT)
        ✓ Compiled: #{env.layout_path}

        反映元: #{env.layout_path}
        差分 1 件:
          - レイヤー1 (0,1): KC_NO → KC_BSPACE
        ✓ 1 件を書き込みました（反映前のバックアップ: #{env.snapshot_store.latest(kind: 'pre-apply').path}）
        ✓ 読み戻して検証し、すべて一致しました
      TEXT
    end

    it 'y/N で y 以外なら書き込まない' do
      input.string = "n\n"
      expect(cornix('apply')).to eq(0)
      expect(out.string).to end_with("この差分をキーボードに書き込みますか？ [y/N] 中止しました\n")
      expect(device.writes).to be_empty
    end

    it 'FILE は受け付けない（ファイルを指定するなら device apply）' do
      expect(cornix('apply', 'a.vil')).to eq(1)
      expect(err.string).to include('余分な引数: a.vil')
    end
  end

  it 'restore は直前の apply の前の状態に戻す' do
    cornix('apply', '--yes')
    latest = env.snapshot_store.latest(kind: 'pre-apply').path
    opens.clear
    expect(cornix('restore', '--yes')).to eq(0)
    expect(device.keymap[1][0][1]).to eq(0)
    expect(opens.size).to eq(1)
    expect(out.string).to start_with("復元元: #{latest}\n差分 1 件:\n  - レイヤー1 (0,1): KC_BSPACE → KC_NO\n")
  end

  describe 'snapshots' do
    def line(snapshot) = "#{snapshot.time.strftime('%Y-%m-%d %H:%M:%S')}  #{snapshot.kind.ljust(9)}  #{snapshot.path}"

    it 'status / apply で読んだ状態と書き込む前の状態が増え、新しい順に表示する（--kind で絞り込む）' do
      expect(cornix('snapshots')).to eq(0)
      expect(out.string).to eq("スナップショットはありません\n")

      cornix('status')
      cornix('apply', '--yes')
      store = env.snapshot_store
      expect(store.list(kind: 'read').size).to eq(2)
      expect(store.list(kind: 'pre-apply').size).to eq(1)

      expect(cornix('snapshots')).to eq(0)
      expect(out.string).to eq(store.list.map { |s| "#{line(s)}\n" }.join)
      expect(cornix('snapshots', '--kind', 'pre-apply')).to eq(0)
      pre_apply = store.latest(kind: 'pre-apply')
      expect(out.string).to eq("#{pre_apply.time.strftime('%Y-%m-%d %H:%M:%S')}  pre-apply  #{pre_apply.path}\n")
      expect(cornix('snapshots', '--kind', 'build')).to eq(0)
      expect(out.string).to eq("種類 build のスナップショットはありません\n")
    end

    it '知らない種類は exit 1' do
      expect(cornix('snapshots', '--kind', 'nope')).to eq(1)
      expect(err.string).to include('知らないスナップショットの種類です: nope')
    end

    it 'カレントの下なら相対パスで出し、そのパスを restore に渡せる' do
      cornix('apply', '--yes')
      Dir.chdir(@root) do
        expect(cornix('snapshots', '--kind', 'pre-apply')).to eq(0)
        path = out.string.split.last
        expect(path).to match(%r{\Atmp/snapshots/\d{8}-\d{6}-pre-apply(-\d+)?/layout\.vil\z})
        expect(cornix('restore', path, '--yes')).to eq(0)
      end
      expect(device.keymap[1][0][1]).to eq(0)
    end
  end

  describe 'pull' do
    it 'キーボードの状態を tmp/layout.vil に保存して config/ にする' do
      expect(cornix('pull')).to eq(0)
      expect(out.string).to start_with("✓ キーボードの状態を保存しました: #{env.decompile_input}\n" \
                                       "Decompiling: #{env.decompile_input}\n")
      expect(JSON.parse(File.read(env.decompile_input))).to eq(device_vil)
      expect(Dir.glob(File.join(env.config_dir, 'layers', '*'))).not_to be_empty
      expect(device.writes).to be_empty
    end

    it 'config/ にすでに設定があれば、キーボードを開かず tmp/layout.vil も書き換えずに止まる' do
      cornix('pull')
      File.write(env.decompile_input, 'mine')
      opens.clear
      expect(cornix('pull')).to eq(1)
      expect(out.string).to include('config/ directory already contains configuration files',
                                    'pull has been blocked', "cornix pull\n")
      expect(out.string).not_to include('decompile')
      expect(opens).to be_empty
      expect(File.read(env.decompile_input)).to eq('mine')
    end
  end
end
