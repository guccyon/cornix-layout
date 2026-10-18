# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Cornix::Domain::ShortcutLibrary do
  include DomainFactories

  let(:copy) { basic(0x06) }
  let(:paste) { basic(0x19) }

  it '名前 => Keycode を定義順に持ち、名前の前後の空白は除く' do
    library = described_class.new(entries: { ' Copy ' => copy, 'Paste' => paste })
    expect(library.entries).to eq('Copy' => copy, 'Paste' => paste)
    expect(library.names).to eq(%w[Copy Paste])
    expect(library.size).to eq(2)
    expect(library).not_to be_empty
  end

  it '#fetch は名前の Keycode（前後の空白は無視）。なければ nil' do
    library = described_class.new(entries: { 'Copy' => copy })
    expect(library.fetch(' Copy')).to eq(copy)
    expect(library.fetch('Nope')).to be_nil
    expect(library.fetch(nil)).to be_nil
  end

  it '#names_for は同じ値を持つ名前の一覧' do
    library = described_class.new(entries: { 'A' => copy, 'B' => paste, 'C' => copy })
    expect(library.names_for(copy)).to eq(%w[A C])
    expect(library.names_for(basic(0x04))).to eq([])
  end

  it 'EMPTY は空' do
    expect(described_class::EMPTY).to be_empty
    expect(described_class::EMPTY).to eq(described_class.new)
  end

  describe '構造検証' do
    it '空の名前・空白だけ違う重複・キーコードでない値は InvalidValue' do
      expect { described_class.new(entries: { ' ' => copy }) }.to raise_error(Cornix::InvalidValue, /空でない文字列/)
      expect { described_class.new(entries: { 'A' => copy, ' A' => paste }) }
        .to raise_error(Cornix::InvalidValue, /重複しています: "A"/)
      expect { described_class.new(entries: { 'A' => 'Tab' }) }.to raise_error(Cornix::InvalidValue, /キーコード/)
      expect { described_class.new(entries: []) }.to raise_error(Cornix::InvalidValue, /名前 => Keycode/)
    end
  end
end
