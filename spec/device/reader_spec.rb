# frozen_string_literal: true

require 'spec_helper'
require_relative 'fake_rmk_device'

RSpec.describe Cornix::Device::Reader do
  let(:device) { FakeRmkDevice.new }
  let(:session) { Cornix::Device::Session.new(device, definition: FakeRmkDevice::DEFINITION) }
  subject(:image) { described_class.new(session).read }

  it 'キーボードの状態を DeviceImage として読む（キーのない位置は nil）' do
    expect(image.layers).to eq([[[4, 0, 0], [0, 0, nil]], [[0, 0, 0], [0, 0, nil]]])
    expect(image.encoders[0]).to all(eq(Cornix::Image::EncoderRecord.new(ccw: 0xAA, cw: 0xA9)))
    expect(image.macros).to eq([[], [], [], []])
    expect(image.tap_dances[0]).to eq(Cornix::Image::TapDanceRecord.new(on_tap: 0, on_hold: 0, on_double_tap: 0,
                                                                        on_tap_hold: 0, tapping_term: 250))
    expect(image.combos[1]).to eq(Cornix::Image::ComboRecord.new(keys: [0, 0, 0, 0], output: 0))
    expect(image.settings).to eq(2 => 50, 7 => 200, 22 => 0)
    expect(image.meta).to eq('version' => 1, 'uid' => 0x0807060504030201, 'vial_protocol' => 6, 'via_protocol' => 9,
                             'layout_options' => 0, 'alt_repeat_key' => [], 'key_override' => [])
  end

  it 'マクロバッファを MacroCodec で解読する' do
    bytes = [1, 2, 0xE1, 0x61, 0, 1, 5, 0x1F, 0x02, 0, 0, 0]
    device.macro[0, bytes.size] = bytes
    expect(image.macros).to eq([
      [Cornix::Image::MacroAction.new(kind: :down, keys: [0xE1]), Cornix::Image::MacroAction.new(kind: :text, value: 'a')],
      [Cornix::Image::MacroAction.new(kind: :tap, keys: [0x021F])], [], []
    ])
  end

  it '書き込みのコマンドを送らない' do
    image
    expect(device.writes).to be_empty
  end

  it '旧 Device::Keyboard#snapshot と同じ値を読む' do
    device.keymap[1][1][1] = 0x0204
    device.macro[0, 4] = [1, 1, 0x05, 0]
    device.tap_dances[1] = [5, 0x5221, 0, 0, 180]
    protocol = Cornix::Device::Protocol.new(device)
    allow(protocol).to receive(:definition).and_return(FakeRmkDevice::DEFINITION)
    keyboard = Cornix::Device::Keyboard.new(protocol)
    snap = keyboard.snapshot
    kc = keyboard.keycodes

    expect(image.layers.map { |rows| rows.map { |cols| cols.map { |v| v.nil? ? -1 : kc.decode(v) } } }).to eq(snap['layout'])
    expect(image.encoders.map { |es| es.map { |e| [kc.decode(e.ccw), kc.decode(e.cw)] } }).to eq(snap['encoder_layout'])
    expect(image.tap_dances.map { |t| [t.on_tap, t.on_hold, t.on_double_tap, t.on_tap_hold].map { |v| kc.decode(v) } + [t.tapping_term] })
      .to eq(snap['tap_dance'])
    expect(image.macros.map { |m| m.map { |a| [a.kind.to_s, *a.keys.map { |v| kc.decode(v) }] } }).to eq(snap['macro'])
    expect(image.settings.transform_keys(&:to_s)).to eq(snap['settings'])
    expect(image.meta.slice('uid', 'vial_protocol', 'via_protocol')).to eq(snap.slice('uid', 'vial_protocol', 'via_protocol'))
  end
end
