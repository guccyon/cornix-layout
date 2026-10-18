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
    expect(library).not_to be_empty
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
