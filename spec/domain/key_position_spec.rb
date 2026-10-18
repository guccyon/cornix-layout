# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Cornix::Domain::KeyPosition do
  it '手・行・列を持つ' do
    pos = described_class.new(hand: :right, row: 2, col: 5)
    expect([pos.hand, pos.row, pos.col]).to eq([:right, 2, 5])
    expect(pos).to be_right
    expect(pos).not_to be_left
    expect(pos.to_s).to eq('right(2, 5)')
  end

  it '同じ値なら等しく、Hash のキーに使える' do
    a = described_class.new(hand: :left, row: 0, col: 0)
    b = described_class.new(hand: :left, row: 0, col: 0)
    expect(a).to eq(b)
    expect({ a => 1 }[b]).to eq(1)
  end

  it 'row 3 の col 3〜5 が親指キー' do
    expect(described_class.new(hand: :left, row: 3, col: 3)).to be_thumb
    expect(described_class.new(hand: :left, row: 3, col: 5)).to be_thumb
    expect(described_class.new(hand: :left, row: 3, col: 2)).not_to be_thumb
    expect(described_class.new(hand: :left, row: 2, col: 4)).not_to be_thumb
  end

  it '範囲外は InvalidValue' do
    expect { described_class.new(hand: :middle, row: 0, col: 0) }.to raise_error(Cornix::InvalidValue, /手/)
    expect { described_class.new(hand: 'left', row: 0, col: 0) }.to raise_error(Cornix::InvalidValue)
    expect { described_class.new(hand: :left, row: 4, col: 0) }.to raise_error(Cornix::InvalidValue, /論理行/)
    expect { described_class.new(hand: :left, row: -1, col: 0) }.to raise_error(Cornix::InvalidValue)
    expect { described_class.new(hand: :left, row: 0, col: 6) }.to raise_error(Cornix::InvalidValue, /論理列/)
    expect { described_class.new(hand: :left, row: 0, col: '1') }.to raise_error(Cornix::InvalidValue)
  end
end
