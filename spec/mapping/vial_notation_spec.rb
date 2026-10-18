# frozen_string_literal: true

require 'spec_helper'
require 'yaml'
require 'zlib'

RSpec.describe Cornix::Mapping::VialNotation do
  subject(:vial) { described_class.new }

  let(:k) { Cornix::Domain::Keycode }

  # 旧 Device::Keycodes の decode / encode の結果（spec/fixtures/expected/vial_codes.tsv.gz に保存したもの）。
  # code => [decode(code), encode(decode(code)) または nil]。保存していない値は ["0x%x", code]
  OLD_CODES = begin
    path = File.expand_path('../fixtures/expected/vial_codes.tsv.gz', __dir__)
    listed = Zlib::GzipReader.open(path) { |gz| gz.read.force_encoding('UTF-8') }.each_line.reject { |l| l.start_with?('#') }
                             .to_h do |line|
      code, text, encoded = line.chomp.split("\t", -1)
      [Integer(code, 16), [text, encoded.empty? ? nil : Integer(encoded, 16)]]
    end
    (0..0xFFFF).map { |code| listed.fetch(code) { [format('0x%x', code), code] } }.freeze
  end

  # 旧 Vial 表（spec/fixtures/vial_keycodes_v6.yaml。旧 lib/cornix/device/via_keycodes.yaml と同じもの）
  VIAL_TABLE = YAML.load_file(File.expand_path('../fixtures/vial_keycodes_v6.yaml', __dir__))


  describe '#format_code' do
    it 'すべての 16bit 値で旧 Device::Keycodes#decode と同じ文字列になる（0x7780〜0x77FF を除く）' do
      mismatches = (0..0xFFFF).filter_map do |code|
        next if (0x7780..0x77FF).cover?(code)

        expected = OLD_CODES[code][0]
        actual = vial.format_code(code)
        "0x#{format('%04X', code)}: 旧 #{expected} / 新 #{actual}" unless actual == expected
      end
      expect(mismatches.first(20)).to be_empty
    end

    it '0x7780〜0x77FF はマクロではない（旧表の M128〜M255）。Vial GUI に名前のない値は 16 進で書く' do
      expect(vial.format_code(0x777F)).to eq('M127')
      expect(vial.format_code(0x7780)).to eq('0x7780')
      expect(vial.format_code(0x77FF)).to eq('0x77ff')
      expect(vial.format_code(0x7C59)).to eq('0x7c59')
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
        text, expected = OLD_CODES[code]
        next if expected.nil?

        actual = vial.parse_code(text)
        "#{text}: 旧 #{expected} / 新 #{actual}" unless actual == expected
      end
      expect(mismatches.first(20)).to be_empty
    end

    it '旧 Vial 表の名前と別名をすべて旧 encode と同じ値にする' do
      codes = VIAL_TABLE['codes'].reject { |name, _| name.include?('(kc)') }.to_h
      aliases = VIAL_TABLE['aliases'].reject { |name, _| name.include?('(kc)') }.transform_values { |name| codes.fetch(name) }
      mismatches = codes.merge(aliases).filter_map do |name, expected|
        actual = vial.parse_code(name)
        "#{name}: 旧 #{expected.inspect} / 新 #{actual}" unless actual == expected
      end
      expect(mismatches).to be_empty
    end

    # 旧 Device::Keycodes#encode の値
    {
      'KC_A' => 0x0004, ' KC_A ' => 0x0004, 'KC_ENT' => 0x0028, 'KC_EXLM' => 0x021E,
      'LSFT(KC_A)' => 0x0204, 'LSFT(LCTL(KC_A))' => 0x0304, 'S(KC_1)' => 0x021E, 'LCMD(KC_A)' => 0x0804,
      'LSG(KC_A)' => 0x0A04, 'LT(1,KC_A)' => 0x4104, 'LT(1, KC_A)' => 0x4104, 'LT15(KC_A)' => 0x4F04,
      'MT(MOD_LCTL|MOD_LSFT, KC_A)' => 0x2304, 'ALL_T(KC_A)' => 0x2F04, 'CMD_T(KC_A)' => 0x2804, 'RCAG_T(KC_A)' => 0x3D04,
      'LM(2, MOD_LSFT)' => 0x5042, 'OSM(MOD_LCTL|MOD_LSFT)' => 0x52A3, 'OSM(MOD_MEH)' => 0x52A7, 'OSM(2)' => 0x52A2,
      'MO(3)' => 0x5223, 'MO(20)' => 0x5234, 'TG(3)' => 0x5263, 'DF(1)' => 0x5241,
      'OSL(4)' => 0x5284, 'TT(2)' => 0x52C2, 'PDF(0)' => 0x52E0, 'TO(3)' => 0x5203,
      'TO(20)' => 0x5214, 'TD(3)' => 0x5703, 'M7' => 0x7707, 'M255' => 0x77FF,
      'KC_A|0x200' => 0x0204, '0x7c00' => 0x7C00, '0x7C00' => 0x7C00, '123' => 0x007B,
      'MOD_LSFT' => 0x0002, 'USER05' => 0x7E05, 'QK_BOOT' => 0x7C00, 'RESET' => 0x7C00
    }.each do |text, expected|
      it "#{text.inspect} を旧 encode と同じ値にする" do
        expect(vial.parse_code(text)).to eq(expected)
      end
    end

    it '整数はそのまま' do
      expect(vial.parse_code(0x7C00)).to eq(0x7C00)
    end

    # 旧実装は表にない書き方（TO( 3) など）だけ ON_PRESS (0x10) を足していた。Vial の表と同じ 0x5200 + n にそろえる
    it 'TO(n) は書き方によらず 0x5200 + n' do
      expect(vial.parse_code('TO(3)')).to eq(0x5203)
      expect(vial.parse_code('TO( 3 )')).to eq(0x5203)
      # 旧 encode('TO( 3 )') は 0x5213 だった
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
