# frozen_string_literal: true

require 'spec_helper'

# 期待値は QMK の公式の表（https://docs.qmk.fm/keycodes の「Key」の列。qmk_firmware の data/constants/keycodes 0.0.9 時点）の名前。
# US の Shift 付きの記号は docs の Key の列（KC_EXCLAIM）に合わせ、hjson の key（KC_EXLM）ではない
RSpec.describe Cornix::Mapping::QmkNotation do
  let(:catalog) { Cornix::Mapping::KeycodeCatalog.default }
  let(:codec) { Cornix::Mapping::KeycodeCodec.new(catalog) }
  let(:notation) { Cornix::Mapping::VialNotation.new(catalog: catalog, codec: codec) }

  subject(:qmk) { described_class.new(catalog: catalog, codec: codec) }

  def name_of(text) = qmk.format(notation.parse(text))

  def expect_names(table)
    table.each { |text, expected| expect(name_of(text)).to eq(expected), "#{text} → #{expected.inspect}" }
  end

  it '基本キーとメディアキーは公式の長い名前（Vial の古い名前や短い名前ではなく）' do
    expect_names('KC_A' => 'KC_A', 'KC_SPACE' => 'KC_SPACE', 'KC_BSPACE' => 'KC_BACKSPACE', 'KC_ENTER' => 'KC_ENTER',
                 'KC_PGDOWN' => 'KC_PAGE_DOWN', 'KC_LANG1' => 'KC_LANGUAGE_1', 'KC_RO' => 'KC_INTERNATIONAL_1',
                 'KC_MPLY' => 'KC_MEDIA_PLAY_PAUSE', 'KC_VOLU' => 'KC_AUDIO_VOL_UP', 'KC_BRIU' => 'KC_BRIGHTNESS_UP',
                 'KC_MS_U' => 'QK_MOUSE_CURSOR_UP', 'KC_BTN1' => 'QK_MOUSE_BUTTON_1')
  end

  it 'KC_NO と KC_TRNS' do
    expect_names('KC_NO' => 'KC_NO', 'KC_TRNS' => 'KC_TRANSPARENT')
  end

  it '修飾キー単体' do
    expect_names('KC_LGUI' => 'KC_LEFT_GUI', 'KC_LCTRL' => 'KC_LEFT_CTRL', 'KC_RSHIFT' => 'KC_RIGHT_SHIFT', 'KC_RALT' => 'KC_RIGHT_ALT')
  end

  it '修飾付きは QMK の修飾関数（組にも名前がある。名前のない組は入れ子）' do
    expect_names('LSFT(KC_P)' => 'LSFT(KC_P)', 'LSFT(LGUI(KC_P))' => 'LSG(KC_P)', 'LCTL(LSFT(KC_A))' => 'LCS(KC_A)',
                 'LCAG(KC_A)' => 'LCAG(KC_A)', 'MEH(KC_A)' => 'MEH(KC_A)', 'HYPR(KC_A)' => 'HYPR(KC_A)',
                 'RCTL(KC_A)' => 'RCTL(KC_A)', 'RSFT(RGUI(KC_A))' => 'RSG(KC_A)',
                 '0x1704' => 'RCTL(RSFT(RALT(KC_A)))', '0x1F04' => 'RCTL(RSFT(RALT(RGUI(KC_A))))')
  end

  it 'US の Shift 付きの記号は KC_EXCLAIM などの名前（右の Shift は名前がないので関数の形）' do
    expect_names('LSFT(KC_1)' => 'KC_EXCLAIM', 'KC_DQUO' => 'KC_DOUBLE_QUOTE', 'RSFT(KC_1)' => 'RSFT(KC_1)')
  end

  it 'レイヤー操作と LT・LM' do
    expect_names('MO(1)' => 'MO(1)', 'TG(2)' => 'TG(2)', 'TO(3)' => 'TO(3)', 'DF(0)' => 'DF(0)', 'OSL(4)' => 'OSL(4)',
                 'TT(5)' => 'TT(5)', 'PDF(0)' => 'PDF(0)', 'LT1(KC_SPACE)' => 'LT(1, KC_SPACE)',
                 'LM(1, MOD_LSFT)' => 'LM(1, MOD_LSFT)', 'LM(2, MOD_LCTL|MOD_LALT)' => 'LM(2, MOD_LCTL | MOD_LALT)')
  end

  it 'Mod-Tap（名前のない組は MT(mods, kc)）' do
    expect_names('LGUI_T(KC_LANG2)' => 'LGUI_T(KC_LANGUAGE_2)', 'RSFT_T(KC_UP)' => 'RSFT_T(KC_UP)',
                 'LSG_T(KC_A)' => 'LSG_T(KC_A)', 'MEH_T(KC_A)' => 'MEH_T(KC_A)', 'ALL_T(KC_A)' => 'HYPR_T(KC_A)',
                 'RCAG_T(KC_A)' => 'RCAG_T(KC_A)', '0x3704' => 'MT(MOD_RCTL | MOD_RSFT | MOD_RALT, KC_A)')
  end

  it 'OSM' do
    expect_names('OSM(MOD_LSFT)' => 'OSM(MOD_LSFT)', 'OSM(MOD_LCTL|MOD_LSFT)' => 'OSM(MOD_LCTL | MOD_LSFT)',
                 'OSM(MOD_MEH)' => 'OSM(MOD_MEH)', 'OSM(MOD_HYPR)' => 'OSM(MOD_HYPR)', 'OSM(MOD_RCTL|MOD_RALT)' => 'OSM(MOD_RCTL | MOD_RALT)')
  end

  it 'マクロは QK_MACRO_n（QMK に名前のある 31 まで）、タップダンスは TD(n)' do
    expect_names('M0' => 'QK_MACRO_0', 'M31' => 'QK_MACRO_31', 'M40' => nil, 'TD(4)' => 'TD(4)', 'TD(255)' => 'TD(255)')
  end

  it '特殊キーは QK_ の公式の名前' do
    expect_names('QK_BOOT' => 'QK_BOOTLOADER', 'RGB_TOG' => 'QK_UNDERGLOW_TOGGLE', 'MAGIC_UNHOST_NKRO' => 'QK_MAGIC_NKRO_OFF',
                 'KC_GESC' => 'QK_GRAVE_ESCAPE', 'QK_REPEAT_KEY' => 'QK_REPEAT_KEY', 'FN_MO13' => 'QK_TRI_LAYER_LOWER',
                 'RGB_M_P' => 'RGB_MODE_PLAIN', 'USER00' => 'QK_KB_0')
  end

  it 'QMK に名前のない値（Raw、Vial GUI だけの USER32〜）は nil' do
    expect_names('0x5C00' => nil, 'USER32' => nil, 'USER63' => nil)
  end

  it 'Cornix の表にない値（Raw）は、QMK に名前があっても nil（v0.1 では表にある値だけ）' do
    expect_names('0x7E40' => nil, '0x0700' => nil) # QMK の QK_USER_0 と KC_MEH
  end

  # 表（data/keycodes.yaml）に別名を足して、選ばれる名前が黙って変わったら落ちる。
  # 期待値の表は QMK の公式の名前と突き合わせて作った（PR #45）。表を変えて名前が変わるときは、QMK の名前と比べてから期待値を直す
  it '名前付きのすべての値で、選ぶ名前は spec/fixtures/expected/qmk_names.yaml と同じ' do
    expected = YAML.safe_load_file(File.join(__dir__, '../fixtures/expected/qmk_names.yaml'))
    actual = (0..0xFFFF).reject { |code| catalog.names_for(code).empty? }
                        .to_h { |code| [format('0x%04X', code), qmk.format(codec.decode(code))] }
    expect(actual).to eq(expected)
  end

  it 'customKeycodes の名前（BT0 など）は使わない' do
    custom = Cornix::Mapping::KeycodeCatalog.load(custom_keycodes: [{ 'name' => 'BT0' }])
    named = described_class.new(catalog: custom, codec: Cornix::Mapping::KeycodeCodec.new(custom))
    expect(named.format(Cornix::Domain::Keycode::Quantum.new(code: 0x7E00))).to eq('QK_KB_0')
  end
end
