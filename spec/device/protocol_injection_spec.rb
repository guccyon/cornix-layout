# frozen_string_literal: true

require 'spec_helper'
require_relative 'fake_rmk_device'

RSpec.describe Cornix::Device::Protocol, '注入する拒否キーコードと設定の幅' do
  let(:device) { FakeRmkDevice.new }
  let(:dims) { { layers: 2, rows: 2, cols: 3, encoders: 1 } }

  it '省略時は従来どおり BOOT_KEYCODES と SETTING_WIDTHS を使う' do
    protocol = described_class.new(device)
    expect { protocol.set_keycode(0, 0, 0, 0x7C00, dims: dims) }.to raise_error(ArgumentError, /boot/)
    expect(protocol.setting_widths).to eq(described_class::SETTING_WIDTHS)
  end

  it '渡した判定と幅を使う' do
    protocol = described_class.new(device, dangerous_keycode: ->(code) { code == 0x04 }, setting_widths: { 22 => 1 })
    expect { protocol.set_keycode(0, 0, 0, 0x04, dims: dims) }.to raise_error(ArgumentError)
    protocol.set_keycode(0, 0, 0, 0x7C00, dims: dims)
    expect(protocol.setting(22)).to eq(0)
    expect { protocol.setting(7) }.to raise_error(Cornix::DeviceError)
  end
end
