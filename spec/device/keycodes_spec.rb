# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/cornix/device/keycodes'

RSpec.describe Cornix::Device::Keycodes do
  subject(:keycodes) { described_class.new(custom_keycodes: [{ 'name' => 'BT0' }, { 'name' => 'BT1' }]) }

  describe '#encode' do
    {
      'KC_NO' => 0x0000, 'KC_TRNS' => 0x0001, 'KC_A' => 0x0004, 'KC_BSPACE' => 0x002A, 'KC_BSPC' => 0x002A,
      'KC_LANG1' => 0x0090, 'LSFT(KC_2)' => 0x021F, 'LGUI(LSFT(KC_EQUAL))' => 0x0A2E, 'SGUI(KC_EQUAL)' => 0x0A2E,
      'RCTL(RSFT(KC_A))' => 0x1304, 'LGUI_T(KC_LANG2)' => 0x2891, 'RSFT_T(KC_A)' => 0x3204,
      'LT1(KC_SPACE)' => 0x412C, 'LT(2, KC_A)' => 0x4204, 'MO(2)' => 0x5222, 'TG(3)' => 0x5263,
      'OSL(4)' => 0x5284, 'TO(1)' => 0x5201, 'TD(3)' => 0x5703, 'M7' => 0x7707, 'USER05' => 0x7E05,
      'BT0' => 0x7E00, 'BT1' => 0x7E01, 'OSM(MOD_LSFT)' => 0x52A2, 'KC_GESC' => 0x7C16, 0x1234 => 0x1234
    }.each do |name, code|
      it "#{name} → 0x#{code.to_s(16)}" do
        expect(keycodes.encode(name)).to eq(code)
      end
    end

    it '不明なキーコードは例外' do
      expect { keycodes.encode('KC_NOT_EXIST') }.to raise_error(described_class::UnknownKeycode)
      expect { keycodes.encode('LSFT(') }.to raise_error(described_class::UnknownKeycode)
    end
  end

  describe '#decode' do
    {
      0x0004 => 'KC_A', 0x002A => 'KC_BSPACE', 0x021F => 'LSFT(KC_2)', 0x0A2E => 'SGUI(KC_EQUAL)',
      0x2891 => 'LGUI_T(KC_LANG2)', 0x412C => 'LT1(KC_SPACE)', 0x5222 => 'MO(2)', 0x5703 => 'TD(3)',
      0x7707 => 'M7', 0x7E00 => 'USER00', 0x7C16 => 'KC_GESC', 0x7FFF => '0x7fff'
    }.each do |code, name|
      it "0x#{code.to_s(16)} → #{name}" do
        expect(keycodes.decode(code)).to eq(name)
      end
    end
  end

  it '表にある全キーコードが往復で一致する' do
    YAML.load_file(described_class::DATA_PATH)['codes'].each do |name, code|
      next if name.end_with?('(kc)')

      expect(keycodes.encode(keycodes.decode(code))).to eq(code), name
    end
  end
end
