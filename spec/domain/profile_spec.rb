# frozen_string_literal: true

require 'spec_helper'
require_relative 'support/domain_factories'

RSpec.describe Cornix::Domain::Profile do
  include DomainFactories

  let(:macros) { [build_macro(index: 0, name: 'Bracket Pair'), build_macro(index: 2, name: 'Copy')] }
  let(:tap_dances) { [build_tap_dance(index: 4, name: 'Tab Escape')] }
  let(:combos) { [build_combo(index: 0, name: 'Bracket')] }
  let(:profile) do
    build_profile(layers: [build_layer(index: 0), build_layer(index: 1)], macros: macros, tap_dances: tap_dances,
                  combos: combos)
  end

  it '集約の要素を持つ' do
    expect(profile.metadata.keyboard).to eq('cornix')
    expect(profile.settings).to eq(d::QmkSettings::EMPTY)
    expect(profile.position_map).to eq(position_map)
    expect(profile.layers.map(&:index)).to eq([0, 1])
    expect(profile.layers).to be_frozen
    expect(profile.macros).to be_frozen
  end

  it 'macros / tap_dances / combos は省略できる' do
    p = d::Profile.new(metadata: build_metadata, settings: d::QmkSettings::EMPTY, position_map: position_map, layers: [])
    expect([p.macros, p.tap_dances, p.combos]).to eq([[], [], []])
  end

  it '番号で要素を引く' do
    expect(profile.layer(1).index).to eq(1)
    expect(profile.macro(2).name).to eq('Copy')
    expect(profile.tap_dance(4).name).to eq('Tab Escape')
    expect(profile.combo(0).name).to eq('Bracket')
    expect(profile.macro(1)).to be_nil
  end

  describe '#references / #macro_names / #tap_dance_names' do
    it '名前 => 番号 の Hash を返す（Mapping に依存しない形）' do
      expect(profile.macro_names).to eq('Bracket Pair' => 0, 'Copy' => 2)
      expect(profile.tap_dance_names).to eq('Tab Escape' => 4)
      expect(profile.references).to eq(macros: { 'Bracket Pair' => 0, 'Copy' => 2 }, tap_dances: { 'Tab Escape' => 4 })
    end

    it 'Mapping::References にそのまま渡せる' do
      refs = Cornix::Mapping::References.new(**profile.references)
      expect(refs.macro_index('Copy')).to eq(2)
      expect(refs.tap_dance_name(4)).to eq('Tab Escape')
    end

    it '名前が重複していれば先のものを使う' do
      p = build_profile(macros: [build_macro(index: 3, name: 'A'), build_macro(index: 1, name: 'A')])
      expect(p.macro_names).to eq('A' => 3)
    end
  end

  describe '構造検証' do
    it '各要素の型' do
      expect { d::Profile.new(metadata: {}, settings: d::QmkSettings::EMPTY, position_map: position_map, layers: []) }
        .to raise_error(Cornix::InvalidValue, /メタデータ/)
      expect { d::Profile.new(metadata: build_metadata, settings: {}, position_map: position_map, layers: []) }
        .to raise_error(Cornix::InvalidValue, /QMK の設定/)
      expect { d::Profile.new(metadata: build_metadata, settings: d::QmkSettings::EMPTY, position_map: position_map_hash, layers: []) }
        .to raise_error(Cornix::InvalidValue, /position_map/)
      expect { build_profile(layers: nil) }.to raise_error(Cornix::InvalidValue, /レイヤー/)
      expect { build_profile(layers: [build_macro]) }.to raise_error(Cornix::InvalidValue, /レイヤー\[0\]/)
      expect { build_profile(macros: [build_layer]) }.to raise_error(Cornix::InvalidValue, /マクロ\[0\]/)
      expect { build_profile(tap_dances: [nil]) }.to raise_error(Cornix::InvalidValue, /タップダンス\[0\]/)
      expect { build_profile(combos: {}) }.to raise_error(Cornix::InvalidValue, /コンボ/)
    end
  end

  it '#diagnostics は既定で Capabilities::CORNIX を使う' do
    expect(profile.diagnostics).to eq([])
    tight = d::Capabilities.new(layers: 1, macros: 32, tap_dances: 32, combos: 32, combo_keys: 4)
    expect(profile.diagnostics(tight).map(&:path)).to include('layers', 'layers[1].index')
  end
end
