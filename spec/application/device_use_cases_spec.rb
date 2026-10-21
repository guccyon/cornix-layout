# frozen_string_literal: true

require 'spec_helper'
require_relative 'device_environment_context'

RSpec.describe 'デバイスのユースケース' do
  include_context 'device environment'

  def snapshots(kind) = env.snapshot_store.list(kind: kind).map(&:path)
  def backups = snapshots('pre-apply')

  describe Cornix::Application::DeviceInfo do
    it 'Session#info を返す' do
      result = described_class.new(env).call
      expect(result.to_h).to include(name: 'Fake', layers: 2, encoders: 1, macros: { count: 4, buffer_size: 64 })
    end
  end

  describe Cornix::Application::DeviceRead do
    it 'layout.vil 形式で読む（-1 はキーのない位置）' do
      result = described_class.new(env).call
      vil = JSON.parse(result.vil)
      expect(vil.keys.first(4)).to eq(%w[version uid vial_protocol via_protocol])
      expect(vil['layout'][0]).to eq([%w[KC_A KC_NO KC_NO], ['KC_NO', 'KC_NO', -1]])
      expect(vil['encoder_layout'][0]).to eq([%w[KC_VOLD KC_VOLU]])
      expect(result.path).to be_nil
      expect(result.to_h.keys).to eq(%w[path vil])
    end

    it 'output を渡すと保存する' do
      path = File.join(@root, 'out.vil')
      result = described_class.new(env).call(output: path)
      expect(result.path).to eq(path)
      expect(File.read(path)).to eq(result.vil)
      expect(env.vil_file.read(path)).to eq(result.image)
    end

    it '読んだ状態をスナップショット（read）に残す' do
      result = described_class.new(env).call
      expect(snapshots('read').size).to eq(1)
      expect(env.vil_file.read(snapshots('read').first)).to eq(result.image)
    end
  end

  describe Cornix::Application::DeviceBackup do
    it 'スナップショット（backup）として保存する（read は残さない）' do
      result = described_class.new(env).call
      expect(result.path).to start_with(env.snapshot_dir)
      expect(snapshots('backup')).to eq([result.path])
      expect(snapshots('read')).to be_empty
      expect(result.to_h).to eq('path' => result.path)
    end
  end

  describe Cornix::Application::ListSnapshots do
    it '新しい順に返し、kind で絞り込める' do
      expect(described_class.new(env).call).to be_empty
      image = env.vil_file.read(write_vil { nil })
      old = env.snapshot_store.save(image, kind: 'pre-apply', time: Time.new(2026, 1, 1))
      new = env.snapshot_store.save(image, kind: 'read', time: Time.new(2026, 2, 1))
      list = described_class.new(env).call
      expect(list.paths).to eq([new, old])
      expect(list.to_h['dir']).to eq(env.snapshot_dir)
      expect(list.to_h['snapshots'].map { |s| s['kind'] }).to eq(%w[read pre-apply])
      expect(described_class.new(env).call(kind: 'pre-apply').paths).to eq([old])
    end
  end

  describe Cornix::Application::DeviceDiff do
    it '既定は layout.vil との差分。書き込まない' do
      write_vil { |v| v['layout'][1][0][1] = 'KC_BSPC' }
      result = described_class.new(env).call
      expect(result.source).to eq(env.layout_path)
      expect(result.changes).to eq(['レイヤー1 (0,1): KC_NO → KC_BSPACE'])
      expect(result.token).to match(/\A\h{16}\z/)
      expect(result).not_to be_empty
      expect(result.to_h).to include('source' => env.layout_path, 'token' => result.token, 'empty' => false)
      expect(device.writes).to be_empty
    end

    it '警告を返す' do
      path = write_vil(File.join(@root, 'a.vil')) { |v| v['layout'][0][1][2] = 'KC_X' }
      result = described_class.new(env).call(vil_path: path)
      expect(result).to be_empty
      expect(result.warnings).to eq(['レイヤー0 (1,2) はキーボード上に存在しない位置のため無視します'])
    end

    it 'ファイルがなければ ConfigError（デバイスは開かない）' do
      expect { described_class.new(env).call }.to raise_error(Cornix::ConfigError, /layout\.vil/)
      expect(opens).to be_empty
    end

    it '拒否するキーコードがあれば PlanError' do
      write_vil { |v| v['layout'][0][0][1] = 'QK_BOOT' }
      expect { described_class.new(env).call }.to raise_error(Cornix::PlanError, /安全のため書き込めません/)
    end
  end

  describe Cornix::Application::DeviceApply do
    before { write_vil { |v| v['layout'][1][0][1] = 'KC_BSPC' } }

    it 'バックアップを取ってから書き込み、読み戻して検証する' do
      token = Cornix::Application::DeviceDiff.new(env).call.token
      outcome = described_class.new(env).call(expected_token: token)
      expect(device.keymap[1][0][1]).to eq(0x2A)
      expect(outcome).to be_written
      expect(outcome).to be_success
      expect(outcome.applied).to eq(1)
      expect(outcome.changes).to eq(['レイヤー1 (0,1): KC_NO → KC_BSPACE'])
      expect(outcome.backup).to eq(backups.first)
      expect(env.vil_file.read(outcome.backup).layers[1][0][1]).to eq(0) # 書き込む前の状態
      expect(snapshots('read').size).to eq(2) # dry run と apply で読んだ状態
      expect(outcome.to_h).to include('written' => true, 'applied' => 1, 'remaining' => [], 'success' => true)
    end

    it 'confirm は同じ接続の中で PlanResult を受け取り、真なら書き込む' do
      seen = []
      outcome = described_class.new(env).call(confirm: ->(plan) { seen << plan; true })
      expect(seen.map(&:class)).to eq([Cornix::Application::PlanResult])
      expect(seen.first.changes).to eq(['レイヤー1 (0,1): KC_NO → KC_BSPACE'])
      expect(outcome).to be_written
      expect(outcome).not_to be_cancelled
      expect(opens.size).to eq(1)
    end

    it 'confirm が偽なら書き込まず、バックアップも取らずに cancelled を返す' do
      outcome = described_class.new(env).call(confirm: ->(_plan) { false })
      expect(outcome).to be_cancelled
      expect(outcome).not_to be_written
      expect(outcome.changes).to eq(['レイヤー1 (0,1): KC_NO → KC_BSPACE'])
      expect(outcome.to_h).to include('cancelled' => true, 'written' => false)
      expect(device.writes).to be_empty
      expect(backups).to be_empty
      expect(snapshots('read').size).to eq(1) # 読んだ状態は残る
      expect(opens.size).to eq(1)
    end

    it 'token が違えば何も書かない' do
      expect { described_class.new(env).call(expected_token: 'stale') }.to raise_error(Cornix::PlanError, /変わって/)
      expect(device.writes).to be_empty
      expect(backups).to be_empty
    end

    it '差分がなければ何も書かず、バックアップも取らない' do
      described_class.new(env).call
      outcome = described_class.new(env).call
      expect(outcome).not_to be_written
      expect(outcome.backup).to be_nil
      expect(backups.size).to eq(1)
    end

    it '読み戻して一致しない変更を remaining に返す' do
      allow(device).to receive(:transfer).and_wrap_original do |original, bytes|
        bytes[0] == 0x05 ? bytes + ([0] * (32 - bytes.size)) : original.call(bytes) # キーの書き込みを無視する
      end
      outcome = described_class.new(env).call
      expect(outcome).not_to be_success
      expect(outcome.remaining).to eq(['レイヤー1 (0,1): KC_NO → KC_BSPACE'])
    end
  end

  describe Cornix::Application::DeviceRestore do
    it 'pre-apply のスナップショットがなければ ConfigError' do
      expect { described_class.new(env).call(dry_run: true) }.to raise_error(Cornix::ConfigError, /戻す元のスナップショット/)
    end

    it '既定は最新の pre-apply に戻し、戻す前の状態を pre-restore に残す' do
      write_vil { |v| v['layout'][1][1][1] = 'KC_C' }
      Cornix::Application::DeviceApply.new(env).call
      expect(device.keymap[1][1][1]).to eq(0x06)
      latest = backups.first

      plan = described_class.new(env).call(dry_run: true)
      expect(plan.source).to eq(latest)
      expect(plan.changes).to eq(['レイヤー1 (1,1): KC_C → KC_NO'])

      outcome = described_class.new(env).call(expected_token: plan.token)
      expect(device.keymap[1][1][1]).to eq(0)
      expect(outcome.source).to eq(latest)
      expect(outcome.backup).to eq(snapshots('pre-restore').first)
      expect(env.vil_file.read(outcome.backup).layers[1][1][1]).to eq(0x06)
      expect(backups).to eq([latest])

      # 続けて restore しても既定の戻し先は同じ pre-apply。pre-restore を指定すると復元前に戻る
      expect(described_class.new(env).call(dry_run: true)).to be_empty
      back = described_class.new(env).call(outcome.backup, dry_run: true)
      expect(back.changes).to eq(['レイヤー1 (1,1): KC_NO → KC_C'])
    end

    it 'confirm を DeviceApply と同じく 1 回の接続の中で呼ぶ' do
      path = env.snapshot_store.save(env.vil_file.read(write_vil { |v| v['layout'][1][1][1] = 'KC_C' }), kind: 'pre-apply')
      outcome = described_class.new(env).call(confirm: ->(plan) { plan.source == path && false })
      expect(outcome).to be_cancelled
      expect(device.writes).to be_empty
      expect(opens.size).to eq(1)
    end

    it 'スナップショットの名前でも指定できる' do
      path = env.snapshot_store.save(env.vil_file.read(write_vil { nil }), kind: 'backup', time: Time.new(2026, 1, 2, 3, 4, 5))
      expect(described_class.new(env).call('20260102-030405-backup', dry_run: true).source).to eq(path)
    end

    it '前の版の tmp/device_backups/ のバックアップも既定の戻し先になる' do
      legacy = File.join(env.legacy_backup_dir, '20250101-000000.vil')
      FileUtils.mkdir_p(env.legacy_backup_dir)
      FileUtils.cp(write_vil { |v| v['layout'][1][1][1] = 'KC_C' }, legacy)
      expect(described_class.new(env).call(dry_run: true).source).to eq(legacy)
    end
  end
end
