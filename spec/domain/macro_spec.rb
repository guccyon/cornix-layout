# frozen_string_literal: true

require 'spec_helper'
require_relative 'support/domain_factories'

RSpec.describe Cornix::Domain::Macro do
  include DomainFactories

  let(:steps) do
    [d::MacroStep::Down.new(keys: [basic(0xE3)]), d::MacroStep::Tap.new(keys: [basic(0x07), basic(0x06)]),
     d::MacroStep::Up.new(keys: [basic(0xE3)]), d::MacroStep::Delay.new(ms: 50), d::MacroStep::Text.new(content: 'x')]
  end

  it '番号・名前・説明・命令を持つ' do
    macro = described_class.new(index: 3, name: 'Copy Current Word', description: '単語をコピー', steps: steps)
    expect(macro.index).to eq(3)
    expect(macro.name).to eq('Copy Current Word')
    expect(macro.description).to eq('単語をコピー')
    expect(macro.steps).to eq(steps)
    expect(macro.steps).to be_frozen
    expect(macro.to_s).to eq('Macro(3: Copy Current Word)')
  end

  it 'preset はプリセットの名前（省略すると nil。空・文字列でなければ InvalidValue）' do
    expect(build_macro.preset).to be_nil
    macro = described_class.new(index: 0, name: 'Copy', steps: steps, preset: 'macOS:テキスト:コピー')
    expect(macro.preset).to eq('macOS:テキスト:コピー')
    expect { described_class.new(index: 0, name: 'Copy', steps: steps, preset: ' ') }
      .to raise_error(Cornix::InvalidValue, /マクロのプリセットの名前/)
    expect { described_class.new(index: 0, name: 'Copy', steps: steps, preset: 1) }.to raise_error(Cornix::InvalidValue)
  end

  it '番号は M0〜M127 の範囲（デバイスの件数との比較は diagnostics）' do
    expect(build_macro(index: 127).index).to eq(127)
    expect { build_macro(index: 128) }.to raise_error(Cornix::InvalidValue, /マクロの番号/)
    expect { build_macro(index: -1) }.to raise_error(Cornix::InvalidValue)
    expect { build_macro(index: nil) }.to raise_error(Cornix::InvalidValue)
  end

  it '名前は空でない文字列' do
    expect { build_macro(name: '') }.to raise_error(Cornix::InvalidValue, /マクロの名前/)
    expect { build_macro(name: nil) }.to raise_error(Cornix::InvalidValue)
  end

  it '命令は 1 つ以上の MacroStep' do
    expect { build_macro(steps: []) }.to raise_error(Cornix::InvalidValue, /steps が空/)
    expect { build_macro(steps: nil) }.to raise_error(Cornix::InvalidValue, /配列/)
    expect { build_macro(steps: [{ 'action' => 'tap' }]) }.to raise_error(Cornix::InvalidValue, /steps\[0\]/)
  end

  it '説明は文字列か nil' do
    expect(build_macro.description).to be_nil
    expect { described_class.new(index: 0, name: 'a', steps: steps, description: []) }.to raise_error(Cornix::InvalidValue)
  end
end
