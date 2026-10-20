# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'tmpdir'

RSpec.describe Cornix::Application::Editor::Inspect do
  around do |example|
    Dir.mktmpdir('cornix-inspect') do |dir|
      @root = File.realpath(dir)
      FileUtils.cp_r(File.join(__dir__, '../../fixtures/test_config'), File.join(@root, 'profile'))
      example.run
    end
  end

  let(:workbench) { Cornix::Application::Editor::Workbench.new(root: @root) }
  let(:id) { workbench.open('profile').id }

  def write(rel, text)
    path = File.join(@root, 'profile', rel)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, text)
  end

  def inspect_text(text, context: 'layerKey') = described_class.new(workbench).call(id, context: context, text: text)

  it '読める表記は KeyValue と説明（最後の行は QMK の名前と 16bit 値）' do
    result = inspect_text('Cmd + Shift + P')
    expect(result[:value]).to eq(text: 'Cmd + Shift + P', canonical: 'Shift + Command + P', code: 0x0A13, kind: 'modified',
                                 display: { label: '⇧⌘P' })
    expect(result[:diagnostics]).to eq([])
    expect(result[:description]).to eq(title: 'Shift + Command + P', lines: ['QMK: LSG(KC_P)（0x0A13）'])
  end

  it '読めない表記は value / description が nil で構造の error' do
    result = inspect_text('Nope')
    expect(result).to include(value: nil, description: nil)
    expect(result[:diagnostics]).to match([{ severity: 'error', source: 'structure', message: a_string_including('Nope') }])
  end

  it '意味検証の規則（参照先・レイヤーの範囲・未定義のレイヤー）を返す' do
    expect(inspect_text('TD(9)')[:diagnostics]).to eq(
      [{ severity: 'error', source: 'semantic', message: 'タップダンス TD(9) が定義されていません' }]
    )
    expect(inspect_text('MO(12)')[:diagnostics].map { |d| d[:severity] }).to eq(['error'])
    File.delete(File.join(@root, 'profile', 'layers/9_layer_9.yaml'))
    expect(inspect_text('TG(9)')[:diagnostics]).to eq(
      [{ severity: 'warning', source: 'semantic', message: 'レイヤー 9 が定義されていません' }]
    )
    expect(inspect_text('Macro(0)')[:diagnostics]).to eq([])
  end

  # inspect はコンボの出力に置いて検証する。規則がキーの場所によって変わったら（Domain にコンボの出力だけの規則が足されたなど）ここで気づく
  it '意味検証の結果は、同じ値をレイヤーのキーに置いたときの Profile#diagnostics と同じ' do
    File.delete(File.join(@root, 'profile', 'layers/9_layer_9.yaml'))
    env = workbench.fetch(id).env
    profile = env.repository.load
    position = profile.position_map.positions.first
    path = "layers[0].#{profile.position_map.path(position)}"
    ['A', 'Macro(0)', 'M20', 'TD(1)', 'TD(9)', 'MO(1)', 'TG(9)', 'MO(12)', 'LT9(A)', 'LM(11, MOD_LSFT)', 'Repeat', 'QK_BOOT', '0x7E40'].each do |text|
      keycode = env.notation.parse(text)
      layer = profile.layers.first
      placed = profile.with(layers: [layer.with(keys: layer.keys.merge(position => keycode))] + profile.layers.drop(1))
      expected = placed.diagnostics(env.capabilities).select { |d| d.path == path }
                       .map { |d| { severity: d.severity.to_s, message: d.message, source: 'semantic' } }
      expect(inspect_text(text)[:diagnostics]).to eq(expected), text
    end
  end

  it 'コンボの件数の上限などプロファイル全体の問題は混ぜない' do
    32.times { |i| write(format('combos/%02d_extra.yaml', 10 + i), "index: #{10 + i}\nname: Extra #{i}\ntrigger_keys: [A, B]\noutput_key: C\n") }
    expect(inspect_text('A')[:diagnostics]).to eq([])
  end

  it 'マクロの説明は説明文・preset の名前・手順' do
    write('macros/12_frame.yaml', "index: 12\npreset: 'Figma:ツール:フレームツール'\ndescription: フレーム\n")
    result = inspect_text('Macro(12)')
    expect(result[:value]).to include(canonical: "Macro('Figma:ツール:フレームツール')", origin: 'presetMacro', icon: 'simple-icons:figma')
    expect(result[:description]).to eq(
      title: 'マクロ Figma:ツール:フレームツール（M12）',
      lines: ['フレーム', '同梱のショートカット: Figma:ツール:フレームツール', 'tap: F', 'QMK: QK_MACRO_12（0x770C）']
    )
  end

  it '自分のショートカットは origin: shortcut でアイコンなし。説明は中身の表記' do
    write('shortcuts.yaml', "shortcuts:\n  前のタブへ: Command + Shift + [\n")
    result = inspect_text("Shortcut('前のタブへ')")
    expect(result[:value]).to include(origin: 'shortcut')
    expect(result[:value]).not_to have_key(:icon)
    expect(result[:description]).to eq(title: 'ショートカット 前のタブへ', lines: ['Shift + Command + [', 'QMK: LSG(KC_LEFT_BRACKET)（0x0A2F）'])
  end

  it 'Mod-Tap はタップとホールド、レイヤー操作は行き先のレイヤー' do
    expect(inspect_text('RSFT_T(KC_UP)')[:description][:lines]).to eq(['タップ: Up', 'ホールド: R⇧', 'QMK: RSFT_T(KC_UP)（0x3252）'])
    expect(inspect_text('MO(1)')[:description][:lines]).to eq(['レイヤー 1（Layer 1）', 'QMK: MO(1)（0x5221）'])
  end

  it '名前にできない値（Cornix の表にない Raw、QMK に名前のないマクロの番号）は最後の行が 16bit 値だけ' do
    expect(inspect_text('0x5C00')[:description][:lines]).to eq(['16bit 値: 0x5C00'])
    expect(inspect_text('0x7E40')[:description][:lines]).to eq(['16bit 値: 0x7E40']) # QMK では QK_USER_0 だが Cornix の表にない
    expect(inspect_text('M40')[:description][:lines].last).to eq('16bit 値: 0x7728')
  end

  it 'タップダンスの説明は動作ごとの行と tapping_term だけ（設定ファイルの description は動作の行と重なるので出さない）' do
    write('tap_dance/03_tab_escape.yaml', "index: 3\nname: Tab Escape\ndescription: タップで Tab、長押しで Escape\non_tap: Tab\non_hold: Escape\ntapping_term: 200\n")
    expect(inspect_text("TapDance('Tab Escape')")[:description]).to eq(
      title: 'タップダンス Tab Escape（TD(3)）',
      lines: ['タップ: Tab', 'ホールド: Escape', 'tapping_term: 200ms', 'QMK: TD(3)（0x5703）']
    )
  end

  it '構造検証で読めないプロファイルでは意味検証をしない（キーの表記は読める）' do
    write('layers/0_layer_0.yaml', "name: Broken\nindex: 0\nmapping: 1\n")
    result = inspect_text('Macro(20)')
    expect(result[:value]).to include(kind: 'macro')
    expect(result[:diagnostics]).to eq([])
  end

  it 'macroKey はマクロのファイルと同じく名前参照を読まず、正規形も名前参照を使わない' do
    result = inspect_text("Macro('Macro 0')", context: 'macroKey')
    expect(result[:value]).to be_nil
    expect(result[:diagnostics]).to match([{ severity: 'error', source: 'structure', message: a_string_including('Macro 0') }])
    expect(inspect_text('Macro(0)', context: 'macroKey')[:value]).to include(canonical: 'M0', kind: 'macro')
    expect(inspect_text('Macro(0)', context: 'layerKey')[:value]).to include(canonical: "Macro('Macro 0')")
  end

  it 'shortcutValue は Shortcut(...) を読まない（読み込みと同じ文）' do
    write('shortcuts.yaml', "shortcuts:\n  前のタブへ: Command + Shift + [\n")
    result = inspect_text("Shortcut('前のタブへ')", context: 'shortcutValue')
    expect(result[:value]).to be_nil
    expect(result[:diagnostics].first[:message]).to eq("shortcuts.yaml の値には Shortcut(...) は書けません: Shortcut('前のタブへ')")
    expect(inspect_text("Macro('Macro 0')", context: 'shortcutValue')[:value]).to include(canonical: "Macro('Macro 0')")
  end

  it 'v0.2 のほかの context はレイヤーのキーと同じ読み方' do
    %w[tapDanceAction comboTrigger comboOutput].each do |context|
      expect(inspect_text("TapDance('TapDance 1')", context: context)[:value]).to include(kind: 'tapDance')
    end
  end

  it '知らない context は UnknownContext' do
    expect { inspect_text('A', context: 'unknown') }.to raise_error(Cornix::Application::Editor::UnknownContext)
  end
end
