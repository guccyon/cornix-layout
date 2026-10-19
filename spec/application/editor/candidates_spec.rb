# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'tmpdir'

RSpec.describe Cornix::Application::Editor::Candidates do
  around do |example|
    Dir.mktmpdir('cornix-candidates') do |dir|
      @root = File.realpath(dir)
      FileUtils.cp_r(File.join(__dir__, '../../fixtures/test_config'), File.join(@root, 'profile'))
      example.run
    end
  end

  let(:workbench) { Cornix::Application::Editor::Workbench.new(root: @root) }
  let(:id) { workbench.open('profile').id }
  let(:candidates) { described_class.new(workbench) }

  def write(rel, text)
    path = File.join(@root, 'profile', rel)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, text)
  end

  def search(query, context: 'layerKey', limit: nil) = candidates.call(id, context: context, query: query, limit: limit)

  it '候補は protocol.md の Candidate の形（nil の項目は省く）' do
    item = search('Escape', limit: 1)[:items].first
    expect(item).to eq(insertText: 'Escape', label: 'Escape', detail: 'Esc · KC_ESCAPE', category: 'basic')
  end

  it 'limit を省くと 50 件で切り、truncated' do
    result = search('')
    expect(result[:items].size).to eq(described_class::DEFAULT_LIMIT)
    expect(result[:truncated]).to be(true)
    expect(result[:typed]).to be_nil
  end

  it 'プロファイルのレイヤーの名前・マクロ・タップダンスを候補にする' do
    expect(search('Layer 1', limit: 1)[:items].first).to include(insertText: 'MO(1)', detail: 'Layer 1', category: 'layer')
    expect(search('Macro 0', limit: 1)[:items].first).to include(insertText: "Macro('Macro 0')", category: 'macro')
    expect(search('TapDance 2', limit: 1)[:items].first).to include(insertText: "TapDance('TapDance 2')", category: 'tapDance')
  end

  it '自分のショートカットはアイコンなし、preset: のマクロは元のアプリのアイコン' do
    write('shortcuts.yaml', "shortcuts:\n  前のタブへ: Command + Shift + [\n")
    write('macros/12_frame.yaml', "index: 12\npreset: 'Figma:ツール:フレームツール'\n")
    expect(search('前のタブへ', limit: 1)[:items].first).to eq(
      insertText: "Shortcut('前のタブへ')", label: '前のタブへ', detail: 'Shift + Command + [', category: 'shortcut'
    )
    expect(search('フレームツール')[:items]).to include(
      { insertText: "Macro('Figma:ツール:フレームツール')", label: 'Figma:ツール:フレームツール', detail: 'M12',
        category: 'macro', icon: 'simple-icons:figma' }
    )
  end

  it 'typed は query をそのまま表記として読めたときの KeyValue（Shortcut(...) なら origin とアイコン）' do
    typed = search("Shortcut('Figma:ツール:移動ツール')")[:typed]
    expect(typed).to include(text: "Shortcut('Figma:ツール:移動ツール')", canonical: 'V', origin: 'presetShortcut',
                             icon: 'simple-icons:figma')
    expect(search('Unknown(')[:typed]).to be_nil
  end

  it '構造検証で読めないプロファイルでも、キーの表と同梱のショートカットは引ける' do
    write('layers/0_layer_0.yaml', "name: Broken\nindex: 0\nmapping: 1\n")
    expect(search('Escape', limit: 1)[:items].first[:insertText]).to eq('Escape')
    expect(search('コマンドパレット')[:items].map { |i| i[:category] }).to include('presetShortcut')
    expect(search('Layer 1')[:items].map { |i| i[:category] }).not_to include('layer')
  end

  it '知らない context は UnknownContext' do
    expect { search('A', context: 'macroKey') }
      .to raise_error(Cornix::Application::Editor::UnknownContext) { |e| expect(e.context).to eq('macroKey') }
  end

  it '開いていない id は ProfileNotFound' do
    expect { candidates.call('p9', context: 'layerKey', query: 'A') }.to raise_error(Cornix::Application::Editor::ProfileNotFound)
  end

  describe '#shortcut_tree' do
    let(:tree) { described_class.new(workbench).shortcut_tree }

    it 'アプリごとのアイコンとカテゴリ。すべてのアプリにアイコンがある' do
      apps = tree[:apps]
      expect(apps.map { |a| a[:name] }).to include('VS Code', 'Figma')
      expect(apps.find { |a| a[:name] == 'VS Code' }[:icon]).to eq('material-icon-theme:vscode')
      expect(apps.map { |a| a[:icon] }).to all(be_a(String))
    end

    it '1 シーケンスは Shortcut(...) と text、複数の手順は macro: true で preset: の名前（text は省く）' do
      items = tree[:apps].flat_map { |a| a[:categories] }.flat_map { |c| c[:items] }
      expect(items).to include(
        { label: 'コマンドパレット', insertText: "Shortcut('VS Code:基本操作:コマンドパレット')", text: 'Shift + Command + P', macro: false }
      )
      macro = items.find { |i| i[:macro] }
      expect(macro).not_to have_key(:text)
      expect(macro[:insertText]).not_to start_with('Shortcut(')
    end
  end
end
