# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'tmpdir'

RSpec.describe Cornix::Application::Editor::Snapshot do
  around do |example|
    Dir.mktmpdir('cornix-snapshot') do |dir|
      @root = File.realpath(dir)
      FileUtils.cp_r(File.join(__dir__, '../../fixtures/test_config'), File.join(@root, 'profile'))
      example.run
    end
  end

  let(:workbench) { Cornix::Application::Editor::Workbench.new(root: @root) }
  let(:opened) { workbench.open('profile') }
  let(:snapshot) { described_class.new(workbench).call(opened.id) }

  def write(rel, text)
    path = File.join(@root, 'profile', rel)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, text)
  end

  def version(rel) = Cornix::Storage::FileVersion.read(File.join(@root, 'profile', rel))

  def key(snap, layer, hand, row, col)
    snap[:layers][layer][:keys].find { |k| k[:hand] == hand && k[:row] == row && k[:col] == col }
  end

  it 'プロファイルの名前と dir、読めたら status: ok' do
    expect(snapshot).to include(profileId: opened.id, name: 'profile', dir: 'profile', status: 'ok')
  end

  it 'files は設定ファイルの版で、知っている版（workbench.versions）もそれにする' do
    expect(snapshot[:files]).to include('metadata.yaml' => version('metadata.yaml'),
                                        'layers/0_layer_0.yaml' => version('layers/0_layer_0.yaml'),
                                        'combos/00_combo.yaml' => version('combos/00_combo.yaml'))
    expect(workbench.versions(opened.id)).to eq(snapshot[:files])
  end

  it '読み直すと知っている版を置き換える（消えたファイルは残さない）' do
    described_class.new(workbench).call(opened.id)
    File.delete(File.join(@root, 'profile', 'combos/03_combo.yaml'))
    write('layers/1_layer_1.yaml', File.read(File.join(@root, 'profile', 'layers/1_layer_1.yaml')).sub('Layer 1', 'Renamed'))
    again = described_class.new(workbench).call(opened.id)
    expect(workbench.versions(opened.id)).not_to have_key('combos/03_combo.yaml')
    expect(workbench.versions(opened.id)['layers/1_layer_1.yaml']).to eq(version('layers/1_layer_1.yaml'))
    expect(again[:layers][1][:name]).to eq('Renamed')
  end

  it 'settings/qmk_settings.yaml がなければ files に null で入れ、設定の value は null' do
    File.delete(File.join(@root, 'profile', 'settings/qmk_settings.yaml'))
    expect(snapshot[:files]).to include('settings/qmk_settings.yaml' => nil)
    expect(snapshot[:settings].map { |s| s[:value] }.uniq).to eq([nil])
    expect(snapshot[:settings].first[:address]).to eq(file: 'settings/qmk_settings.yaml', path: %w[vial combo_timing_window])
  end

  it 'settings は data/qmk_settings.yaml のすべてを順に返し、真偽値は true / false' do
    catalog = Cornix::Mapping::QmkSettingCatalog.default
    expect(snapshot[:settings].map { |s| s[:name] }).to eq(catalog.all.map(&:name))
    permissive = snapshot[:settings].find { |s| s[:name] == 'permissive_hold' }
    expect(permissive).to include(type: 'boolean', value: true, default: false, group: 'keyboard')
    expect(permissive[:description]).to be_a(String)
  end

  it '名前の形で書いた設定は [group, name] を Address にする' do
    write('settings/qmk_settings.yaml', "keyboard:\n  tapping_term: 180\n")
    tapping = snapshot[:settings].find { |s| s[:name] == 'tapping_term' }
    expect(tapping).to include(value: 180, address: { file: 'settings/qmk_settings.yaml', path: %w[keyboard tapping_term] })
  end

  it 'keys は position_map のすべての位置。割り当てのない位置は value: nil で Address だけ' do
    write('layers/0_layer_0.yaml', <<~YAML)
      name: Base
      index: 0
      mapping:
        left_hand:
          row0: { tab: "LT1(KC_SPACE)" }
          row1:
          row2:
          row3:
          thumb_keys:
        right_hand:
          row0:
          row1:
          row2:
          row3:
          thumb_keys:
    YAML
    keys = snapshot[:layers][0][:keys]
    expect(keys.size).to eq(48)
    expect(keys.count { |k| k[:value] }).to eq(1)
    expect(key(snapshot, 0, 'left', 0, 0)[:value]).to eq(
      text: 'LT1(KC_SPACE)', canonical: 'LT1(Space)', code: 0x412C, kind: 'layerTap',
      display: { label: 'Space', tap: 'Space', hold: 'L1' }
    )
    expect(key(snapshot, 0, 'right', 3, 5)).to eq(
      hand: 'right', row: 3, col: 5, value: nil,
      address: { file: 'layers/0_layer_0.yaml', path: %w[mapping right_hand thumb_keys right] }
    )
    expect(snapshot[:layers][0][:encoders][:right][:cw]).to eq(
      address: { file: 'layers/0_layer_0.yaml', path: %w[mapping encoders right cw] }, value: nil
    )
  end

  it 'エンコーダの注記付きの形は key の表記と note' do
    text = File.read(File.join(@root, 'profile', 'layers/0_layer_0.yaml'))
    write('layers/0_layer_0.yaml', text.sub('push: Mute', 'push: { key: KC_MUTE, note: ミュート }'))
    push = snapshot[:layers][0][:encoders][:left][:push]
    expect(push[:value]).to include(text: 'KC_MUTE', canonical: 'Mute', note: 'ミュート')
    expect(push[:address][:path]).to eq(%w[mapping encoders left push])
  end

  it 'positionMap は論理位置とグループ・記号' do
    expect(snapshot[:positionMap].size).to eq(48)
    expect(snapshot[:positionMap][21]).to eq(hand: 'left', row: 3, col: 3, group: 'thumb_keys', symbol: 'left',
                                             address: { file: 'position_map.yaml', path: ['left_hand', 'thumb_keys', 0] })
  end

  it 'references はレイヤー・マクロ・タップダンス・自分のショートカット（ファイルに書いた表記）' do
    write('shortcuts.yaml', "shortcuts:\n  前のタブへ: Command + Shift + [\n")
    refs = snapshot[:references]
    expect(refs[:layers].first).to eq(index: 0, name: 'Layer 0')
    expect(refs[:macros].first).to eq(index: 0, name: 'Macro 0', icon: nil)
    expect(refs[:tapDances].first).to eq(index: 0, name: 'TapDance 0')
    expect(refs[:shortcuts]).to eq([{ name: '前のタブへ', text: 'Command + Shift + [' }])
  end

  it '構造検証で読めなければ status: invalid、diagnostics だけ（注記付きの形の .key は Address に付けない）' do
    text = File.read(File.join(@root, 'profile', 'layers/0_layer_0.yaml'))
    write('layers/0_layer_0.yaml', text.sub('tab: Tab', 'tab: { key: Unknown, note: x }'))
    expect(snapshot).to include(status: 'invalid', layers: [], settings: [], metadata: {}, positionMap: [])
    expect(snapshot[:files]).to include('layers/0_layer_0.yaml' => version('layers/0_layer_0.yaml'))
    diagnostic = snapshot[:diagnostics].then { |list| expect(list.size).to eq(1); list.first }
    expect(diagnostic).to include(severity: 'error', source: 'structure',
                                  address: { file: 'layers/0_layer_0.yaml', path: %w[mapping left_hand row0 tab] })
    expect(diagnostic[:range]).to eq(start: { line: 7, character: 18 }, end: { line: 7, character: 25 })
  end

  it 'YAML として読めないファイルは file だけ' do
    write('macros/00_macro.yaml', "index: [\n")
    diagnostic = snapshot[:diagnostics].then { |list| expect(list.size).to eq(1); list.first }
    expect(diagnostic).to include(source: 'structure', file: 'macros/00_macro.yaml')
    expect(diagnostic).not_to have_key(:address)
  end

  it '意味検証の結果は Address と range 付き。一覧全体の問題は file に "<ディレクトリ>/"' do
    text = File.read(File.join(@root, 'profile', 'layers/0_layer_0.yaml'))
    write('layers/0_layer_0.yaml', text.sub('Q: Q', 'Q: Macro(20)'))
    33.times { |i| write(format('macros/%02d_extra.yaml', 40 + i), "index: #{40 + i}\nname: Extra #{i}\nsequence: [{ action: tap, keys: A }]\n") }
    diagnostics = snapshot[:diagnostics]
    expect(diagnostics).to include(
      { severity: 'error', source: 'semantic', message: 'マクロ M20 が定義されていません',
        address: { file: 'layers/0_layer_0.yaml', path: %w[mapping left_hand row0 Q] },
        range: { start: { line: 8, character: 9 }, end: { line: 8, character: 18 } } },
      a_hash_including(severity: 'error', source: 'semantic', file: 'macros/')
    )
  end
end
