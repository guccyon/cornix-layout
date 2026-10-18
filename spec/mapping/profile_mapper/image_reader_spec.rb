# frozen_string_literal: true

require 'spec_helper'
require_relative '../../domain/support/domain_factories'

RSpec.describe Cornix::Mapping::ProfileMapper::ImageReader do
  include DomainFactories

  let(:mapper) { Cornix::Mapping::ProfileMapper.new }
  let(:img) { Cornix::Image }
  let(:k) { Cornix::Domain::Keycode }

  def grid = Array.new(8) { Array.new(7) }
  def no_encoders = [img::EncoderRecord.new(ccw: nil, cw: nil)] * 2
  def td(*keys, term) = img::TapDanceRecord.new(on_tap: keys[0], on_hold: keys[1], on_double_tap: keys[2],
                                                on_tap_hold: keys[3], tapping_term: term)

  let(:layer0) do
    g = grid
    g[0][0] = 0x2B
    g[4][5] = 0x5223
    g[2][6] = 0xA8
    g[5][6] = 0
    g
  end
  let(:layers) { [layer0] + Array.new(9) { grid } }
  let(:encoders) do
    [[img::EncoderRecord.new(ccw: 0xAA, cw: 0xA9), img::EncoderRecord.new(ccw: 0x52, cw: 0x51)]] +
      Array.new(9) { no_encoders }
  end
  let(:macros) { [[], [img::MacroAction.new(kind: :tap, keys: [0x06]), img::MacroAction.new(kind: :delay, value: 50),
                       img::MacroAction.new(kind: :text, value: 'hi')]] + Array.new(30) { [] } }
  let(:tap_dances) do
    [td(0x04, 0x5221, 0, 0, 200), td(0, 0, 0, 0, 250), td(0, 0, 0, 0, 180)] + Array.new(29) { td(0, 0, 0, 0, 250) }
  end
  let(:combos) do
    [img::ComboRecord.new(keys: [0x0E, 0x0F, 0, 0], output: 0x7705),
     img::ComboRecord.new(keys: [0, 0, 0, 0], output: 0),
     img::ComboRecord.new(keys: [0x0E, 0, 0x0F, 0], output: 0x04),
     img::ComboRecord.new(keys: [0, 0, 0, 0], output: 0x05)] + Array.new(28) { img::ComboRecord.new(keys: [0] * 4, output: 0) }
  end
  let(:meta) do
    { 'version' => 1, 'uid' => 99, 'vial_protocol' => 6, 'via_protocol' => 9,
      'layout_options' => 0, 'alt_repeat_key' => [], 'key_override' => [] }
  end
  let(:image) do
    img::DeviceImage.new(layers: layers, encoders: encoders, macros: macros, tap_dances: tap_dances, combos: combos,
                         settings: { 7 => 180, 2 => 50 }, meta: meta)
  end
  let(:profile) { mapper.to_profile(image, position_map: position_map) }

  describe 'レイヤー' do
    it 'すべて nil のレイヤーは読まない' do
      expect(profile.layers.map(&:index)).to eq([0])
    end

    it 'キーの位置の値だけを読み、nil の位置は割り当てなし' do
      expect(profile.layers[0].keys).to eq(key_position(:left, 0, 0) => basic(0x2B),
                                           key_position(:right, 0, 0) => mo(3))
    end

    it 'エンコーダのプッシュをマトリクスから、回転を encoders から読む' do
      expect(profile.layers[0].encoders).to eq(
        left: encoder_binding(push: basic(0xA8), ccw: basic(0xAA), cw: basic(0xA9)),
        right: encoder_binding(push: k::NO_KEY, ccw: basic(0x52), cw: basic(0x51))
      )
    end

    it 'キーのあるレイヤーのエンコーダの nil は KC_NO として読む' do
      g = grid
      g[0][0] = 0x04
      image2 = image.with(layers: [g], encoders: [no_encoders])
      expect(mapper.to_profile(image2, position_map: position_map).layers[0].encoders)
        .to eq(left: encoder_binding, right: encoder_binding)
    end

    it '名前は "Layer N"、説明は nil' do
      expect(profile.layers[0]).to have_attributes(name: 'Layer 0', description: nil)
    end

    it '解釈できない値は Raw のまま持ち、to_image で同じ値に戻る' do
      layer0[0][0] = 0x7E40
      expect(profile.layers[0].key(key_position(:left, 0, 0))).to eq(k::Raw.new(code: 0x7E40))
      expect(mapper.to_image(profile).layers[0][0][0]).to eq(0x7E40)
    end
  end

  describe 'マクロ' do
    it '空の枠は読まず、動作を MacroStep にする' do
      s = Cornix::Domain::MacroStep
      expect(profile.macros.map(&:index)).to eq([1])
      expect(profile.macros[0]).to have_attributes(name: 'Macro 1',
                                                   steps: [s::Tap.new(keys: [basic(0x06)]), s::Delay.new(ms: 50),
                                                           s::Text.new(content: 'hi')])
    end
  end

  describe 'タップダンス' do
    it 'KC_NO × 4 で既定のタッピング時間の枠は読まない' do
      expect(profile.tap_dances.map(&:index)).to eq([0, 2])
      expect(profile.tap_dances[0]).to have_attributes(name: 'TapDance 0', on_tap: basic(0x04), on_hold: mo(1),
                                                       on_double_tap: k::NO_KEY, tapping_term: 200)
    end

    it 'KC_NO × 4 でもタッピング時間が既定でなければ読む（旧 decompile は落としていた）' do
      expect(profile.tap_dances[1]).to have_attributes(index: 2, tapping_term: 180)
    end
  end

  describe 'コンボ' do
    it 'すべて KC_NO の枠は読まず、トリガーの末尾の KC_NO を落とす' do
      expect(profile.combos.map(&:index)).to eq([0, 2, 3])
      expect(profile.combos[0]).to have_attributes(name: 'Combo 0', trigger_keys: [basic(0x0E), basic(0x0F)],
                                                   output_key: macro_call(5))
    end

    it '途中の KC_NO は残す（to_image で同じ値に戻る）' do
      expect(profile.combos[1].trigger_keys).to eq([basic(0x0E), k::NO_KEY, basic(0x0F)])
    end

    it 'トリガーがすべて KC_NO で出力だけある枠はトリガー [KC_NO] として持つ' do
      expect(profile.combos[2].trigger_keys).to eq([k::NO_KEY])
    end
  end

  describe '設定とメタデータ' do
    it 'settings を QmkSettings にする' do
      expect(profile.settings.values).to eq(2 => 50, 7 => 180)
    end

    it 'meta の既知の項目は Metadata の項目、それ以外は extra_keys。keyboard は "Cornix"（旧 decompile）' do
      expect(profile.metadata.to_h).to eq(
        'keyboard' => 'Cornix', 'version' => 1, 'uid' => 99, 'vial_protocol' => 6, 'via_protocol' => 9,
        'extra_keys' => { 'layout_options' => 0, 'alt_repeat_key' => [], 'key_override' => [] }
      )
    end

    it 'extra_keys にする項目がなければ extra_keys を持たない' do
      image2 = image.with(meta: { 'version' => 1 })
      expect(mapper.to_profile(image2, position_map: position_map).metadata.extra).to eq({})
    end
  end

  it 'to_image で元のイメージに戻る' do
    expect(mapper.to_image(profile)).to eq(image)
  end

  it 'image が DeviceImage でなければ InvalidValue' do
    expect { mapper.to_profile({}, position_map: position_map) }.to raise_error(Cornix::InvalidValue)
  end
end
