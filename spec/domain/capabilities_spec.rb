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
