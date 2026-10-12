# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require_relative '../../lib/cornix/device/keyboard'
require_relative 'fake_rmk_device'

RSpec.describe Cornix::Device::Keyboard do
  let(:device) { FakeRmkDevice.new }
  let(:keyboard) do
    protocol = Cornix::Device::Protocol.new(device)
    allow(protocol).to receive(:definition).and_return(FakeRmkDevice::DEFINITION)
    described_class.new(protocol)
  end
  let(:backup_dir) { Dir.mktmpdir }

  before { stub_const("#{described_class}::BACKUP_DIR", backup_dir) }
  after { FileUtils.rm_rf(backup_dir) }

  it 'キーボードの状態を layout.vil 形式で読む（存在しない位置は -1）' do
    snap = keyboard.snapshot
    expect(snap['layout'][0]).to eq([%w[KC_A KC_NO KC_NO], ['KC_NO', 'KC_NO', -1]])
    expect(snap['encoder_layout'][0]).to eq([%w[KC_VOLD KC_VOLU]])
    expect(snap['macro']).to eq([[], [], [], []])
    expect(snap['tap_dance'][0]).to eq(['KC_NO', 'KC_NO', 'KC_NO', 'KC_NO', 250])
    expect(snap['settings']).to eq('2' => 50, '7' => 200, '22' => 0)
  end

  it '読み出した状態との差分は空' do
    expect(keyboard.diff(keyboard.snapshot)[:changes]).to be_empty
  end

  context '変更がある場合' do
    let(:target) do
      keyboard.snapshot.tap do |t|
        t['layout'][1][0][1] = 'KC_BSPC'
        t['encoder_layout'][1][0][1] = 'KC_MUTE'
        t['tap_dance'][1] = ['KC_B', 'MO(1)', 'KC_NO', 'KC_NO', 200]
        t['combo'][0] = ['KC_A', 'KC_S', 'KC_NO', 'KC_NO', 'M0']
        t['macro'][2] = [['text', 'hi'], ['tap', 'LSFT(KC_2)']]
        t['settings']['7'] = 180
      end
    end

    it 'dry run は差分だけを返し、何も書き込まない' do
      result = keyboard.diff(target)
      expect(result[:changes].map { |c| c[:kind] }).to eq(%i[key encoder tap_dance combo macro setting])
      expect(keyboard.format_change(result[:changes].first)).to eq('レイヤー1 (0,1): KC_NO → KC_BSPACE')
      expect(device.writes).to be_empty
    end

    it '差分だけを書き込み、バックアップを取り、読み戻して一致を確認する' do
      token = keyboard.diff(target)[:token]
      result = keyboard.apply(target, expected_token: token)
      expect(result[:applied]).to eq(6)
      expect(result[:remaining]).to be_empty
      expect(File).to exist(result[:backup])
      expect(device.sent.count { |m| m[0] == 0x05 }).to eq(1)
      expect(device.keymap[1][0][1]).to eq(0x2A)
      expect(device.settings[7]).to eq(180)
      expect(keyboard.diff(target)[:changes]).to be_empty
    end

    it '確認時から差分が変わっていたら書き込まない' do
      expect { keyboard.apply(target, expected_token: 'stale') }.to raise_error(Cornix::Device::DeviceError, /変わって/)
      expect(device.writes).to be_empty
    end
  end

  it 'boot 系キーコードを含む差分は書き込み前に拒否する' do
    target = keyboard.snapshot.tap { |t| t['layout'][0][0][1] = 'QK_BOOT' }
    expect { keyboard.diff(target) }.to raise_error(Cornix::Device::DeviceError, /QK_BOOT/)
    expect { keyboard.apply(target) }.to raise_error(Cornix::Device::DeviceError)
    expect(device.writes).to be_empty
  end

  it 'キーボードに存在しない位置やレイヤーは書き込まない' do
    target = keyboard.snapshot.tap { |t| t['layout'][0][1][2] = 'KC_X' }
    result = keyboard.diff(target)
    expect(result[:changes]).to be_empty
    expect(result[:warnings].join).to include('存在しない位置')

    too_many = keyboard.snapshot.tap { |t| t['layout'] << t['layout'][0] }
    expect { keyboard.diff(too_many) }.to raise_error(Cornix::Device::DeviceError, /レイヤー数/)
  end

  it 'マクロがバッファに収まらない場合は拒否する' do
    target = keyboard.snapshot.tap { |t| t['macro'][0] = [['text', 'x' * 100]] }
    expect { keyboard.diff(target) }.to raise_error(Cornix::Device::DeviceError, /収まりません/)
  end
end
