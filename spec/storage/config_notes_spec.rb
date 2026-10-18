# frozen_string_literal: true

require 'spec_helper'
require_relative 'support/storage_helpers'

RSpec.describe 'Storage::ConfigRepository の注記（{ key: ..., note: ... }）' do
  include StorageHelpers

  let(:k) { Cornix::Domain::Keycode }
  let(:mapper) { Cornix::Mapping::ProfileMapper.new }

  def edit(dir, rel, from, to)
    path = File.join(dir, rel)
    text = File.read(path)
    raise "#{rel} に #{from.inspect} がありません" unless from.is_a?(Regexp) ? text.match?(from) : text.include?(from)

    File.write(path, text.sub(from, to))
  end

  # レイヤー 0 の tab とエンコーダ、タップダンス 1、コンボ 0 に注記を付ける
  def add_notes(dir)
    edit(dir, 'layers/0_layer_0.yaml', "      tab: Tab\n", "      tab:\n        key: Tab\n        note: インデント\n")
    edit(dir, 'layers/0_layer_0.yaml', "      push: Mute\n", "      push: { key: Mute, note: ミュート }\n")
    edit(dir, 'tap_dance/01_tap_dance.yaml', "on_tap: SGUI(KC_4)\n", "on_tap:\n  key: SGUI(KC_4)\n  note: 範囲のスクリーンショット\n")
    edit(dir, 'combos/00_combo.yaml', "output_key: KC_LBRACKET", "output_key: { key: KC_LBRACKET, note: 開き括弧 }")
  end

  def tab(profile) = profile.position_map.position('left_hand', 'row0', 'tab')

  it '割り当てを書くどの場所でも注記付きの形を読む' do
    with_config_copy do |dir|
      add_notes(dir)
      profile = repository(dir).load
      layer = profile.layer(0)
      expect(layer.key(tab(profile))).to eq(k::Basic.new(code: 0x2B))
      expect(layer.note(tab(profile))).to eq('インデント')
      expect(layer.encoder(:left).note(:push)).to eq('ミュート')
      expect(profile.tap_dance(1).note(:on_tap)).to eq('範囲のスクリーンショット')
      expect(profile.combo(0).output_note).to eq('開き括弧')
      expect(profile.combo(0).output_key).to eq(k::Basic.new(code: 0x2F))
    end
  end

  it '注記はデバイスのイメージ（compile の結果）を変えない' do
    with_config_copy do |dir|
      plain = mapper.to_image(repository(dir).load)
      add_notes(dir)
      expect(mapper.to_image(repository(dir).load)).to eq(plain)
    end
  end

  it 'save は注記のある場所を key / note の形で書き、読み直すと同じ Profile になる' do
    with_config_copy do |dir|
      add_notes(dir)
      profile = repository(dir).load
      Dir.mktmpdir do |out|
        repository(out).save(profile)
        expect(File.read(File.join(out, 'layers/0_layer.yaml')))
          .to include("      tab:\n        key: Tab\n        note: インデント\n      Q: Q\n")
          .and include("      push:\n        key: Mute\n        note: ミュート\n      ccw: VolumeDown\n")
        expect(File.read(File.join(out, 'combos/00_combo.yaml'))).to include("output_key:\n  key: \"[\"\n  note: 開き括弧\n")
        expect(repository(out).load).to eq(profile)
      end
    end
  end

  it '3 通りの書き方（key と note、key だけのマッピング、キーだけ）を読む' do
    with_config_copy do |dir|
      edit(dir, 'layers/0_layer_0.yaml', "      tab: Tab\n", "      tab:\n        key: MouseButton1\n        note: 左クリック\n")
      edit(dir, 'layers/0_layer_0.yaml', "      Q: Q\n", "      Q:\n        key: MouseButton1\n")
      edit(dir, 'layers/0_layer_0.yaml', "      W: W\n", "      W: MouseButton1\n")
      profile = repository(dir).load
      layer = profile.layer(0)
      positions = %w[tab Q W].map { |s| profile.position_map.position('left_hand', 'row0', s) }
      expect(positions.map { |p| layer.key(p) }.uniq).to eq([k::Basic.new(code: 0xD1)])
      expect(positions.map { |p| layer.note(p) }).to eq(['左クリック', nil, nil])
    end
  end

  it '空の注記は注記なしとして読む' do
    with_config_copy do |dir|
      edit(dir, 'layers/0_layer_0.yaml', "      tab: Tab\n", "      tab: { key: Tab, note: '' }\n")
      expect(repository(dir).load.layer(0).notes).to eq({})
    end
  end

  it '形の誤りは位置付きの問題にする' do
    with_config_copy do |dir|
      edit(dir, 'layers/0_layer_0.yaml', "      tab: Tab\n", "      tab: { key: Tab, note: 1 }\n")
      edit(dir, 'layers/0_layer_0.yaml', "      Q: Q\n", "      Q: { note: 説明だけ }\n")
      edit(dir, 'layers/0_layer_0.yaml', "      W: W\n", "      W: { key: W, memo: x }\n")
      edit(dir, 'layers/0_layer_0.yaml', "      E: E\n", "      E: { key: NotAKey, note: x }\n")
      problems = load_problems(dir)
      expect(problems).to include(a_string_matching(/0_layer_0.yaml: mapping.left_hand.row0.tab.note: 注記（文字列）/))
        .and include(a_string_matching(/mapping.left_hand.row0.Q: key がありません/))
        .and include(a_string_matching(/mapping.left_hand.row0.W.memo: 未知のキーです（使えるキー: key, note）/))
        .and include(a_string_matching(/mapping.left_hand.row0.E.key: /))
    end
  end

  it 'エンコーダ・タップダンス・コンボの形の誤りもそれぞれの位置で報告する' do
    with_config_copy do |dir|
      edit(dir, 'layers/0_layer_0.yaml', "      push: Mute\n", "      push: { key: Mute, note: 1 }\n")
      edit(dir, 'layers/0_layer_0.yaml', "      ccw: VolumeDown\n", "      ccw: { key: ~, note: x }\n")
      edit(dir, 'tap_dance/01_tap_dance.yaml', "on_tap: SGUI(KC_4)\n", "on_tap: { key: SGUI(KC_4), note: [x] }\n")
      edit(dir, 'combos/00_combo.yaml', "output_key: KC_LBRACKET", "output_key: { note: 開き括弧 }")
      edit(dir, 'combos/01_combo.yaml', /output_key: .*/, 'output_key: [A]')
      problems = load_problems(dir)
      expect(problems).to include(a_string_matching(/mapping.encoders.left.push.note: 注記（文字列）/))
        .and include(a_string_matching(/mapping.encoders.left.ccw.key: キーコード（文字列）/))
        .and include(a_string_matching(%r{tap_dance/01_tap_dance.yaml: on_tap.note: 注記（文字列）}))
        .and include(a_string_matching(%r{combos/00_combo.yaml: output_key: key がありません}))
        .and include(a_string_matching(%r{combos/01_combo.yaml: output_key: キーコード（文字列）か \{ key: キーコード, note: 注記 \}}))
    end
  end

  it '空白だけの注記も注記なしとして読む' do
    with_config_copy do |dir|
      edit(dir, 'combos/00_combo.yaml', "output_key: KC_LBRACKET", "output_key: { key: KC_LBRACKET, note: '  ' }")
      expect(repository(dir).load.combo(0).notes).to eq({})
    end
  end

  it '診断の位置は注記付きの形ならキーコード（.key）を指す' do
    with_config_copy do |dir|
      add_notes(dir)
      locator = Cornix::Storage::DiagnosticLocator.new(dir)
      expect(locator.locate_path('layers[0].left_hand.row0.tab')).to eq('layers/0_layer_0.yaml: mapping.left_hand.row0.tab.key')
      expect(locator.locate_path('layers[0].encoders.left.push')).to eq('layers/0_layer_0.yaml: mapping.encoders.left.push.key')
      expect(locator.locate_path('layers[0].left_hand.row0.Q')).to eq('layers/0_layer_0.yaml: mapping.left_hand.row0.Q')
      expect(locator.locate_path('tap_dances[1].on_tap')).to eq('tap_dance/01_tap_dance.yaml: on_tap.key')
      expect(locator.locate_path('combos[0].output_key')).to eq('combos/00_combo.yaml: output_key.key')
    end
  end
end
