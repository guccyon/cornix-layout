# frozen_string_literal: true

require 'spec_helper'
require_relative 'fake_rmk_device'

RSpec.describe Cornix::Device::Session do
  let(:device) { FakeRmkDevice.new }
  subject(:session) { described_class.new(device, definition: FakeRmkDevice::DEFINITION, connection_info: { 'transport' => 'test' }) }

  it 'キーボードの形を読み出す' do
    expect(session.dims).to eq(layers: 2, rows: 2, cols: 3, encoders: 1)
    expect(session.key_position?(1, 1)).to be(true)
    expect(session.key_position?(1, 2)).to be(false)
    expect(session.macro_count).to eq(4)
    expect(session.macro_buffer_size).to eq(64)
    expect(session.entry_counts).to eq(tap_dance: 2, combo: 2, key_override: 0)
    expect(session.setting_ids).to eq([2, 7, 22])
  end

  it 'info は旧 Device::Keyboard#info と同じ項目を返す' do
    info = session.info
    expect(info).to include(name: 'Fake', via_protocol: 9, vial_protocol: 6, layers: 2, encoders: 1,
                            macros: { count: 4, buffer_size: 64 }, tap_dance: 2, combo: 2, settings: [2, 7, 22],
                            connection: { 'transport' => 'test' })
    expect(info[:lock]).to include(unlocked: false)
  end

  it 'Protocol に KeycodeCatalog#dangerous? と QmkSettingCatalog の幅を渡す' do
    expect(session.protocol.setting_widths).to eq(Cornix::Device::Protocol::SETTING_WIDTHS)
    expect { session.protocol.set_keycode(0, 0, 0, 0x7C00, dims: session.dims) }.to raise_error(ArgumentError, /boot/)
    expect(device.writes).to be_empty
  end

  it '書き込みを拒否するキーコードは渡したカタログに従う' do
    catalog = instance_double(Cornix::Mapping::KeycodeCatalog, dangerous?: false)
    allow(catalog).to receive(:dangerous?).with(0x04).and_return(true)
    s = described_class.new(device, catalog: catalog, definition: FakeRmkDevice::DEFINITION)
    expect { s.protocol.set_keycode(0, 0, 0, 0x04, dims: s.dims) }.to raise_error(ArgumentError)
    s.protocol.set_keycode(0, 0, 0, 0x05, dims: s.dims)
    expect(device.keymap[0][0][0]).to eq(0x05)
  end
end
