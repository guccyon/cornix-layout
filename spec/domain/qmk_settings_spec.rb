# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Cornix::Domain::QmkSettings do
  it 'QSID => 値 を QSID の昇順で持つ' do
    settings = described_class.new(values: { 27 => 120, 2 => 50, 7 => 180, 22 => 0 })
    expect(settings.values.keys).to eq([2, 7, 22, 27])
    expect(settings[7]).to eq(180)
    expect(settings[99]).to be_nil
    expect(settings.key?(22)).to be true
    expect(settings.size).to eq(4)
    expect(settings.to_h).to be_frozen
  end

  it '空でもよい' do
    expect(described_class.new).to be_empty
    expect(described_class::EMPTY).to eq(described_class.new(values: {}))
  end

  it '並びが違っても同じ内容なら等しい' do
    expect(described_class.new(values: { 2 => 1, 7 => 2 })).to eq(described_class.new(values: { 7 => 2, 2 => 1 }))
  end

  it 'QSID は 0〜65535、値は 0〜0xFFFFFFFF の整数' do
    expect { described_class.new(values: { '7' => 180 }) }.to raise_error(Cornix::InvalidValue, /QSID/)
    expect { described_class.new(values: { 0x10000 => 1 }) }.to raise_error(Cornix::InvalidValue)
    expect { described_class.new(values: { 22 => true }) }.to raise_error(Cornix::InvalidValue, /22 の値/)
    expect { described_class.new(values: { 7 => -1 }) }.to raise_error(Cornix::InvalidValue)
    expect { described_class.new(values: { 7 => 0x1_0000_0000 }) }.to raise_error(Cornix::InvalidValue)
    expect { described_class.new(values: nil) }.to raise_error(Cornix::InvalidValue, /Hash/)
  end
end
