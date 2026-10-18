# frozen_string_literal: true

require 'spec_helper'
require_relative 'fake_rmk_device'
require_relative '../planning/planning_images_context'

RSpec.describe Cornix::Device::Planner do
  include_context 'planning images'

  let(:device) { FakeRmkDevice.new }
  let(:session) { Cornix::Device::Session.new(device, definition: FakeRmkDevice::DEFINITION) }
  let(:current) { Cornix::Device::Reader.new(session).read }
  subject(:planner) { described_class.new(session) }

  def with_key(image, layer, row, col, code)
    layers = image.layers.map { |rows| rows.map(&:dup) }
    layers[layer][row][col] = code
    image.with(layers: layers)
  end

  it '差分がなければ空の Plan' do
    plan = planner.plan(current: current, target: current)
    expect(plan).to be_empty
    expect(plan.warnings).to be_empty
  end

  it 'ImageDiff の変更と警告を Plan にする' do
    target = with_key(with_key(current, 1, 0, 1, 0x2A), 0, 1, 2, 0x1B)
    plan = planner.plan(current: current, target: target)
    expect(plan.changes).to eq([Cornix::Planning::Change::SetKeycode.new(layer: 1, row: 0, col: 1, from: 0, to: 0x2A)])
    expect(plan.warnings).to eq(['レイヤー0 (1,2) はキーボード上に存在しない位置のため無視します'])
  end

  it 'boot 系キーコードを含む差分は PlanError（何も書かない）' do
    expect { planner.plan(current: current, target: with_key(current, 0, 0, 1, 0x7C00)) }
      .to raise_error(Cornix::PlanError, /QK_BOOT/)
    expect(device.writes).to be_empty
  end

  it 'ファームウェアが解釈できない値は警告する' do
    plan = planner.plan(current: current, target: with_key(current, 0, 0, 1, 0x7C20))
    expect(plan.warnings.join).to include('ファームウェアが未対応')
  end

  it 'マクロがバッファに収まらなければ PlanError' do
    target = current.with(macros: [[action(:text, 'x' * 100)], [], [], []])
    expect { planner.plan(current: current, target: target) }.to raise_error(Cornix::PlanError, /収まりません/)
  end

  it 'マクロをバイト列にできなければ PlanError' do
    target = current.with(macros: [[action(:text, "a\x01")], [], [], []])
    expect { planner.plan(current: current, target: target) }.to raise_error(Cornix::PlanError, /マクロ: /)
  end
end
