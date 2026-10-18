# frozen_string_literal: true

require 'spec_helper'
require_relative 'support/domain_factories'

RSpec.describe Cornix::Domain::Combo do
  include DomainFactories

  it '番号・名前・トリガー・出力を持つ' do
    combo = build_combo(index: 2, name: 'Bracket Pair', trigger_keys: [basic(0x0E), basic(0x0F)], output_key: macro_call(0))
    expect(combo.index).to eq(2)
    expect(combo.name).to eq('Bracket Pair')
    expect(combo.trigger_keys).to eq([basic(0x0E), basic(0x0F)])
    expect(combo.trigger_keys).to be_frozen
    expect(combo.output_key).to eq(macro_call(0))
    expect(combo.description).to be_nil
    expect(combo.to_s).to eq('Combo(2: Bracket Pair)')
  end

  it 'トリガーは 1 つでもよい（上限は diagnostics で検査する）' do
    expect(build_combo(trigger_keys: [basic(0x04)]).trigger_keys.size).to eq(1)
    expect(build_combo(trigger_keys: Array.new(5) { |i| basic(0x04 + i) }).trigger_keys.size).to eq(5)
  end

  it '番号は 0〜255' do
    expect { build_combo(index: 256) }.to raise_error(Cornix::InvalidValue, /コンボの番号/)
    expect { build_combo(index: nil) }.to raise_error(Cornix::InvalidValue)
  end

  it '名前は空でない文字列' do
    expect { build_combo(name: '') }.to raise_error(Cornix::InvalidValue, /コンボの名前/)
  end

  it 'トリガーは空でないキーコードの配列' do
    expect { build_combo(trigger_keys: []) }.to raise_error(Cornix::InvalidValue, /トリガーが空/)
    expect { build_combo(trigger_keys: nil) }.to raise_error(Cornix::InvalidValue, /配列/)
    expect { build_combo(trigger_keys: [basic(0x04), 'KC_B']) }.to raise_error(Cornix::InvalidValue, /トリガー\[1\]/)
  end

  it '出力はキーコード' do
    expect { build_combo(output_key: nil) }.to raise_error(Cornix::InvalidValue, /出力/)
  end

  it '出力に注記を持てる' do
    expect(build_combo(notes: { output_key: '括弧' }).output_note).to eq('括弧')
    expect(build_combo.output_note).to be_nil
    expect(build_combo.keycode_at(:output_key)).to eq(basic(0x2F))
    expect { build_combo(notes: { trigger_keys: 'x' }) }.to raise_error(Cornix::InvalidValue, /コンボの注記/)
  end
end
