# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Cornix::Mapping::KeyDisplay do
  subject(:key_display) { described_class.new(catalog: notation.catalog, notation: notation) }

  let(:notation) { Cornix::Mapping::KeycodeNotation.new }
  let(:references) { Cornix::Mapping::References.new(macros: { 'Bracket Pair' => 0 }, tap_dances: { 'Tab Escape' => 4 }) }

  def show(text)
    keycode = notation.parse(text, references: references)
    [key_display.kind(keycode), key_display.display(keycode, references: references)]
  end

  {
    'A' => ['basic', 'A'],
    'Space' => ['basic', 'Space'],
    'KC_ENT' => ['basic', 'Enter'],
    'KC_STOP' => ['basic', 'STOP'],
    'VolumeUp' => ['basic', 'Vol+'],
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
    'MO(1)' => ['L1', nil, 'L1'],
    'TG(3)' => ['TG L3', 'TG', 'L3'],
    'TO(2)' => ['TO L2', 'TO', 'L2'],
    'OSL(9)' => ['OSL L9', 'OSL', 'L9'],
    'TT(1)' => ['TT L1', 'TT', 'L1'],
    'DF(0)' => ['DF L0', 'DF', 'L0']
  }.each do |text, (label, tap, hold)|
    it "#{text} は帯にレイヤー「#{hold}」、面に「#{tap.inspect}」（名前があっても番号。MO は面を空ける）" do
      expect(show(text)).to eq(['layerAction', { label: label, tap: tap, hold: hold }])
    end
  end

  it 'LM は帯にレイヤー、面に修飾キーの記号' do
    expect(show('LM(1, MOD_LSFT)')).to eq(['layerMod', { label: 'L1 ⇧', tap: '⇧', hold: 'L1' }])
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

  it 'タップダンスの動作の並びは Domain::TapDance::ACTIONS と同じ' do
    expect(described_class::TAP_DANCE_ACTIONS.keys).to eq(Cornix::Domain::TapDance::ACTIONS)
  end

  it 'タップダンスの動作は tap・hold・doubleTap・tapHold の順で、NoKey の動作は省く' do
    tap_dance = Cornix::Domain::TapDance.new(
      index: 4, name: 'Tab Escape', on_tap: notation.parse('Tab'), on_hold: notation.parse('MO(1)'),
      on_double_tap: Cornix::Domain::Keycode::NO_KEY, on_tap_hold: notation.parse("Macro('Bracket Pair')", references: references),
      tapping_term: 200
    )
    expect(key_display.tap_dance_actions(tap_dance, references: references)).to eq(
      [{ action: 'tap', label: 'Tab' }, { action: 'hold', label: 'L1' }, { action: 'tapHold', label: 'Bracket Pair' }]
    )
  end

  it 'すべての 16bit 値に kind と文字がある' do
    codec = notation.codec
    kinds = (0..0xFFFF).map do |code|
      keycode = codec.decode(code)
      shown = key_display.display(keycode, references: references)
      expect(shown[:label]).to be_a(String)
      key_display.kind(keycode)
    end
    expect(kinds.uniq.sort).to eq(%w[basic layerAction layerMod layerTap macro modTap modified noKey oneShotMod quantum raw
                                     tapDance transparent])
  end
end
