# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Cornix::Device::ChangePolicy do
  subject(:policy) { described_class.new }

  let(:change) { Cornix::Planning::Change::SetKeycode.new(layer: 0, row: 0, col: 1, from: 0, to: 0x04) }

  it '書き込んでよいキーコードなら警告なし' do
    expect(policy.check!([change])).to eq([])
  end

  it 'KeycodeCatalog#dangerous? に当たる値（QK_BOOT など）は PlanError' do
    expect { policy.check!([change.with(to: 0x7C00)]) }.to raise_error(Cornix::PlanError, /レイヤー0 \(0,1\): QK_BOOT は安全のため/)
    expect { policy.check!([change.with(to: 0x7C01)]) }.to raise_error(Cornix::PlanError, /QK_REBOOT/)
  end

  it 'マクロの中の拒否する値も検査する' do
    macros = Cornix::Planning::Change::ReplaceMacros.new(
      indexes: [0], from: [[]], to: [[Cornix::Image::MacroAction.new(kind: :tap, keys: [0x7C00])]]
    )
    expect { policy.check!([macros]) }.to raise_error(Cornix::PlanError, /マクロ M0/)
  end

  it 'RMK 0.8 が解釈できない値は警告する' do
    expect(policy.check!([change.with(to: 0x7C20)]).first).to match(/レイヤー0 \(0,1\): .* はファームウェアが未対応/)
  end

  it '拒否するときは PlanRejected で、keycodes に拒否したキーコードの表記を重ならずに入れる' do
    changes = [change.with(to: 0x7C00), change.with(col: 2, to: 0x7C01), change.with(col: 3, to: 0x7C00)]
    expect { policy.check!(changes) }.to raise_error(Cornix::PlanRejected) { |e| expect(e.keycodes).to eq(%w[QK_BOOT QK_REBOOT]) }
  end
end
