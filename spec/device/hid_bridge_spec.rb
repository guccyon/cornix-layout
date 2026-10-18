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
end
