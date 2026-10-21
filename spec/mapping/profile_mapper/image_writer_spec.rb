# frozen_string_literal: true

require 'spec_helper'
require_relative '../../domain/support/domain_factories'

RSpec.describe Cornix::Mapping::ProfileMapper::ImageWriter do
  include DomainFactories

  let(:mapper) { Cornix::Mapping::ProfileMapper.new }
  let(:img) { Cornix::Image }
  let(:image) { mapper.to_image(profile) }
  let(:profile) { build_profile }

  def mods(*m) = Cornix::Domain::ModifierSet.new(side: :left, mods: m)

  describe 'レイヤー' do
    let(:keys) { { key_position(:left, 0, 0) => basic(0x2B), key_position(:right, 0, 0) => mo(3) } }
    let(:encoders) do
      { left: encoder_binding(push: basic(0xA8), ccw: basic(0xAA), cw: basic(0xA9)),
        right: encoder_binding(push: td_call(3), ccw: basic(0x52), cw: basic(0x51)) }
    end
    let(:profile) { build_profile(layers: [build_layer(index: 0, keys: keys, encoders: encoders)]) }

    it 'capabilities.layers 枚の 8 × 7 のマトリクスを作る' do
      expect(image.layers.size).to eq(10)
      expect(image.layers).to all(satisfy { |g| g.size == 8 && g.all? { |r| r.size == 7 } })
    end

    it 'キーを PositionMap#matrix の位置に置く（右手は反転・行 +4）' do
      expect(image.layers[0][0][0]).to eq(0x2B)
      expect(image.layers[0][4][5]).to eq(0x5223)
    end

    it 'position_map にある位置で割り当てのないものは KC_NO（0）、キーのない位置は nil（.vil の -1）' do
      expect(image.layers[0][0][1]).to eq(0)
      expect(image.layers[0][7][0]).to eq(0)
      expect(image.layers[0][0][6]).to be_nil
      expect(image.layers[0][3][6]).to be_nil
      # キーの位置 48 とエンコーダのプッシュ 2。nil はプッシュ以外の col 6 の 6 か所
      expect(image.layers[0].flatten.compact.size).to eq(50)
      expect(image.layers[0].flatten.count(0)).to eq(46)
      expect(image.layers[0].map { |row| row[6] }.each_with_index.reject { |_, r| [2, 5].include?(r) }.map(&:first))
        .to all(be_nil)
    end

    it '割り当てのないレイヤーでも position_map にある位置は KC_NO、エンコーダは KC_NO' do
      empty = build_layer(index: 0, encoders: { left: encoder_binding, right: encoder_binding })
      result = mapper.to_image(build_profile(layers: [empty]))
      expect(result.layers[0].flatten.compact).to all(eq(0))
      expect(result.layers[0].flatten.compact.size).to eq(50)
      expect(result.encoders[0]).to eq([img::EncoderRecord.new(ccw: 0, cw: 0)] * 2)
    end

    it 'エンコーダのプッシュはマトリクス、回転は encoders に置く' do
      expect(image.layers[0][2][6]).to eq(0xA8)
      expect(image.layers[0][5][6]).to eq(0x5703)
      expect(image.encoders[0]).to eq([img::EncoderRecord.new(ccw: 0xAA, cw: 0xA9),
                                       img::EncoderRecord.new(ccw: 0x52, cw: 0x51)])
    end

    it '定義のないレイヤーは割り当てのないレイヤーと同じ（position_map にある位置とエンコーダは KC_NO、キーのない位置は nil）' do
      empty = build_layer(index: 1, encoders: { left: encoder_binding, right: encoder_binding })
      with_empty = mapper.to_image(build_profile(layers: [build_layer(index: 0), empty]))
      expect(image.layers[1]).to eq(with_empty.layers[1])
      expect(image.layers[1].flatten.compact).to all(eq(0))
      expect(image.layers[1].flatten.compact.size).to eq(50)
      expect(image.encoders[1]).to eq([img::EncoderRecord.new(ccw: 0, cw: 0)] * 2)
    end

    it 'レイヤーは配列の順ではなく index の位置に置く' do
      profile = build_profile(layers: [build_layer(index: 2, keys: keys), build_layer(index: 0)])
      result = mapper.to_image(profile)
      expect(result.layers[2][0][0]).to eq(0x2B)
      expect(result.layers[0][0][0]).to eq(0)
      expect(result.layers[1].flatten.compact).to all(eq(0))
    end

    it 'レイヤーの番号が枠を超えると InvalidValue' do
      expect { mapper.to_image(build_profile(layers: [build_layer(index: 10)])) }
        .to raise_error(Cornix::InvalidValue, /レイヤーの番号/)
    end

    it '16bit 値にできないキーコードは UnknownKeycode' do
      profile = build_profile(layers: [build_layer(keys: { key_position(:left, 0, 0) => basic(0xF0) })])
      expect { mapper.to_image(profile) }.to raise_error(Cornix::UnknownKeycode)
    end

    it 'Raw はその値のまま書く' do
      raw = Cornix::Domain::Keycode::Raw.new(code: 0x7E40)
      profile = build_profile(layers: [build_layer(keys: { key_position(:left, 0, 0) => raw })])
      expect(mapper.to_image(profile).layers[0][0][0]).to eq(0x7E40)
    end
  end

  describe 'マクロ' do
    let(:steps) do
      s = Cornix::Domain::MacroStep
      [s::Down.new(keys: [basic(0xE3)]), s::Tap.new(keys: [basic(0x06), basic(0x07)]), s::Up.new(keys: [basic(0xE3)]),
       s::Delay.new(ms: 100), s::Text.new(content: 'hello')]
    end
    let(:profile) { build_profile(macros: [build_macro(index: 2, steps: steps)]) }

    it '32 個の枠に index の位置で置き、未使用は []' do
      expect(image.macros.size).to eq(32)
      expect(image.macros[2]).to eq([
                                      img::MacroAction.new(kind: :down, keys: [0xE3]),
                                      img::MacroAction.new(kind: :tap, keys: [0x06, 0x07]),
                                      img::MacroAction.new(kind: :up, keys: [0xE3]),
                                      img::MacroAction.new(kind: :delay, value: 100),
                                      img::MacroAction.new(kind: :text, value: 'hello')
                                    ])
      expect(image.macros.values_at(0, 1, 3, 31)).to all(eq([]))
    end
  end

  describe 'タップダンス' do
    let(:profile) { build_profile(tap_dances: [build_tap_dance(index: 4, on_hold: mo(1), tapping_term: 200)]) }

    it '32 個の枠に置き、未使用は KC_NO × 4 と 250（旧 TapDanceCollection と同じ）' do
      expect(image.tap_dances.size).to eq(32)
      expect(image.tap_dances[4]).to eq(img::TapDanceRecord.new(on_tap: 0x04, on_hold: 0x5221, on_double_tap: 0,
                                                                on_tap_hold: 0, tapping_term: 200))
      expect(image.tap_dances[0]).to eq(img::TapDanceRecord.new(on_tap: 0, on_hold: 0, on_double_tap: 0,
                                                                on_tap_hold: 0, tapping_term: 250))
      expect(Cornix::Mapping::ProfileMapper::DEFAULT_TAPPING_TERM).to eq(250)
    end
  end

  describe 'コンボ' do
    let(:profile) { build_profile(combos: [build_combo(index: 1, output_key: macro_call(5))]) }

    it '32 個の枠に置き、トリガーを 4 個まで 0 で埋める。未使用はすべて 0' do
      expect(image.combos.size).to eq(32)
      expect(image.combos[1]).to eq(img::ComboRecord.new(keys: [0x0E, 0x0F, 0, 0], output: 0x7705))
      expect(image.combos[0]).to eq(img::ComboRecord.new(keys: [0, 0, 0, 0], output: 0))
    end

    it 'トリガーが combo_keys を超えると InvalidValue' do
      combo = build_combo(trigger_keys: [basic(4), basic(5), basic(6), basic(7), basic(8)])
      expect { mapper.to_image(build_profile(combos: [combo])) }.to raise_error(Cornix::InvalidValue, /4 個まで/)
    end
  end

  describe '設定とメタデータ' do
    let(:metadata) do
      Cornix::Domain::Metadata.from_h(
        'keyboard' => 'cornix', 'version' => 1, 'uid' => 123, 'vial_protocol' => 6, 'via_protocol' => 9,
        'extra_keys' => { 'layout_options' => 0, 'alt_repeat_key' => [], 'key_override' => [] },
        'file_naming' => { 'layers' => {} }
      )
    end
    let(:profile) do
      Cornix::Domain::Profile.new(metadata: metadata, settings: Cornix::Domain::QmkSettings.new(values: { 7 => 180, 2 => 50 }),
                                  position_map: position_map, layers: [build_layer])
    end

    it 'settings は QSID の昇順' do
      expect(image.settings.to_a).to eq([[2, 50], [7, 180]])
    end

    it 'meta は version / uid / vial_protocol / via_protocol と extra_keys（旧 Metadata#to_qmk + extra_keys の順）' do
      expect(image.meta.to_a).to eq([['version', 1], ['uid', 123], ['vial_protocol', 6], ['via_protocol', 9],
                                     ['layout_options', 0], ['alt_repeat_key', []], ['key_override', []]])
    end

    it 'uid などがなくても nil で書き、vendor_product_id などはあるときだけ書く' do
      metadata = Cornix::Domain::Metadata.new(keyboard: 'cornix', version: 1, vendor_product_id: '0x1234')
      profile = Cornix::Domain::Profile.new(metadata: metadata, settings: Cornix::Domain::QmkSettings::EMPTY,
                                            position_map: position_map, layers: [])
      expect(mapper.to_image(profile).meta).to eq('version' => 1, 'uid' => nil, 'vial_protocol' => nil,
                                                  'via_protocol' => nil, 'vendor_product_id' => '0x1234')
    end
  end
end
