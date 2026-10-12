# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/cornix/device/keycodes'
require_relative '../../lib/cornix/device/macro_codec'

RSpec.describe Cornix::Device::MacroCodec do
  subject(:codec) { described_class.new(Cornix::Device::Keycodes.new) }

  it 'tap/down/up/text/delay を Vial と同じバイト列にする' do
    macro = [['down', 'KC_LSHIFT'], ['tap', 'KC_9', 'KC_0'], ['up', 'KC_LSHIFT'], ['text', 'ab'], ['delay', 300]]
    expect(codec.encode(macro).bytes).to eq(
      [1, 2, 0xE1, 1, 1, 0x26, 1, 1, 0x27, 1, 3, 0xE1, 0x61, 0x62, 1, 4, 46, 2]
    )
  end

  it '16bit キーコードは拡張コードで、下位バイトが 0 の場合は 0xFF00 形式にする' do
    expect(codec.encode([['tap', 'LSFT(KC_2)']]).bytes).to eq([1, 5, 0x1F, 0x02])
    expect(codec.encode([['tap', 'LSFT(KC_NO)']]).bytes).to eq([1, 5, 0x02, 0xFF])
  end

  it '往復で同じマクロに戻る' do
    macros = [
      [['tap', 'KC_LBRACKET', 'KC_RBRACKET', 'KC_LEFT']],
      [['down', 'KC_LGUI'], ['tap', 'KC_C'], ['up', 'KC_LGUI'], ['tap', 'KC_RIGHT']],
      [['text', 'hello'], ['delay', 1000], ['tap', 'LSFT(KC_2)', 'LSFT(KC_NO)']],
      []
    ]
    buffer = codec.encode_all(macros)
    expect(buffer.count("\x00")).to eq(4)
    expect(codec.decode_all(buffer, 4)).to eq(macros)
  end

  it 'NUL を含む text は拒否する' do
    expect { codec.encode([['text', "a\x00b"]]) }.to raise_error(ArgumentError)
  end
end
