# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Cornix::Domain::Diagnostic do
  it 'error / warning を作る' do
    e = described_class.error('layers[0].left_hand.row0.tab', 'マクロ M5 が定義されていません')
    expect(e).to be_error
    expect(e).not_to be_warning
    expect(e.to_s).to eq('[error] layers[0].left_hand.row0.tab: マクロ M5 が定義されていません')
    w = described_class.warning('layers', 'レイヤー 3 がありません')
    expect(w).to be_warning
    expect(w.severity).to eq(:warning)
  end

  it 'path と message は freeze した文字列' do
    d = described_class.new(severity: :error, path: :layers, message: 'x')
    expect(d.path).to eq('layers')
    expect(d.path).to be_frozen
    expect(d.message).to be_frozen
  end

  it 'severity は error / warning' do
    expect { described_class.new(severity: :info, path: 'a', message: 'b') }.to raise_error(Cornix::InvalidValue, /severity/)
  end
end
