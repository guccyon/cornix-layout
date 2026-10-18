# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require_relative 'fake_rmk_device'

# 新しい Reader / Planner / Writer が旧 Device::Keyboard と同じ差分・警告・書き込みになることを確かめる
RSpec.describe 'Device::Reader / Planner / Writer と旧 Device::Keyboard の一致' do
  let(:old_device) { FakeRmkDevice.new }
  let(:new_device) { FakeRmkDevice.new }
  let(:keyboard) do
    protocol = Cornix::Device::Protocol.new(old_device)
    allow(protocol).to receive(:definition).and_return(FakeRmkDevice::DEFINITION)
    Cornix::Device::Keyboard.new(protocol)
  end
  let(:kc) { keyboard.keycodes }
  let(:session) { Cornix::Device::Session.new(new_device, definition: FakeRmkDevice::DEFINITION) }
  let(:reader) { Cornix::Device::Reader.new(session) }
  let(:planner) { Cornix::Device::Planner.new(session) }
  let(:backup_dir) { Dir.mktmpdir }

  before { stub_const('Cornix::Device::Keyboard::BACKUP_DIR', backup_dir) }
  after { FileUtils.rm_rf(backup_dir) }

  # layout.vil 形式の Hash → DeviceImage（旧 Keycodes で文字列を整数にする。-1 は nil）
  def to_image(vil)
    code = ->(v) { v == -1 ? nil : kc.encode(v) }
    Cornix::Image::DeviceImage.new(
      layers: vil['layout'].map { |rows| rows.map { |cols| cols.map(&code) } },
      encoders: vil['encoder_layout'].map { |es| es.map { |ccw, cw| Cornix::Image::EncoderRecord.new(ccw: code[ccw], cw: code[cw]) } },
      macros: vil['macro'].map do |m|
        m.map do |tag, *args|
          if %w[tap down up].include?(tag)
            Cornix::Image::MacroAction.new(kind: tag.to_sym, keys: args.map(&code))
          else
            Cornix::Image::MacroAction.new(kind: tag.to_sym, value: args.first)
          end
        end
      end,
      tap_dances: vil['tap_dance'].map do |a, b, c, d, term|
        Cornix::Image::TapDanceRecord.new(on_tap: code[a], on_hold: code[b], on_double_tap: code[c], on_tap_hold: code[d],
                                          tapping_term: term)
      end,
      combos: vil['combo'].map { |*keys, out| Cornix::Image::ComboRecord.new(keys: keys.map(&code), output: code[out]) },
      settings: vil['settings'].transform_keys(&:to_i),
      meta: vil.slice('version', 'uid', 'vial_protocol', 'via_protocol', 'layout_options', 'alt_repeat_key', 'key_override')
    )
  end

  let(:old_kind) do
    { key: :set_keycode, encoder: :set_encoder, tap_dance: :set_tap_dance, combo: :set_combo,
      macro: :replace_macros, setting: :set_setting }
  end

  let(:target) do
    keyboard.snapshot.tap do |t|
      t['layout'][1][0][1] = 'KC_BSPC'
      t['layout'][0][1][2] = 'KC_X'          # キーのない位置
      t['layout'][1][1][0] = -1              # -1
      t['encoder_layout'][1][0][1] = 'KC_MUTE'
      t['encoder_layout'][0] << %w[KC_A KC_B] # 存在しないエンコーダ
      t['tap_dance'][1] = ['KC_B', 'MO(1)', 'KC_NO', 'KC_NO', 200]
      t['tap_dance'] << ['KC_C', 'KC_NO', 'KC_NO', 'KC_NO', 200] # 上限超え
      t['combo'][0] = ['KC_A', 'KC_S', 'KC_NO', 'KC_NO', 'M0']
      t['macro'][2] = [['text', 'hi'], ['tap', 'LSFT(KC_2)']]
      t['macro'][3] = [%w[tap KC_A], %w[tap KC_B]]
      t['settings']['7'] = 180
      t['settings']['99'] = 1
      t['layout_options'] = 1
      t['key_override'] = [{}]
    end
  end

  it '同じ変更と警告を計画する' do
    old = keyboard.diff(target)
    plan = planner.plan(current: reader.read, target: to_image(target))
    expect(plan.changes.map(&:kind)).to eq(old[:changes].map { |c| old_kind.fetch(c[:kind]) })
    expect(plan.warnings).to eq(old[:warnings])
    expect(plan.changes.find { |c| c.kind == :replace_macros }.indexes).to eq([2, 3])
    expect(old[:changes].find { |c| c[:kind] == :macro }[:indexes]).to eq([2, 3])
  end

  it '同じバイト列を書き込み、同じ状態になる' do
    old_result = keyboard.apply(target)
    plan = planner.plan(current: reader.read, target: to_image(target))
    result = Cornix::Device::Writer.new(session).apply(plan, backup: -> { 'x' })
    expect(result.applied.size).to eq(old_result[:applied])
    expect(result.remaining).to be_empty
    expect(new_device.writes).to eq(old_device.writes)
    %i[keymap encoders macro tap_dances combos settings].each do |name|
      expect(new_device.public_send(name)).to eq(old_device.public_send(name))
    end
  end

  it 'boot 系キーコードはどちらも拒否する' do
    t = keyboard.snapshot.tap { |s| s['layout'][0][0][1] = 'QK_BOOT' }
    expect { keyboard.diff(t) }.to raise_error(Cornix::Device::DeviceError, /QK_BOOT/)
    expect { planner.plan(current: reader.read, target: to_image(t)) }.to raise_error(Cornix::PlanError, /QK_BOOT/)
  end
end
