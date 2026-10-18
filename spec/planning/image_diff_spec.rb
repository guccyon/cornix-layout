# frozen_string_literal: true

require 'spec_helper'
require_relative 'planning_images_context'

RSpec.describe Cornix::Planning::ImageDiff do
  include_context 'planning images'

  def diff(target) = described_class.new(current: current, target: target)

  it '同じイメージなら変更も警告もない' do
    d = diff(current)
    expect(d.changes).to be_empty
    expect(d.warnings).to be_empty
  end

  it '旧 Device::Keyboard と同じ順に変更を列挙する' do
    target = current.with(
      layers: [current.layers[0], [[0, 0x2A, 0], [0, 0, nil]]],
      encoders: [current.encoders[0], [record(0xAA, 0x7F)]],
      tap_dances: [current.tap_dances[0], td(5, 0x5221, 0, 0, 200)],
      combos: [combo([4, 22, 0, 0], 0x7700), current.combos[1]],
      macros: [[], [], [action(:text, 'hi'), action(:tap, 0x021F)], []],
      settings: current.settings.merge(7 => 180)
    )
    changes = diff(target).changes
    expect(changes.map(&:kind)).to eq(%i[set_keycode set_encoder set_tap_dance set_combo replace_macros set_setting])
    expect(changes[0]).to eq(Cornix::Planning::Change::SetKeycode.new(layer: 1, row: 0, col: 1, from: 0, to: 0x2A))
    expect(changes[1]).to have_attributes(layer: 1, index: 0, clockwise: true, from: 0xA9, to: 0x7F)
    expect(changes[4]).to have_attributes(indexes: [2], from: current.macros)
    expect(changes[5]).to have_attributes(qsid: 7, from: 200, to: 180)
    expect(diff(target).warnings).to be_empty
  end

  it 'キーのない位置の値と、目標で nil（-1）の位置は警告して無視する' do
    target = current.with(layers: [[[nil, 0, 0], [0, 0, 0x1B]], current.layers[1]])
    d = diff(target)
    expect(d.changes).to be_empty
    expect(d.warnings).to eq(['レイヤー0 (0,0) が layout.vil で -1 のため無視します',
                              'レイヤー0 (1,2) はキーボード上に存在しない位置のため無視します'])
  end

  it 'マトリクスの外の位置は値があれば警告する' do
    target = current.with(layers: [[[4, 0, 0, 9], [0, 0, nil], [nil, nil, nil]], current.layers[1]])
    expect(diff(target).warnings).to eq(['レイヤー0 (0,3) はキーボード上に存在しない位置のため無視します'])
  end

  it 'レイヤー数が多ければ PlanError、少なければ警告' do
    expect { diff(current.with(layers: current.layers + [current.layers[0]])).changes }
      .to raise_error(Cornix::PlanError, /レイヤー数/)
    expect(diff(current.with(layers: [current.layers[0]])).warnings.first).to include('より少ない')
  end

  it 'エンコーダ数・TD・コンボの枠を超える目標は警告して無視する（中身が空の TD / コンボは警告しない）' do
    target = current.with(
      encoders: [[record(0xAA, 0xA9), record(1, 2)], current.encoders[1], [record(3, 4)]],
      tap_dances: current.tap_dances + [td(0, 0, 0, 0, 200), td(4, 0, 0, 0, 200)],
      combos: current.combos + [combo([0, 0, 0, 0], 0), combo([4, 5, 0, 0], 6)]
    )
    d = diff(target)
    expect(d.changes).to be_empty
    expect(d.warnings).to eq(['レイヤー0 エンコーダ1 はキーボードに存在しないため無視します',
                              'タップダンス3 はキーボードの上限を超えるため無視します',
                              'コンボ3 はキーボードの上限を超えるため無視します'])
  end

  it 'マクロは足りない分を空で埋め、バイト列で区別できない違いは差分にしない' do
    with_macro = current.with(macros: [[action(:tap, 4, 5)], [], [], []])
    split = current.with(macros: [[action(:tap, 4), action(:tap, 5), action(:text, '')]])
    expect(described_class.new(current: with_macro, target: split).changes).to be_empty
    change = diff(split).changes.first
    expect(change.indexes).to eq([0])
    expect(change.to.size).to eq(4)
  end

  it 'マクロ数が上限を超えて中身があれば PlanError（空なら無視）' do
    expect(diff(current.with(macros: current.macros + [[]])).changes).to be_empty
    expect { diff(current.with(macros: current.macros + [[action(:tap, 4)]])).changes }
      .to raise_error(Cornix::PlanError, /マクロ数/)
  end

  it 'デバイスが扱わない設定と、未対応の .vil 項目は警告する' do
    target = current.with(settings: { 2 => 50, 99 => 1 },
                          meta: { 'layout_options' => 1, 'key_override' => [1], 'alt_repeat_key' => [] })
    expect(diff(target).warnings).to eq(['設定 99 はこのキーボードでは扱えないため無視します',
                                         'layout_options はキーボードへ反映しません',
                                         'key_override はこのキーボードが対応していないため反映しません'])
  end
end
