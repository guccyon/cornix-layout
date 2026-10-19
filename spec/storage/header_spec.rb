# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Cornix::Storage::Schema::Header do
  it '名前と番号を読む（正しくなければ nil）' do
    expect(described_class.call({ 'name' => 'A', 'index' => 1 })).to eq(['A', 1])
    expect(described_class.call({ 'name' => ' ', 'index' => 1 })).to be_nil
    expect(described_class.call({ 'name' => 'A', 'index' => '1' })).to be_nil
    expect(described_class.call([])).to be_nil
  end

  it 'マクロ（preset: true）は name がなければ preset の名前（前後の空白を除く）' do
    expect(described_class.call({ 'index' => 1, 'preset' => ' App:X ' }, preset: true)).to eq(['App:X', 1])
    expect(described_class.call({ 'index' => 1, 'preset' => ' App:X ' })).to be_nil
    expect(described_class.call({ 'name' => 'A', 'index' => 1, 'preset' => 'App:X' }, preset: true)).to eq(['A', 1])
    expect(described_class.call({ 'name' => nil, 'index' => 1, 'preset' => 'App:X' }, preset: true)).to be_nil
    expect(described_class.call({ 'index' => 1, 'preset' => 1 }, preset: true)).to be_nil
  end

  it 'name_of はファイルの name（検査はしない）' do
    expect(described_class.name_of({ 'name' => 1 })).to eq(1)
    expect(described_class.name_of({ 'preset' => 'App:X' }, preset: true)).to eq('App:X')
    expect(described_class.name_of({ 'preset' => 'App:X' })).to be_nil
    expect(described_class.name_of(nil, preset: true)).to be_nil
  end
end
