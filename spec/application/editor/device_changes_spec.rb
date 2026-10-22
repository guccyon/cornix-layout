# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe Cornix::Application::Editor::DeviceChanges do
  around do |example|
    Dir.mktmpdir { |dir| (@root = dir) && example.run }
  end

  # プロファイルなし（位置の表は設定ディレクトリにないのでテンプレートから読む）
  let(:env) { Cornix::Application::Environment.new(root: @root) }
  let(:changes) { described_class.new(env) }

  def key(row, col, layer: 0) = Cornix::Planning::Change::SetKeycode.new(layer: layer, row: row, col: col, from: 0x04, to: 0x05)

  it 'キーは論理位置と記号に直す（右手の列は反転）' do
    left, right = changes.call([key(1, 2), key(5, 0)])
    expect(left).to include(kind: 'key', layer: 0, key: { hand: 'left', row: 1, col: 2 }, device: 'KC_A', profile: 'KC_B',
                            text: 'レイヤー0 (1,2): KC_A → KC_B')
    expect(right).to include(kind: 'key', key: { hand: 'right', row: 1, col: 5 })
    expect(left[:position]).to be_a(String)
  end

  it 'エンコーダのプッシュの位置は kind: encoder、どちらでもない位置は kind: other' do
    push, other = changes.call([key(5, 6, layer: 2), key(0, 6)])
    expect(push).to include(kind: 'encoder', layer: 2, encoder: { side: 'right', direction: 'push' })
    expect(other).to include(kind: 'other', layer: 0, text: 'レイヤー0 (0,6): KC_A → KC_B')
    expect(other).not_to include(:key, :position)
  end

  it 'エンコーダは 0 が左、1 が右。ほかの番号は other' do
    encoder = ->(index, clockwise) { Cornix::Planning::Change::SetEncoder.new(layer: 1, index: index, clockwise: clockwise, from: 0, to: 0x04) }
    left, right, other = changes.call([encoder.call(0, true), encoder.call(1, false), encoder.call(2, true)])
    expect(left).to include(kind: 'encoder', encoder: { side: 'left', direction: 'cw' })
    expect(right).to include(kind: 'encoder', encoder: { side: 'right', direction: 'ccw' })
    expect(other).to include(kind: 'other', layer: 1)
  end

  it 'マクロは変わる番号ごとに 1 件。プロファイルがなければ name を省く' do
    tap = ->(code) { [Cornix::Image::MacroAction.new(kind: :tap, keys: [code])] }
    change = Cornix::Planning::Change::ReplaceMacros.new(indexes: [0, 2], from: [[], [], tap.call(0x04)], to: [tap.call(0x05), [], []])
    first, second = changes.call([change])
    expect(first).to eq(kind: 'macro', index: 0, device: '[]', profile: '[["tap","KC_B"]]', text: 'マクロ M0: [] → [["tap","KC_B"]]')
    expect(second).to include(kind: 'macro', index: 2, device: '[["tap","KC_A"]]', profile: '[]')
  end

  it '設定は name に設定の名前' do
    setting = Cornix::Planning::Change::SetSetting.new(qsid: 7, from: 200, to: 180)
    expect(changes.call([setting]).first).to eq(kind: 'setting', name: 'tapping_term', device: '200', profile: '180',
                                                text: '設定 7: 200 → 180')
  end
end
