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

  it '読める表記は KeyValue と説明（最後の行は 16bit 値）' do
    result = inspect_text('Cmd + Shift + P')
    expect(result[:value]).to eq(text: 'Cmd + Shift + P', canonical: 'Shift + Command + P', code: 0x0A13, kind: 'modified',
                                 display: { label: '⇧⌘P' })
    expect(result[:diagnostics]).to eq([])
    expect(result[:description]).to eq(title: 'Shift + Command + P', lines: ['16bit 値: 0x0A13'])
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
      lines: ['フレーム', '同梱のショートカット: Figma:ツール:フレームツール', 'tap: F', '16bit 値: 0x770C']
    )
  end

  it '自分のショートカットは origin: shortcut でアイコンなし。説明は中身の表記' do
    write('shortcuts.yaml', "shortcuts:\n  前のタブへ: Command + Shift + [\n")
    result = inspect_text("Shortcut('前のタブへ')")
    expect(result[:value]).to include(origin: 'shortcut')
    expect(result[:value]).not_to have_key(:icon)
    expect(result[:description]).to eq(title: 'ショートカット 前のタブへ', lines: ['Shift + Command + [', '16bit 値: 0x0A2F'])
  end

  it 'Mod-Tap はタップとホールド、レイヤー操作は行き先のレイヤー' do
    expect(inspect_text('RSFT_T(KC_UP)')[:description][:lines]).to eq(['タップ: Up', 'ホールド: R⇧', '16bit 値: 0x3252'])
    expect(inspect_text('MO(1)')[:description][:lines]).to eq(['レイヤー 1（Layer 1）', '16bit 値: 0x5221'])
  end

  it '構造検証で読めないプロファイルでは意味検証をしない（キーの表記は読める）' do
    write('layers/0_layer_0.yaml', "name: Broken\nindex: 0\nmapping: 1\n")
    result = inspect_text('Macro(20)')
    expect(result[:value]).to include(kind: 'macro')
    expect(result[:diagnostics]).to eq([])
  end

  it '知らない context は Candidates::UnknownContext' do
    expect { inspect_text('A', context: 'comboTrigger') }.to raise_error(Cornix::Application::Editor::Candidates::UnknownContext)
  end
end
