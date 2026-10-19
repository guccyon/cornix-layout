# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Cornix::Mapping::References do
  let(:a) { Cornix::Domain::Keycode::Basic.new(code: 0x04) }

  describe '名前の一覧' do
    subject(:references) do
      described_class.new(macros: { 'Bracket Pair' => 0, 'Quote' => 3 }, tap_dances: { 'Tab Escape' => 4 },
                          shortcuts: { '前のタブへ' => a }, preset_shortcuts: { 'App:Cat:X' => a })
    end

    it 'マクロ・タップダンスの名前を渡した順に返す' do
      expect(references.macro_names).to eq(['Bracket Pair', 'Quote'])
      expect(references.tap_dance_names).to eq(['Tab Escape'])
    end

    it 'shortcut_names は利用者の定義だけで、同梱の定義を含めない' do
      expect(references.shortcut_names).to eq(['前のタブへ'])
    end

    it 'NONE ではどれも空' do
      none = described_class::NONE
      expect([none.macro_names, none.tap_dance_names, none.shortcut_names]).to all(be_empty)
    end
  end
end
