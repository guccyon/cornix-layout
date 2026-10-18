# frozen_string_literal: true

require 'spec_helper'
require_relative '../domain/support/domain_factories'

RSpec.describe Cornix::Mapping::ProfileMapper do
  include DomainFactories

  subject(:mapper) { described_class.new(codec: Cornix::Mapping::KeycodeCodec.new, capabilities: caps) }

  let(:caps) { Cornix::Domain::Capabilities::CORNIX }

  describe '#to_image' do
    it 'Profile でなければ InvalidValue' do
      expect { mapper.to_image(:x) }.to raise_error(Cornix::InvalidValue)
    end

    it '枠の数は capabilities に従う' do
      small = Cornix::Domain::Capabilities.new(layers: 2, macros: 1, tap_dances: 3, combos: 4, combo_keys: 2)
      image = described_class.new(capabilities: small).to_image(build_profile)
      expect([image.layers.size, image.encoders.size, image.macros.size, image.tap_dances.size, image.combos.size])
        .to eq([2, 2, 1, 3, 4])
      expect(image.combos[0].keys).to eq([0, 0])
    end
  end

  describe '#to_profile' do
    let(:metadata) do
      Cornix::Domain::Metadata.from_h('keyboard' => 'cornix', 'version' => 1, 'uid' => 5,
                                      'file_naming' => { 'layers' => {} },
                                      'extra_keys' => { 'layout_options' => 0 },
                                      'references' => { 'macros' => {} })
    end
    let(:source) do
      Cornix::Domain::Profile.new(
        metadata: metadata, settings: Cornix::Domain::QmkSettings.new(values: { 7 => 200 }), position_map: position_map,
        layers: [build_layer(index: 0, name: 'Base', description: '基本',
                             keys: { key_position(:left, 0, 0) => td_call(4) }),
                 build_layer(index: 1, name: 'Symbols')],
        macros: [build_macro(index: 3, name: 'Copy')],
        tap_dances: [build_tap_dance(index: 4, name: 'Tab Escape')],
        combos: [build_combo(index: 0, name: 'Bracket')]
      )
    end
    let(:image) { mapper.to_image(source) }

    it 'previous がなければ旧 decompile と同じ名前を付ける' do
      profile = mapper.to_profile(image, position_map: position_map)
      expect(profile.layers.map(&:name)).to eq(['Layer 0', 'Layer 1'])
      expect(profile.macros.map(&:name)).to eq(['Macro 3'])
      expect(profile.tap_dances.map(&:name)).to eq(['TapDance 4'])
      expect(profile.combos.map(&:name)).to eq(['Combo 0'])
      expect(profile.metadata.keyboard).to eq('Cornix')
    end

    it 'previous があれば名前・説明・メタデータを引き継ぎ、元の Profile に戻る' do
      expect(mapper.to_profile(image, position_map: position_map, previous: source)).to eq(source)
    end

    it '注記はイメージに出ず、previous があればキーコードが変わっていない場所の注記を引き継ぐ' do
      tab = key_position(:left, 0, 0)
      q = key_position(:left, 0, 1)
      noted = source.with(layers: [build_layer(index: 0, keys: { tab => basic(0x2B), q => basic(0x14) },
                                               notes: { tab => 'インデント', q => 'Q' })])
      expect(mapper.to_image(noted)).to eq(mapper.to_image(noted.with(layers: [noted.layers[0].with(notes: {})])))

      changed = mapper.to_image(noted.with(layers: [build_layer(index: 0, keys: { tab => basic(0x2B), q => basic(0x15) })]))
      profile = mapper.to_profile(changed, position_map: position_map, previous: noted)
      expect(profile.layer(0).notes).to eq(tab => 'インデント')
      expect(mapper.to_profile(changed, position_map: position_map).layer(0).notes).to eq({})
    end

    it 'extra_keys は image の値にし、previous の extra の順を保つ' do
      changed = image.with(meta: image.meta.merge('layout_options' => 3))
      profile = mapper.to_profile(changed, position_map: position_map, previous: source)
      expect(profile.metadata.extra.keys).to eq(%w[file_naming extra_keys references])
      expect(profile.metadata.extra_keys).to eq('layout_options' => 3)
    end

    it 'previous が Profile でなければ InvalidValue' do
      expect { mapper.to_profile(image, position_map: position_map, previous: {}) }.to raise_error(Cornix::InvalidValue)
    end

    it 'position_map が PositionMap でなければ InvalidValue' do
      expect { mapper.to_profile(image, position_map: {}) }.to raise_error(Cornix::InvalidValue)
    end
  end
end
