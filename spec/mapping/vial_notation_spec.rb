# frozen_string_literal: true

require 'spec_helper'
require 'yaml'
require_relative '../../lib/cornix/device/keycodes'

RSpec.describe Cornix::Mapping::VialNotation do
  subject(:vial) { described_class.new }

  let(:old) { Cornix::Device::Keycodes.new }
  let(:k) { Cornix::Domain::Keycode }

  def old_encode(text)
    old.encode(text)
  rescue Cornix::Device::Keycodes::UnknownKeycode
    nil
  end

  describe '#format_code' do
    it 'すべての 16bit 値で旧 Device::Keycodes#decode と同じ文字列になる' do
      mismatches = (0..0xFFFF).filter_map do |code|
        expected = old.decode(code)
        actual = vial.format_code(code)
        "0x#{format('%04X', code)}: 旧 #{expected} / 新 #{actual}" unless actual == expected
      end
      expect(mismatches.first(20)).to be_empty
    end

    it '範囲外の値は ArgumentError' do
      expect { vial.format_code(0x10000) }.to raise_error(ArgumentError)
    end
  end

  describe '#format' do
    it 'Keycode を .vil の表記にする' do
      expect(vial.format(k::LayerTap.new(layer: Cornix::Domain::LayerRef.new(index: 1), base: k::Basic.new(code: 0x2C))))
        .to eq('LT1(KC_SPACE)')
      expect(vial.format(k::MacroCall.new(index: 7))).to eq('M7')
      expect(vial.format(k::Raw.new(code: 0x7E40))).to eq('0x7e40')
    end
  end

  describe '#parse_code' do
    it '旧 decode が書いたすべての文字列を旧 encode と同じ値にする' do
      mismatches = (0..0xFFFF).filter_map do |code|
        text = old.decode(code)
        expected = old_encode(text) or next
        actual = vial.parse_code(text)
        "#{text}: 旧 #{expected} / 新 #{actual}" unless actual == expected
      end
      expect(mismatches.first(20)).to be_empty
    end

    it '旧 Vial 表の名前と別名をすべて旧 encode と同じ値にする' do
      table = YAML.load_file(File.expand_path('../../lib/cornix/device/via_keycodes.yaml', __dir__))
      names = (table['codes'].map(&:first) + table['aliases'].keys).reject { |name| name.include?('(kc)') }
      mismatches = names.filter_map do |name|
        expected = old_encode(name)
        actual = vial.parse_code(name)
        "#{name}: 旧 #{expected.inspect} / 新 #{actual}" unless actual == expected
      end
      expect(mismatches).to be_empty
    end

    [
      'KC_A', ' KC_A ', 'KC_ENT', 'KC_EXLM', 'LSFT(KC_A)', 'LSFT(LCTL(KC_A))', 'S(KC_1)', 'LCMD(KC_A)', 'LSG(KC_A)',
      'LT(1,KC_A)', 'LT(1, KC_A)', 'LT15(KC_A)', 'MT(MOD_LCTL|MOD_LSFT, KC_A)', 'ALL_T(KC_A)', 'CMD_T(KC_A)',
      'RCAG_T(KC_A)', 'LM(2, MOD_LSFT)', 'OSM(MOD_LCTL|MOD_LSFT)', 'OSM(MOD_MEH)', 'OSM(2)', 'MO(3)', 'MO(20)',
      'TG(3)', 'DF(1)', 'OSL(4)', 'TT(2)', 'PDF(0)', 'TO(3)', 'TO(20)', 'TD(3)', 'M7', 'M255', 'KC_A|0x200',
      '0x7c00', '0x7C00', '123', 'MOD_LSFT', 'USER05', 'QK_BOOT', 'RESET'
    ].each do |text|
      it "#{text.inspect} を旧 encode と同じ値にする" do
        expect(vial.parse_code(text)).to eq(old_encode(text))
      end
    end

    it '整数はそのまま' do
      expect(vial.parse_code(0x7C00)).to eq(0x7C00)
    end

    # 旧実装は表にない書き方（TO( 3) など）だけ ON_PRESS (0x10) を足していた。Vial の表と同じ 0x5200 + n にそろえる
    it 'TO(n) は書き方によらず 0x5200 + n' do
      expect(vial.parse_code('TO(3)')).to eq(0x5203)
      expect(vial.parse_code('TO( 3 )')).to eq(0x5203)
      expect(old_encode('TO( 3 )')).to eq(0x5213)
    end

    it '解釈できなければ UnknownKeycode' do
      ['FOO', 'LSFT(KC_A', 'LSFT(KC_A, KC_B)', 'NOPE(1)', 'M256', 'KC_A)', '0x10000', 'Enter'].each do |text|
        expect { vial.parse_code(text) }.to raise_error(Cornix::UnknownKeycode, /不明なキーコード/), text
      end
    end
  end

  describe '#parse' do
    it 'Keycode にする' do
      expect(vial.parse('LGUI_T(KC_LANG2)')).to eq(
        k::ModTap.new(mods: Cornix::Domain::ModifierSet.new(side: :left, mods: [:gui]), base: k::Basic.new(code: 0x91))
      )
      expect(vial.parse('TD(3)')).to eq(k::TapDanceCall.new(index: 3))
      expect(vial.parse('0x7e40')).to eq(k::Raw.new(code: 0x7E40))
    end

    it 'customKeycodes の名前を受け付ける' do
      custom = described_class.new(catalog: Cornix::Mapping::KeycodeCatalog.load(custom_keycodes: [{ 'name' => 'BT0' }]))
      expect(custom.parse_code('BT0')).to eq(0x7E00)
    end
  end
end
