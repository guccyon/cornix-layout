# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Cornix::Mapping::KeyDisplay do
  subject(:key_display) { described_class.new(catalog: notation.catalog, notation: notation) }

  let(:notation) { Cornix::Mapping::KeycodeNotation.new }
  let(:references) { Cornix::Mapping::References.new(macros: { 'Bracket Pair' => 0 }, tap_dances: { 'Tab Escape' => 4 }) }
  let(:layer_names) { { 1 => 'Symbols' } }

  def show(text)
    keycode = notation.parse(text, references: references)
    [key_display.kind(keycode), key_display.display(keycode, references: references, layer_names: layer_names)]
  end

  {
    'A' => ['basic', 'A'],
    'Space' => ['basic', 'Space'],
    'KC_ENT' => ['basic', 'Enter'],
    'KC_STOP' => ['basic', 'STOP'],
    'VolumeUp' => ['basic', 'VolumeUp'],
    'Cmd' => ['basic', '⌘'],
    'LShift' => ['basic', '⇧'],
    'Option' => ['basic', '⌥'],
    'Ctrl' => ['basic', '⌃'],
    'RCmd' => ['basic', 'R⌘'],
    'Shift + Command + P' => ['modified', '⇧⌘P'],
    'Command + Shift + P' => ['modified', '⇧⌘P'],
    'Ctrl + Option + Shift + Command + T' => ['modified', '⌃⌥⇧⌘T'],
    'Option + Up' => ['modified', '⌥Up'],
    'RCtrl + RShift + A' => ['modified', 'R⌃⇧A'],
    '!' => ['modified', '!'],
    'LSFT(KC_1)' => ['modified', '!'],
    'MO(1)' => ['layerAction', 'MO Symbols'],
    'TG(3)' => ['layerAction', 'TG L3'],
    'OSL(9)' => ['layerAction', 'OSL L9'],
    'LM(1, MOD_LSFT)' => ['layerMod', 'Symbols ⇧'],
    'OSM(MOD_LSFT|MOD_LGUI)' => ['oneShotMod', 'OSM ⇧⌘'],
    'Macro(0)' => ['macro', 'Bracket Pair'],
    'M5' => ['macro', 'M5'],
    'TD(4)' => ['tapDance', 'Tab Escape'],
    'TD(2)' => ['tapDance', 'TD(2)'],
    'Repeat' => ['quantum', 'Repeat'],
    'BT0' => ['quantum', 'BT0'],
    'NoKey' => ['noKey', ''],
    'Trans' => ['transparent', '▽'],
    '0x7E40' => ['raw', '0x7E40']
  }.each do |text, (kind, label)|
    it "#{text} は #{kind} で「#{label}」" do
      expect(show(text)).to eq([kind, { label: label, tap: nil, hold: nil }])
    end
  end

  {
    'LT1(Space)' => ['layerTap', 'Space', 'L1'],
    'LT(2, Escape)' => ['layerTap', 'Escape', 'L2'],
    'LGUI_T(Lang2)' => ['modTap', 'Lang2', '⌘'],
    'RSFT_T(Up)' => ['modTap', 'Up', 'R⇧'],
    'MT(MOD_LCTL|MOD_LSFT, A)' => ['modTap', 'A', '⌃⇧']
  }.each do |text, (kind, tap, hold)|
    it "#{text} は 2 役のキーで tap「#{tap}」hold「#{hold}」" do
      expect(show(text)).to eq([kind, { label: tap, tap: tap, hold: hold }])
    end
  end

  it '参照の名前がなければ番号（references を省いたとき）' do
    keycode = notation.parse('M0')
    expect(key_display.display(keycode)).to eq({ label: 'M0', tap: nil, hold: nil })
  end

  it 'すべての 16bit 値に kind と文字がある' do
    codec = notation.codec
    kinds = (0..0xFFFF).map do |code|
      keycode = codec.decode(code)
      shown = key_display.display(keycode, references: references, layer_names: layer_names)
      expect(shown[:label]).to be_a(String)
      key_display.kind(keycode)
    end
    expect(kinds.uniq.sort).to eq(%w[basic layerAction layerMod layerTap macro modTap modified noKey oneShotMod quantum raw
                                     tapDance transparent])
  end
end
