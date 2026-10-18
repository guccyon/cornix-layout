# frozen_string_literal: true

require 'spec_helper'
require_relative '../../domain/support/domain_factories'

RSpec.describe Cornix::Mapping::ProfileMapper::Inheritance do
  include DomainFactories

  let(:previous) do
    metadata = Cornix::Domain::Metadata.from_h('keyboard' => 'cornix', 'version' => 1,
                                               'extra_keys' => { 'layout_options' => 0 },
                                               'file_naming' => { 'layers' => {} })
    Cornix::Domain::Profile.new(
      metadata: metadata, settings: Cornix::Domain::QmkSettings::EMPTY, position_map: position_map,
      layers: [build_layer(index: 1, name: 'Symbols', description: '記号')],
      macros: [build_macro(index: 3, name: 'Copy')],
      tap_dances: [build_tap_dance(index: 4, name: 'Tab Escape')],
      combos: [build_combo(index: 0, name: 'Bracket')]
    )
  end

  describe 'previous があるとき' do
    subject(:inheritance) { described_class.new(previous) }

    it '同じ番号の名前と説明を引き継ぐ' do
      expect(inheritance.name(:layer, 1)).to eq('Symbols')
      expect(inheritance.description(:layer, 1)).to eq('記号')
      expect(inheritance.name(:macro, 3)).to eq('Copy')
      expect(inheritance.name(:tap_dance, 4)).to eq('Tab Escape')
      expect(inheritance.name(:combo, 0)).to eq('Bracket')
    end

    it '同じ番号がなければ既定の名前' do
      expect(inheritance.name(:layer, 0)).to eq('Layer 0')
      expect(inheritance.description(:layer, 0)).to be_nil
    end

    it 'keyboard と extra を引き継ぐ' do
      expect(inheritance.keyboard).to eq('cornix')
      expect(inheritance.metadata_extra.keys).to eq(%w[extra_keys file_naming])
    end
  end

  describe 'previous がないとき（旧 decompile の名前）' do
    subject(:inheritance) { described_class.new(nil) }

    it { expect(inheritance.name(:layer, 2)).to eq('Layer 2') }
    it { expect(inheritance.name(:macro, 2)).to eq('Macro 2') }
    it { expect(inheritance.name(:tap_dance, 2)).to eq('TapDance 2') }
    it { expect(inheritance.name(:combo, 2)).to eq('Combo 2') }
    it { expect(inheritance.keyboard).to eq('Cornix') }
    it { expect(inheritance.metadata_extra).to eq({}) }
  end
end
