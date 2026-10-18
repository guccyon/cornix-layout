# frozen_string_literal: true

require 'spec_helper'
require_relative 'support/domain_factories'

RSpec.describe Cornix::Domain::MacroStep do
  include DomainFactories

  let(:step) { described_class }

  describe 'Tap / Down / Up' do
    it 'キーコードの配列を持ち、kind を返す' do
      { step::Tap => :tap, step::Down => :down, step::Up => :up }.each do |klass, kind|
        s = klass.new(keys: [basic(0xE3), basic(0x06)])
        expect(s.keys).to eq([basic(0xE3), basic(0x06)])
        expect(s.keys).to be_frozen
        expect(s.kind).to eq(kind)
        expect(step.step?(s)).to be true
      end
    end

    it '16bit のキーコードならどれでもよい（Vial の拡張形式で送れる）' do
      expect(step::Tap.new(keys: [k::Modified.new(mods: Cornix::Domain::ModifierSet.new(side: :left, mods: [:gui]),
                                                  base: basic(0x06))]).keys.size).to eq(1)
    end

    it 'キーが空・キーコード以外なら InvalidValue' do
      expect { step::Tap.new(keys: []) }.to raise_error(Cornix::InvalidValue, /tap のキーが空/)
      expect { step::Down.new(keys: nil) }.to raise_error(Cornix::InvalidValue, /配列/)
      expect { step::Up.new(keys: [basic(0x04), 'KC_A']) }.to raise_error(Cornix::InvalidValue, /up のキー\[1\]/)
    end
  end

  describe 'Delay' do
    it 'ミリ秒を持つ（0〜65024）' do
      expect(step::Delay.new(ms: 100).ms).to eq(100)
      expect(step::Delay.new(ms: 0).kind).to eq(:delay)
      expect(step::Delay.new(ms: 65_024).ms).to eq(65_024)
    end

    it '範囲外・整数以外は InvalidValue' do
      expect { step::Delay.new(ms: 65_025) }.to raise_error(Cornix::InvalidValue, /delay/)
      expect { step::Delay.new(ms: -1) }.to raise_error(Cornix::InvalidValue)
      expect { step::Delay.new(ms: '100') }.to raise_error(Cornix::InvalidValue)
      expect { step::Delay.new(ms: 1.5) }.to raise_error(Cornix::InvalidValue)
    end
  end

  describe 'Text' do
    it '文字列を持つ' do
      s = step::Text.new(content: "```\n")
      expect(s.content).to eq("```\n")
      expect(s.content).to be_frozen
      expect(s.kind).to eq(:text)
    end

    it '空・文字列以外・ASCII 以外・NUL / 0x01 は InvalidValue' do
      expect { step::Text.new(content: '') }.to raise_error(Cornix::InvalidValue, /空/)
      expect { step::Text.new(content: nil) }.to raise_error(Cornix::InvalidValue, /文字列/)
      expect { step::Text.new(content: 'あ') }.to raise_error(Cornix::InvalidValue, /ASCII/)
      expect { step::Text.new(content: "a\x00b") }.to raise_error(Cornix::InvalidValue, /NUL/)
      expect { step::Text.new(content: "a\x01b") }.to raise_error(Cornix::InvalidValue)
    end
  end

  it 'step? / check! で命令かどうかを調べる' do
    expect(step.step?(basic(0x04))).to be false
    expect { step.check!(:tap) }.to raise_error(Cornix::InvalidValue, /マクロの命令/)
  end
end
