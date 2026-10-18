# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/cornix/modifier_expression_compiler'

RSpec.describe Cornix::Mapping::KeycodeNotation do
  subject(:notation) { described_class.new }

  let(:codec) { notation.codec }
  let(:k) { Cornix::Domain::Keycode }
  let(:none) { Cornix::Mapping::References::NONE }
  let(:refs) do
    Cornix::Mapping::References.new(
      macros: { 'Copy Selected' => 2, "It's" => 3, %(Say "it's") => 4 },
      tap_dances: { 'Tab Escape' => 4 }
    )
  end

  def code(text, references: refs) = codec.encode(notation.parse(text, references: references))

  describe '#parse' do
    {
      # 別名・QMK 名
      'Tab' => 0x002B, '  Tab  ' => 0x002B, 'KC_TAB' => 0x002B, 'KC_ENT' => 0x0028, 'Trans' => 0x0001,
      '___' => 0x0001, 'NoKey' => 0x0000, 'KC_NO' => 0x0000, 'KC_TRANSPARENT' => 0x0001,
      '!' => 0x021E, 'KC_EXLM' => 0x021E, '¥' => 0x041C, '+' => 0x022E, '(' => 0x0226, ',' => 0x0036,
      'LCtrl' => 0x00E0, 'RShift' => 0x00E5, 'USER00' => 0x7E00, 'BT0' => 0x7E00, 'QK_BOOT' => 0x7C00,
      'KC_LEFT_PAREN' => 0x0226, 'KC_RIGHT_PAREN' => 0x0227,
      # 修飾関数
      'LSFT(KC_1)' => 0x021E, 'LSFT(A)' => 0x0204, 'LSFT(1)' => 0x021E, 'SGUI(KC_4)' => 0x0A21,
      'LGUI(LSFT(KC_Q))' => 0x0A14, 'HYPR(Left)' => 0x0F50, 'MEH(A)' => 0x0704, 'LCS(A)' => 0x0304,
      'C_S(A)' => 0x0304, 'LSG(A)' => 0x0A04, 'LCAG(A)' => 0x0D04, 'RCG(A)' => 0x1904, 'RCAG(A)' => 0x1D04,
      'LCMD(A)' => 0x0804, 'ALGR(A)' => 0x1404, 'S(KC_1)' => 0x021E, 'LGUI(Plus)' => 0x0A2E,
      # ModTap
      'LGUI_T(KC_LANG2)' => 0x2891, 'RSFT_T(KC_UP)' => 0x3252, 'ALL_T(Esc)' => 0x2F29,
      'CTL_T(A)' => 0x2104, 'MT(MOD_LCTL|MOD_LSFT, A)' => 0x2304, 'MEH_T(A)' => 0x2704,
      # レイヤー
      'LT1(Space)' => 0x412C, 'LT1(KC_SPACE)' => 0x412C, 'LT(1, KC_A)' => 0x4104, 'LT(2,Space)' => 0x422C,
      'MO(3)' => 0x5223, 'TG(3)' => 0x5263, 'TO(0)' => 0x5200, 'TO(20)' => 0x5214, 'DF(1)' => 0x5241,
      'OSL(4)' => 0x5284, 'TT(2)' => 0x52C2, 'PDF(0)' => 0x52E0, 'LM(1, MOD_LSFT)' => 0x5022,
      'OSM(MOD_LSFT)' => 0x52A2, 'OSM(MOD_LCTL|MOD_LSFT)' => 0x52A3, 'OSM(MOD_MEH)' => 0x52A7,
      # 参照
      'M2' => 0x7702, 'M11' => 0x770B, 'TD(4)' => 0x5704, 'Macro(3)' => 0x7703, 'TapDance(2)' => 0x5702,
      "Macro('Copy Selected')" => 0x7702, 'Macro("Copy Selected")' => 0x7702, "TapDance('Tab Escape')" => 0x5704,
      %(Macro("It's")) => 0x7703, %(Macro('Say "it\\'s"')) => 0x7704,
      # 修飾キー式
      'Cmd + Q' => 0x0814, 'Cmd+Q' => 0x0814, 'Cmd  +  Q' => 0x0814, 'Shift + Cmd + Q' => 0x0A14,
      'Cmd + Shift + Q' => 0x0A14, 'Command + Plus' => 0x0A2E, 'Command + Minus' => 0x082D,
      'Ctrl + Option + Shift + Command + Left' => 0x0F50, 'Shift + Command + Enter' => 0x0A28,
      'Shift + +' => 0x022E, 'Ctrl + "-"' => 0x012D, "Shift + '='" => 0x022E, 'Cmd + ]' => 0x0830,
      'Cmd + "]"' => 0x0830, 'Cmd + KC_ENTER' => 0x0828, 'Win + E' => 0x0808, 'Option + Tab' => 0x042B,
      'Control + C' => 0x0106, 'RShift + RCmd + Q' => 0x1A14, 'Ctrl + Shift + Alt + A' => 0x0704,
      'Cmd + LSFT(A)' => 0x0A04,
      # 生の値
      '0x7C00' => 0x7C00, '0x00E8' => 0x00E8, '0x1000' => 0x1000
    }.each do |text, expected|
      it "#{text} → 0x#{format('%04X', expected)}" do
        expect(code(text)).to eq(expected)
      end
    end

    it 'YAML に数値で書かれた値は 16bit の値そのもの' do
      expect(notation.parse(5)).to eq(k::Basic.new(code: 0x05))
      expect(notation.parse(0)).to eq(k::NO_KEY)
    end

    it '修飾キー式は修飾キーの順序に依存しない' do
      expect(notation.parse('Alt + Ctrl + Shift + Q')).to eq(notation.parse('Ctrl + Shift + Alt + Q'))
    end

    it '修飾キー式の修飾名はすべて正しいビットになる' do
      expected = { shift: 0x02, ctrl: 0x01, alt: 0x04, gui: 0x08 }
      described_class::Modifiers::EXPRESSION.each do |name, (side, mod)|
        bits = expected.fetch(mod) | (side == :right ? 0x10 : 0)
        expect(code("#{name} + A")).to eq((bits << 8) | 0x04), name
      end
    end

    it '旧 ModifierExpressionCompiler が受け付けた修飾名をすべて受け付ける' do
      expect(described_class::Modifiers::EXPRESSION.keys)
        .to include(*Cornix::ModifierExpressionCompiler::MODIFIER_TO_FUNCTION.keys)
    end

    # 旧実装は LCS / LCSG / LSAG / RCSG / RCAG / RSAG / RCA / RSG / RAG を書き出し（.vil で解釈できない）、
    # 右の Ctrl+Shift+Alt を左の MEH にしていた
    it '旧実装で .vil に書けなかった修飾の組も正しい値になる' do
      {
        'Ctrl + Shift + A' => 0x0304, 'Ctrl + Shift + Cmd + A' => 0x0B04, 'Shift + Alt + Cmd + A' => 0x0E04,
        'RCtrl + RShift + RCmd + A' => 0x1B04, 'RCtrl + RAlt + RCmd + A' => 0x1D04,
        'RShift + RAlt + RCmd + A' => 0x1E04, 'RCtrl + RAlt + A' => 0x1504, 'RShift + RCmd + A' => 0x1A04,
        'RAlt + RCmd + A' => 0x1C04, 'RCtrl + RShift + RAlt + A' => 0x1704
      }.each { |text, expected| expect(code(text)).to eq(expected), text }
    end

    describe 'エラー（利用者向けの日本語）' do
      {
        'Shift + RCmd + A' => /左右の修飾キーは混在できません/,
        'LSFT(RCTL(A))' => /左右の修飾キーは混在できません/,
        'OSM(MOD_LCTL|MOD_RSFT)' => /左右の修飾キーは混在できません/,
        'Hoge + A' => /修飾キー名「Hoge」は使えません/,
        'Cmd +' => /キーがありません/,
        'enter' => /「enter」は不明なキーコードです（もしかして: Enter）/,
        'Foo' => /「Foo」は不明なキーコードです/,
        'LSFT(MO(1))' => /基本キーだけ/,
        'LGUI_T(LSFT(A))' => /基本キーだけ/,
        'Combo(1)' => /\.vil で表せません/,
        "Combo('Pair')" => /\.vil で表せません/,
        "Macro('nope')" => /マクロ「nope」が見つかりません/,
        "TapDance('nope')" => /タップダンス「nope」が見つかりません/,
        'Macro(InvalidArg)' => /'名前' か番号/,
        'MO(40)' => /レイヤー番号/,
        'LT(16, A)' => /0〜15/,
        'LT0(1, A)' => /引数は 1 個/,
        'MO(A)' => /引数は数値/,
        'FOO(A)' => /関数 FOO\(...\) は使えません/,
        'M300' => /マクロ番号/,
        'DB_TOGG' => /不明なキーコード/,
        '' => /キーコードが空です/
      }.each do |text, message|
        it "#{text.inspect} は UnknownKeycode" do
          expect { notation.parse(text, references: refs) }.to raise_error(Cornix::UnknownKeycode, message)
        end
      end

      it '文字列でも整数でもなければ UnknownKeycode' do
        expect { notation.parse(:tab) }.to raise_error(Cornix::UnknownKeycode, /文字列で書いてください/)
        expect { notation.parse(-1) }.to raise_error(Cornix::UnknownKeycode, /0〜0xFFFF/)
      end
    end
  end

  describe '#format' do
    {
      0x002B => 'Tab', 0x0029 => 'Escape', 0x0000 => 'NoKey', 0x0001 => 'Trans', 0x021E => '!',
      0x0032 => 'KC_NONUS_HASH', 0x7C00 => 'Reset', 0x7C01 => 'QK_REBOOT', 0x7E00 => 'BT0',
      0x0A28 => 'Shift + Command + Enter', 0x0F50 => 'Ctrl + Option + Shift + Command + Left',
      0x0A2E => 'Shift + Command + =', 0x1304 => 'RCtrl + RShift + A', 0x1F04 => 'RCtrl + ROption + RShift + RCommand + A',
      0x2891 => 'LGUI_T(KC_LANG2)', 0x2F29 => 'HYPR_T(Escape)', 0x2304 => 'C_S_T(A)',
      0x3704 => 'MT(MOD_RCTL|MOD_RSFT|MOD_RALT, A)', 0x2136 => "LCTL_T(',')", 0x4134 => %(LT1("'")),
      0x412C => 'LT1(Space)', 0x5223 => 'MO(3)', 0x5200 => 'TO(0)', 0x52E0 => 'PDF(0)',
      0x5022 => 'LM(1, MOD_LSFT)', 0x52A7 => 'OSM(MOD_LCTL|MOD_LSFT|MOD_LALT)',
      0x7705 => 'M5', 0x5701 => 'TD(1)', 0x00E8 => '0x00E8', 0x1000 => '0x1000'
    }.each do |value, expected|
      it "0x#{format('%04X', value)} → #{expected}" do
        expect(notation.format(codec.decode(value))).to eq(expected)
      end
    end

    it '名前の分かる参照は名前で書く' do
      expect(notation.format(k::MacroCall.new(index: 2), references: refs)).to eq("Macro('Copy Selected')")
      expect(notation.format(k::MacroCall.new(index: 3), references: refs)).to eq(%(Macro("It's")))
      expect(notation.format(k::MacroCall.new(index: 4), references: refs)).to eq(%(Macro('Say "it\\'s"')))
      expect(notation.format(k::TapDanceCall.new(index: 4), references: refs)).to eq("TapDance('Tab Escape')")
      expect(notation.format(k::TapDanceCall.new(index: 1), references: refs)).to eq('TD(1)')
    end
  end

  describe '不変条件 parse(format(k)) == k' do
    let(:named_refs) do
      Cornix::Mapping::References.new(
        macros: (0..255).to_h { |i| ["マクロ #{i} 'x' \"y\"", i] },
        tap_dances: (0..255).to_h { |i| ["TD #{i} (a, b) + c", i] }
      )
    end

    it 'すべての 16bit 値の decode で成り立つ' do
      failures = []
      [none, named_refs].each do |references|
        (0..0xFFFF).each do |value|
          keycode = codec.decode(value)
          text = notation.format(keycode, references: references)
          back = begin
            notation.parse(text, references: references)
          rescue Cornix::UnknownKeycode => e
            e
          end
          failures << "0x#{format('%04X', value)} #{text.inspect} → #{back.inspect}" unless back == keycode
        end
      end
      expect(failures.first(20)).to be_empty
    end
  end
end
