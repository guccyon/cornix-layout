# frozen_string_literal: true

require 'spec_helper'
require_relative 'support/domain_factories'

RSpec.describe Cornix::Domain::Layer do
  include DomainFactories

  let(:tab) { key_position(:left, 0, 0) }

  it '番号・名前・説明・キー・エンコーダを持つ' do
    layer = build_layer(index: 3, name: 'Function', description: 'F keys', keys: { tab => basic(0x2B) })
    expect(layer.index).to eq(3)
    expect(layer.name).to eq('Function')
    expect(layer.description).to eq('F keys')
    expect(layer.key(tab)).to eq(basic(0x2B))
    expect(layer.key(key_position(:right, 0, 0))).to be_nil
    expect(layer.encoder(:left)).to eq(encoder_binding)
    expect(layer.to_s).to eq('Layer(3: Function)')
  end

  it '説明は省略できる' do
    expect(build_layer.description).to be_nil
  end

  it 'keys と encoders は freeze した複製' do
    keys = { tab => basic(0x2B) }
    layer = build_layer(keys: keys)
    keys[key_position(:left, 0, 1)] = basic(0x14)
    expect(layer.keys.size).to eq(1)
    expect(layer.keys).to be_frozen
    expect(layer.encoders).to be_frozen
  end

  describe '構造検証' do
    it '番号は 0〜31 の整数（デバイスのレイヤー数との比較は diagnostics）' do
      expect(build_layer(index: 31).index).to eq(31)
      expect { build_layer(index: 32) }.to raise_error(Cornix::InvalidValue, /レイヤーの番号/)
      expect { build_layer(index: -1) }.to raise_error(Cornix::InvalidValue)
      expect { build_layer(index: '0') }.to raise_error(Cornix::InvalidValue)
      expect { build_layer(index: nil) }.to raise_error(Cornix::InvalidValue)
    end

    it '名前は空でない 50 文字までの文字列' do
      expect(build_layer(name: 'a' * 50).name.size).to eq(50)
      expect { build_layer(name: 'a' * 51) }.to raise_error(Cornix::InvalidValue, /50 文字/)
      expect { build_layer(name: '') }.to raise_error(Cornix::InvalidValue, /レイヤーの名前/)
      expect { build_layer(name: '  ') }.to raise_error(Cornix::InvalidValue)
      expect { build_layer(name: nil) }.to raise_error(Cornix::InvalidValue)
    end

    it '説明は文字列か nil' do
      expect { build_layer(description: 1) }.to raise_error(Cornix::InvalidValue, /説明/)
    end

    it 'keys は KeyPosition => Keycode の Hash' do
      expect { build_layer(keys: []) }.to raise_error(Cornix::InvalidValue, /Hash/)
      expect { build_layer(keys: { 'left_hand.row0.tab' => basic(0x2B) }) }.to raise_error(Cornix::InvalidValue, /キーの位置/)
      expect { build_layer(keys: { tab => 'Tab' }) }.to raise_error(Cornix::InvalidValue, /left\(0, 0\) のキーコード/)
    end

    it 'encoders は :left と :right の EncoderBinding' do
      expect { build_layer(encoders: { left: encoder_binding }) }.to raise_error(Cornix::InvalidValue, /right がありません/)
      expect { build_layer(encoders: { left: encoder_binding, right: nil }) }.to raise_error(Cornix::InvalidValue)
      expect { build_layer(encoders: { left: encoder_binding, right: encoder_binding, center: encoder_binding }) }
        .to raise_error(Cornix::InvalidValue, /左右/)
      expect { build_layer(encoders: nil) }.to raise_error(Cornix::InvalidValue)
    end
  end
end
