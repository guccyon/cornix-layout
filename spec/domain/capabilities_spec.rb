# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Cornix::Domain::Capabilities do
  it 'CORNIX は 10 レイヤー、マクロ・タップダンス・コンボ 32 件、トリガー 4 個' do
    caps = described_class::CORNIX
    expect(caps.layers).to eq(10)
    expect(caps.macros).to eq(32)
    expect(caps.tap_dances).to eq(32)
    expect(caps.combos).to eq(32)
    expect(caps.combo_keys).to eq(4)
    expect(caps.unsupported_keycodes).to eq({})
  end

  it 'unsupported_keycodes は値 => 説明の Hash で、freeze される' do
    caps = described_class::CORNIX.with(unsupported_keycodes: { 0x7C79 => 'QK_REPEAT_KEY: 非対応' })
    expect(caps.unsupported_keycodes).to eq(0x7C79 => 'QK_REPEAT_KEY: 非対応')
    expect(caps.unsupported_keycodes).to be_frozen
    expect { described_class::CORNIX.with(unsupported_keycodes: { 'x' => 'a' }) }
      .to raise_error(Cornix::InvalidValue, /キーコードの値/)
    expect { described_class::CORNIX.with(unsupported_keycodes: { 0x7C79 => '' }) }
      .to raise_error(Cornix::InvalidValue, /説明/)
  end

  it '範囲外は InvalidValue' do
    expect { described_class.new(layers: 0, macros: 1, tap_dances: 1, combos: 1, combo_keys: 1) }
      .to raise_error(Cornix::InvalidValue, /レイヤーの数/)
    expect { described_class.new(layers: 1, macros: -1, tap_dances: 1, combos: 1, combo_keys: 1) }
      .to raise_error(Cornix::InvalidValue, /マクロの数/)
    expect { described_class.new(layers: 1, macros: 1, tap_dances: 1, combos: 1, combo_keys: 0) }
      .to raise_error(Cornix::InvalidValue, /トリガー/)
  end
end
