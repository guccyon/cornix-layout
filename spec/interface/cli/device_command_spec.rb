# frozen_string_literal: true

require 'spec_helper'
require 'stringio'
require_relative '../../application/device_environment_context'

RSpec.describe Cornix::Interface::Cli::Commands::Device do
  include_context 'device environment'

  let(:out) { StringIO.new }
  let(:err) { StringIO.new }
  let(:input) { StringIO.new }

  def cornix(*argv)
    Cornix::Interface::Cli::Main.new(env_factory: ->(_ws) { env }, out: out, err: err, input: input).run(['device', *argv])
  end

  it '引数がなければ使い方を表示して exit 0、知らない action は exit 1' do
    expect(cornix).to eq(0)
    expect(out.string).to start_with("Usage:\n  cornix device info")
    expect(cornix('bogus')).to eq(1)
  end

  it 'info は JSON で表示する' do
    expect(cornix('info')).to eq(0)
    expect(JSON.parse(out.string)).to include('name' => 'Fake', 'layers' => 2)
  end

  it 'read は .vil を表示し、-o で保存する' do
    expect(cornix('read')).to eq(0)
    expect(JSON.parse(out.string)['layout'][0][0][0]).to eq('KC_A')
    path = File.join(@root, 'read.vil')
    out.truncate(0) && out.rewind
    expect(cornix('read', '-o', path)).to eq(0)
    expect(out.string).to eq("✓ 保存しました: #{path}\n")
    expect(JSON.parse(File.read(path))['layout'][0][0][0]).to eq('KC_A')
  end

  it 'backup はバックアップのパスを表示する' do
    expect(cornix('backup')).to eq(0)
    expect(out.string).to eq("✓ バックアップを保存しました: #{env.backup_store.latest}\n")
  end

  describe 'diff / apply' do
    let(:vil) { write_vil(File.join(@root, 'target.vil')) { |v| v['layout'][1][0][1] = 'KC_BSPC' } }

    it 'diff は差分を表示し、書き込まない' do
      expect(cornix('diff', vil)).to eq(0)
      expect(out.string).to eq("差分 1 件:\n  - レイヤー1 (0,1): KC_NO → KC_BSPACE\n")
      expect(device.writes).to be_empty
    end

    it 'diff は差分がなければそう表示し、警告も出す' do
      path = write_vil(File.join(@root, 'same.vil')) { |v| v['layout'][0][1][2] = 'KC_X' }
      expect(cornix('diff', path)).to eq(0)
      expect(out.string).to eq("✓ キーボードとの差分はありません\n" \
                               "  ⚠️  レイヤー0 (1,2) はキーボード上に存在しない位置のため無視します\n")
    end

    it 'diff は FILE を省略すると compile の出力（tmp/build/layout.vil）を使う' do
      write_vil { |v| v['layout'][1][0][1] = 'KC_BSPC' }
      expect(cornix('diff')).to eq(0)
      expect(out.string).to include('差分 1 件:')
    end

    it 'diff / apply は FILE を省略して compile の出力がなければ、compile を案内して exit 1' do
      expect(cornix('diff')).to eq(1)
      expect(err.string).to include(env.layout_path, '先に cornix compile')
      expect(cornix('apply', '--yes')).to eq(1)
      expect(opens).to be_empty
    end

    it 'apply --yes は確認せずに書き込み、読み戻して検証する' do
      expect(cornix('apply', vil, '--yes')).to eq(0)
      expect(device.keymap[1][0][1]).to eq(0x2A)
      expect(opens.size).to eq(1) # 旧実装と同じく接続は 1 回
      backup = env.backup_store.latest
      expect(out.string).to eq(<<~TEXT)
        反映元: #{vil}
        差分 1 件:
          - レイヤー1 (0,1): KC_NO → KC_BSPACE
        ✓ 1 件を書き込みました（反映前のバックアップ: #{backup}）
        ✓ 読み戻して検証し、すべて一致しました
      TEXT
    end

    it 'apply は y/N を尋ね、y なら書き込む' do
      input.string = "y\n"
      expect(cornix('apply', vil)).to eq(0)
      expect(out.string).to include("\nこの差分をキーボードに書き込みますか？ [y/N] ✓ 1 件を書き込みました")
      expect(device.keymap[1][0][1]).to eq(0x2A)
      expect(opens.size).to eq(1)
    end

    it 'apply は y 以外なら中止する' do
      input.string = "\n"
      expect(cornix('apply', vil)).to eq(0)
      expect(out.string).to end_with("中止しました\n")
      expect(device.writes).to be_empty
      expect(env.backup_store.list).to be_empty
      expect(opens.size).to eq(1)
    end

    it 'apply は差分がなければ尋ねずに終わる' do
      path = write_vil(File.join(@root, 'same.vil')) { nil }
      expect(cornix('apply', path)).to eq(0)
      expect(out.string).to eq("反映元: #{path}\n✓ キーボードとの差分はありません\n")
      expect(input.string).to be_empty # 尋ねない
    end

    it '読み戻して一致しなければ exit 1' do
      allow(device).to receive(:transfer).and_wrap_original do |original, bytes|
        bytes[0] == 0x05 ? bytes + ([0] * (32 - bytes.size)) : original.call(bytes)
      end
      expect(cornix('apply', vil, '--yes')).to eq(1)
      expect(out.string).to include("⚠️  読み戻し後も 1 件が一致しません:\n  - レイヤー1 (0,1): KC_NO → KC_BSPACE\n")
    end

    it 'ファイルがなければ「エラー: …」で exit 1' do
      expect(cornix('apply', File.join(@root, 'none.vil'), '--yes')).to eq(1)
      expect(err.string).to start_with('エラー: ').and include('none.vil')
      expect(opens).to be_empty
    end

    it '余分な引数は exit 1' do
      expect(cornix('diff', 'a.vil', 'b.vil')).to eq(1)
      expect(err.string).to include('余分な引数: b.vil')
    end
  end

  describe 'restore' do
    it '最新のバックアップに戻す' do
      vil = write_vil(File.join(@root, 'target.vil')) { |v| v['layout'][1][1][1] = 'KC_C' }
      cornix('apply', vil, '--yes')
      latest = env.backup_store.latest
      out.truncate(0) && out.rewind
      opens.clear
      expect(cornix('restore', '--yes')).to eq(0)
      expect(opens.size).to eq(1)
      expect(device.keymap[1][1][1]).to eq(0)
      expect(out.string).to start_with("復元元: #{latest}\n差分 1 件:\n  - レイヤー1 (1,1): KC_C → KC_NO\n")
    end

    it 'バックアップがなければエラー' do
      expect(cornix('restore', '--yes')).to eq(1)
      expect(err.string).to include('バックアップがありません')
    end
  end
end
