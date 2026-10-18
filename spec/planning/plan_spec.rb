# frozen_string_literal: true

require 'spec_helper'
require_relative 'planning_images_context'

RSpec.describe Cornix::Planning::Plan do
  include_context 'planning images'

  let(:key) { Cornix::Planning::Change::SetKeycode.new(layer: 0, row: 0, col: 1, from: 0, to: 0x2A) }
  let(:macros) do
    Cornix::Planning::Change::ReplaceMacros.new(indexes: [1], from: [[], []], to: [[], [action(:tap, 0x7C00), action(:text, 'a')]])
  end

  it '変更がなければ empty?' do
    expect(described_class.new(changes: [])).to be_empty
    expect(described_class.new(changes: [key], warnings: ['w'])).not_to be_empty
  end

  it 'Change 以外は受け付けない' do
    expect { described_class.new(changes: [{ kind: :key }]) }.to raise_error(ArgumentError)
  end

  it 'token は書き込む内容（場所と to）で決まり、from には依存しない' do
    token = described_class.new(changes: [key]).token
    expect(token).to match(/\A\h{16}\z/)
    expect(described_class.new(changes: [key.with(from: 0x99)]).token).to eq(token)
    expect(described_class.new(changes: [key.with(to: 0x2B)]).token).not_to eq(token)
    expect(described_class.new(changes: [key.with(col: 2)]).token).not_to eq(token)
    expect(described_class.new(changes: [key], warnings: ['x']).token).to eq(token)
  end

  it 'Change は表示・ハッシュ用の Hash と書き込むキーコードの一覧を返す' do
    expect(key.to_h).to eq('kind' => 'set_keycode', 'layer' => 0, 'row' => 0, 'col' => 1, 'from' => 0, 'to' => 0x2A)
    expect(macros.keycodes).to eq([0x7C00])
    expect(macros.token_payload['to'][1]).to eq([{ 'kind' => 'tap', 'keys' => [0x7C00], 'value' => nil },
                                                 { 'kind' => 'text', 'keys' => [], 'value' => 'a' }])
    td = Cornix::Planning::Change::SetTapDance.new(index: 0, from: td(0, 0, 0, 0, 200), to: td(1, 2, 3, 4, 200))
    expect(td.keycodes).to eq([1, 2, 3, 4])
    cb = Cornix::Planning::Change::SetCombo.new(index: 0, from: combo([0, 0, 0, 0], 0), to: combo([4, 5, 0, 0], 6))
    expect(cb.keycodes).to eq([4, 5, 0, 0, 6])
  end
end
