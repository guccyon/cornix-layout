# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require_relative '../../lib/cornix/device/hid_bridge'

RSpec.describe Cornix::Device::HidBridge do
  let(:dir) { Dir.mktmpdir }
  after { FileUtils.rm_rf(dir) }

  # ブリッジの代わりに動くシェルスクリプトを作る
  def fake_bridge(body)
    path = File.join(dir, 'fake-bridge')
    File.write(path, "#!/bin/sh\n#{body}\n")
    File.chmod(0o755, path)
    path
  end

  it 'キーボードが接続されていないとき、ブリッジのメッセージで DeviceError になる' do
    bridge = fake_bridge('echo "ERROR Cornix が見つかりません"; exit 1')
    expect { described_class.new(bridge) }.to raise_error(Cornix::DeviceError, /見つかりません/)
  end

  it '通信中に接続が切れて応答がないとき DeviceError になる' do
    bridge = fake_bridge(<<~SH)
      echo 'READY {"product":"Cornix"}'
      read line
      echo "ERROR キーボードから応答がありません"
    SH
    hid = described_class.new(bridge)
    expect(hid.info).to eq('product' => 'Cornix')
    expect { hid.transfer([0x01]) }.to raise_error(Cornix::DeviceError, /応答がありません/)
    hid.close
  end

  it 'ブリッジが途中で終了したとき DeviceError になる' do
    bridge = fake_bridge(%(echo 'READY {}'; exit 0))
    hid = described_class.new(bridge)
    expect { hid.transfer([0x01]) }.to raise_error(Cornix::DeviceError, /終了/)
  end

  it '応答した内容を 32 バイトで返す' do
    bridge = fake_bridge(<<~SH)
      echo 'READY {}'
      read line
      echo "RECV 0100090000000000000000000000000000000000000000000000000000000000"
    SH
    hid = described_class.new(bridge)
    expect(hid.transfer([0x01]).first(3)).to eq([1, 0, 9])
    hid.close
  end

  describe '使えない理由（Cornix::DeviceUnavailable#reason）' do
    it 'キーボードが見つからない → :not_connected' do
      bridge = fake_bridge('echo "ERROR Cornix が見つかりません"; exit 1')
      expect { described_class.new(bridge) }.to raise_error(Cornix::DeviceUnavailable) { |e| expect(e.reason).to eq(:not_connected) }
    end

    it 'ブリッジを起動できない → :bridge' do
      expect { described_class.new(File.join(dir, 'missing')) }
        .to raise_error(Cornix::DeviceUnavailable) { |e| expect(e.reason).to eq(:bridge) }
    end

    it '応答がない・ブリッジが終わった → :timeout。ブリッジが送信を拒否したのはただの DeviceError' do
      bridge = fake_bridge(<<~SH)
        echo 'READY {}'
        read line
        echo "ERROR 拒否: via command 0xb"
        read line
        echo "ERROR キーボードから応答がありません"
      SH
      hid = described_class.new(bridge)
      expect { hid.transfer([0x0B]) }.to raise_error(Cornix::DeviceError) { |e| expect(e).not_to be_a(Cornix::DeviceUnavailable) }
      expect { hid.transfer([0x01]) }.to raise_error(Cornix::DeviceUnavailable) { |e| expect(e.reason).to eq(:timeout) }
      hid.close
    end

    it 'macOS でなく、CORNIX_HID_BRIDGE もなければ開く前に :platform' do
      allow(described_class).to receive(:macos?).and_return(false)
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with('CORNIX_HID_BRIDGE', nil).and_return(nil)
      expect { described_class.open }.to raise_error(Cornix::DeviceUnavailable) { |e| expect(e.reason).to eq(:platform) }
    end
  end
end
