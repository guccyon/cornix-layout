# frozen_string_literal: true

require 'spec_helper'
require_relative 'fake_rmk_device'
require_relative '../planning/planning_images_context'

RSpec.describe Cornix::Device::Writer do
  include_context 'planning images'

  let(:device) { FakeRmkDevice.new }
  let(:session) { Cornix::Device::Session.new(device, definition: FakeRmkDevice::DEFINITION) }
  let(:reader) { Cornix::Device::Reader.new(session) }
  let(:planner) { Cornix::Device::Planner.new(session) }
  let(:current) { reader.read }
  subject(:writer) { described_class.new(session) }

  # 旧 spec/device/keyboard_spec.rb の「変更がある場合」と同じ目標
  let(:target) do
    layers = current.layers.map { |rows| rows.map(&:dup) }
    layers[1][0][1] = 0x2A # KC_BSPC
    current.with(
      layers: layers,
      encoders: [current.encoders[0], [record(0xAA, 0x7F)]], # KC_MUTE
      tap_dances: [current.tap_dances[0], td(0x05, 0x5221, 0, 0, 200)], # KC_B, MO(1)
      combos: [combo([0x04, 0x16, 0, 0], 0x7700), current.combos[1]], # KC_A + KC_S → M0
      macros: [[], [], [action(:text, 'hi'), action(:tap, 0x021F)], []],
      settings: current.settings.merge(7 => 180)
    )
  end

  it 'read → diff → plan → write → 読み直して検証する' do
    plan = planner.plan(current: current, target: target)
    expect(plan.changes.map(&:kind)).to eq(%i[set_keycode set_encoder set_tap_dance set_combo replace_macros set_setting])
    expect(device.writes).to be_empty

    backups = []
    result = writer.apply(plan, expected_token: plan.token, backup: -> { backups << current; 'tmp/backup.vil' })
    expect(result).to be_success
    expect(result.backup).to eq('tmp/backup.vil')
    expect(result.applied.size).to eq(6)
    expect(result.remaining).to be_empty
    expect(backups.size).to eq(1)

    expect(device.sent.count { |m| m[0] == 0x05 }).to eq(1)
    expect(device.keymap[1][0][1]).to eq(0x2A)
    expect(device.encoders[1][0]).to eq([0xAA, 0x7F])
    expect(device.tap_dances[1]).to eq([0x05, 0x5221, 0, 0, 200])
    expect(device.combos[0]).to eq([0x04, 0x16, 0, 0, 0x7700])
    expect(device.settings[7]).to eq(180)
    expect(planner.plan(current: reader.read, target: target)).to be_empty
  end

  it 'バックアップは最初の書き込みの前に取る' do
    plan = planner.plan(current: current, target: target)
    writes_at_backup = nil
    writer.apply(plan, backup: -> { writes_at_backup = device.writes.size })
    expect(writes_at_backup).to eq(0)
  end

  it '変更がなければ何も書かず、バックアップも取らない' do
    called = false
    result = writer.apply(planner.plan(current: current, target: current), backup: -> { called = true })
    expect(result).to eq(Cornix::Device::ApplyResult.new)
    expect(called).to be(false)
    expect(device.writes).to be_empty
  end

  it '確認時から差分が変わっていたら書き込まない' do
    plan = planner.plan(current: current, target: target)
    expect { writer.apply(plan, expected_token: 'stale') }.to raise_error(Cornix::PlanError, /変わって/)
    expect(device.writes).to be_empty
  end

  it 'token は現在の値ではなく書き込む内容で決まる（確認後に同じ目標へ計画し直すと一致する）' do
    token = planner.plan(current: current, target: target).token
    device.keymap[1][0][1] = 0x05
    replanned = planner.plan(current: reader.read, target: target)
    expect(replanned.token).to eq(token)
    device.keymap[1][0][0] = 0x05
    expect(planner.plan(current: reader.read, target: target).token).not_to eq(token)
  end

  it '手で作った Plan でも boot 系キーコードは書き込まない' do
    change = Cornix::Planning::Change::SetKeycode.new(layer: 0, row: 0, col: 1, from: 0, to: 0x7C00)
    called = false
    plan = Cornix::Planning::Plan.new(changes: [change])
    expect { writer.apply(plan, backup: -> { called = true }) }.to raise_error(Cornix::PlanError, /QK_BOOT/)
    expect(called).to be(false)
    expect(device.writes).to be_empty
  end

  it '書き込みに失敗したら止めて、書き込み済みの件数とバックアップを示す' do
    changes = [
      Cornix::Planning::Change::SetKeycode.new(layer: 0, row: 0, col: 1, from: 0, to: 0x05),
      Cornix::Planning::Change::SetKeycode.new(layer: 0, row: 1, col: 3, from: 0, to: 0x06), # マトリクスの外
      Cornix::Planning::Change::SetKeycode.new(layer: 1, row: 0, col: 0, from: 0, to: 0x07)
    ]
    plan = Cornix::Planning::Plan.new(changes: changes)
    expect { writer.apply(plan, backup: -> { 'b.vil' }) }
      .to raise_error(Cornix::DeviceError, /レイヤー0 \(1,3\) の書き込みに失敗しました（1\/3 件書き込み済み）.*反映前のバックアップ: b\.vil/)
    expect(device.keymap[0][0][1]).to eq(0x05)
    expect(device.keymap[1][0][0]).to eq(0)
  end

  it '読み直して目標と一致しない変更を remaining に返す' do
    plan = planner.plan(current: current, target: target)
    allow(device).to receive(:transfer).and_wrap_original do |original, bytes|
      bytes[0] == 0x0B || (bytes[0] == 0xFE && bytes[1] == 0x0B) ? bytes + [0] * (32 - bytes.size) : original.call(bytes)
    end
    result = writer.apply(plan)
    expect(result).not_to be_success
    expect(result.remaining.map(&:kind)).to eq([:set_setting])
  end
end
