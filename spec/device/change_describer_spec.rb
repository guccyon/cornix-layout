# frozen_string_literal: true

require 'spec_helper'
require_relative '../planning/planning_images_context'

RSpec.describe Cornix::Device::ChangeDescriber do
  include_context 'planning images'
  subject(:describer) { described_class.new }

  c = Cornix::Planning::Change

  it '旧 Device::Keyboard#describe と同じ場所の表記にする' do
    expect(describer.describe(c::SetKeycode.new(layer: 1, row: 0, col: 1, from: 0, to: 0x2A))).to eq('レイヤー1 (0,1)')
    expect(describer.describe(c::SetEncoder.new(layer: 1, index: 0, clockwise: true, from: 0, to: 0))).to eq('レイヤー1 エンコーダ0 時計回り')
    expect(describer.describe(c::SetEncoder.new(layer: 0, index: 1, clockwise: false, from: 0, to: 0))).to eq('レイヤー0 エンコーダ1 反時計回り')
    expect(describer.describe(c::SetTapDance.new(index: 3, from: nil, to: nil))).to eq('タップダンス3')
    expect(describer.describe(c::SetCombo.new(index: 2, from: nil, to: nil))).to eq('コンボ2')
    expect(describer.describe(c::ReplaceMacros.new(indexes: [0, 2], from: [], to: []))).to eq('マクロ M0, M2')
    expect(describer.describe(c::SetSetting.new(qsid: 7, from: 200, to: 180))).to eq('設定 7')
  end

  it '変更内容を「場所: 現在 → 目標」にする' do
    expect(describer.format_change(c::SetKeycode.new(layer: 1, row: 0, col: 1, from: 0, to: 0x2A)))
      .to eq('レイヤー1 (0,1): KC_NO → KC_BSPACE')
    expect(describer.format_change(c::SetTapDance.new(index: 0, from: td(0, 0, 0, 0, 250), to: td(5, 0, 0, 0, 200))))
      .to eq('タップダンス0: [KC_NO, KC_NO, KC_NO, KC_NO, 250ms] → [KC_B, KC_NO, KC_NO, KC_NO, 200ms]')
    expect(describer.format_change(c::SetCombo.new(index: 0, from: combo([0, 0, 0, 0], 0), to: combo([4, 22, 0, 0], 0x29))))
      .to eq('コンボ0: [KC_NO + KC_NO + KC_NO + KC_NO → KC_NO] → [KC_A + KC_S + KC_NO + KC_NO → KC_ESCAPE]')
    macros = c::ReplaceMacros.new(indexes: [1], from: [[], []], to: [[], [action(:text, 'hi'), action(:tap, 4)]])
    expect(describer.format_change(macros)).to eq('マクロ M1: [] → [["text","hi"],["tap","KC_A"]]')
  end

  it 'キーコードの表記は差し替えられる' do
    d = described_class.new(formatter: ->(code) { "K#{code}" })
    expect(d.format_change(c::SetKeycode.new(layer: 0, row: 0, col: 0, from: 1, to: 2))).to eq('レイヤー0 (0,0): K1 → K2')
  end
end
