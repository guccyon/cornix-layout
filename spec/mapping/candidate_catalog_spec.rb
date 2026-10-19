# frozen_string_literal: true

require 'spec_helper'
require 'yaml'

RSpec.describe Cornix::Mapping::CandidateCatalog do
  subject(:candidates) { described_class.new }

  let(:notation) { Cornix::Mapping::KeycodeNotation.new }

  # profile/open の references と同じ形（layers / macros / tapDances / shortcuts）→ [References, layer_names]
  def profile_references(table)
    table ||= {}
    shortcuts = Array(table['shortcuts']).to_h { |s| [s['name'], notation.parse(s['text'])] }
    references = Cornix::Mapping::References.new(
      macros: Array(table['macros']).to_h { |m| [m['name'], m['index']] },
      tap_dances: Array(table['tapDances']).to_h { |t| [t['name'], t['index']] },
      shortcuts: shortcuts,
      preset_shortcuts: Cornix::Mapping::ShortcutCatalog.default.library(notation).entries
    )
    [references, Array(table['layers']).to_h { |l| [l['index'], l['name']] }]
  end

  def search(query, context: 'layerKey', references: Cornix::Mapping::References::NONE, layer_names: {}, limit: 50)
    candidates.search(query: query, context: context, references: references, layer_names: layer_names, limit: limit)
  end

  # spec/fixtures/candidates/*.yaml: 「この入力ならこの候補」（ADR 004。TypeScript 版も同じデータを読む）。
  # 形と判定の規則は spec/fixtures/candidates/README.md
  describe 'spec/fixtures/candidates' do
    Dir[File.join(__dir__, '..', 'fixtures', 'candidates', '*.yaml')].sort.each do |path|
      YAML.safe_load_file(path, aliases: true).each do |item|
        it "#{File.basename(path)}: #{item['context']} #{item['query'].inspect}" do
          references, layer_names = profile_references(item['references'])
          result = search(item['query'], context: item['context'], references: references, layer_names: layer_names,
                                         limit: item.fetch('limit', 50))
          texts = result.items.map(&:insert_text)
          expect(texts.first(item['expect'].size)).to eq(item['expect'])
          expect(texts).to be_empty if item['expect'].empty?
          expect(texts & Array(item['absent'])).to be_empty
          (item['warning'] || {}).each do |text, reason|
            expect(result.items.find { |c| c.insert_text == text }&.warning).to eq(reason)
          end
          (item['category'] || {}).each do |text, category|
            categories = result.items.select { |c| c.insert_text == text }.map(&:category)
            expect(categories).not_to be_empty
            expect(categories).to all(eq(category))
          end
        end
      end
    end
  end

  describe '#search' do
    it '候補の形（label・detail・category）' do
      lgui = search('Cmd').items.first
      expect(lgui).to have_attributes(insert_text: 'LGui', label: 'LGui', category: 'modifier', icon: nil, warning: nil)
      expect(lgui.detail).to include('Cmd', 'KC_LGUI')
    end

    it '同梱のショートカットは名前の形で、detail にアプリ・カテゴリ・表記、icon に icon_for の結果' do
      catalog = described_class.new(icon_for: ->(app) { "test:#{app}" })
      references, = profile_references(nil)
      item = catalog.search(query: 'コマンドパレット', context: 'layerKey', references: references).items.first
      expect(item).to have_attributes(
        insert_text: "Shortcut('VS Code:基本操作:コマンドパレット')", label: 'コマンドパレット',
        detail: 'VS Code › 基本操作 · Shift + Command + P', category: 'presetShortcut', icon: 'test:VS Code'
      )
    end

    it 'レイヤー操作の detail はレイヤーの名前' do
      item = search('MO(1)', layer_names: { 1 => 'Symbols' }).items.first
      expect(item).to have_attributes(insert_text: 'MO(1)', detail: 'Symbols', category: 'layer')
    end

    it 'マクロ・タップダンス・ショートカットは名前を label に、番号や中身を detail に' do
      references, = profile_references(
        'macros' => [{ 'index' => 0, 'name' => 'Bracket Pair' }], 'tapDances' => [{ 'index' => 4, 'name' => 'Tab Escape' }],
        'shortcuts' => [{ 'name' => '前のタブへ', 'text' => 'Command + Shift + [' }]
      )
      items = %w[Bracket Tab\ Escape 前のタブ].map { |q| search(q, references: references).items.first }
      expect(items.map { |c| [c.label, c.detail, c.category] }).to eq(
        [['Bracket Pair', 'M0', 'macro'], ['Tab Escape', 'TD(4)', 'tapDance'], ['前のタブへ', 'Shift + Command + [', 'shortcut']]
      )
    end

    it '書き込み禁止のキーは query が空でも出さない' do
      texts = search('', limit: 10_000).items.map(&:insert_text)
      expect(texts).not_to include('Reset', 'Reboot', 'ClearEEPROM')
      expect(texts).to include('NoKey', 'Trans', 'BT0')
    end

    it '対応していないキーは一致の強さにかかわらず最後に並べる' do
      items = search('', limit: 10_000).items
      first_unsupported = items.index(&:warning)
      expect(items[first_unsupported..].map(&:warning)).to all(be_a(String))
    end

    it 'insert_text はどれも KeycodeNotation で読めて、キーの表の候補は正規形のまま' do
      references, layer_names = profile_references(
        'layers' => [{ 'index' => 1, 'name' => 'Symbols' }], 'macros' => [{ 'index' => 0, 'name' => 'Bracket Pair' }]
      )
      search('', references: references, layer_names: layer_names, limit: 10_000).items.each do |item|
        keycode = notation.parse(item.insert_text, references: references)
        next if item.category == 'presetShortcut' || item.category == 'macro'

        expect(notation.format(keycode)).to eq(item.insert_text)
      end
    end

    it 'Shortcut(...) を使えない references（既定の NONE）では shortcut / presetShortcut を出さない' do
      none = search('コマンドパレット').items
      expect(none).to be_empty
      references, = profile_references('shortcuts' => [{ 'name' => 'コピー', 'text' => 'Command + C' }])
      usable = search('コ', references: references, limit: 10_000).items.map(&:category).uniq
      expect(usable).to include('shortcut', 'presetShortcut')
    end

    it "名前に ' や \" を含むショートカットも、insert_text を読むと同じ定義になる" do
      names = ["Don't", 'Say "Hi"', %q(It's "ok")]
      references = Cornix::Mapping::References.new(shortcuts: names.to_h { |n| [n, notation.parse('Command + C')] })
      names.each do |name|
        item = search(name, references: references).items.find { |c| c.label == name }
        expect(notation.parse(item.insert_text, references: references)).to eq(notation.parse('Command + C'))
      end
    end

    it 'warning は data/unsupported_keycodes.yaml の reason（範囲内のすべての名前のある値で）' do
      catalog = Cornix::Mapping::KeycodeCatalog.default
      ranges = YAML.safe_load_file(File.join(Cornix::DATA_DIR, 'unsupported_keycodes.yaml'))['ranges']
      items = search('', limit: 10_000).items.to_h { |c| [c.insert_text, c] }
      ranges.each do |range|
        (range['from']..range['to']).each do |code|
          next unless catalog.name(code)

          text = notation.format(notation.codec.decode(code))
          expect(items.fetch(text).warning).to eq(range['reason'])
        end
      end
    end

    it 'detail の別名は 3 個まで + QMK 名' do
      expect(search('Cmd').items.first.detail).to eq('LCmd · LWin · LCommand · KC_LGUI')
    end

    it 'limit は 1 未満なら 1' do
      expect(search('', limit: 0).items.size).to eq(1)
      expect(search('', limit: -1).items.size).to eq(1)
    end

    it 'limit で切ったら truncated' do
      result = search('', limit: 3)
      expect(result.items.size).to eq(3)
      expect(result.truncated).to be(true)
      expect(search('Cmd').truncated).to be(false)
    end

    it '知らない context は ArgumentError' do
      expect { search('A', context: 'macroKey') }.to raise_error(ArgumentError, /context/)
      expect(candidates.contexts).to eq(%w[layerKey encoder])
    end
  end

  describe '#shortcut_tree' do
    subject(:tree) { described_class.new(icon_for: ->(app) { app == 'VS Code' ? 'material-icon-theme:vscode' : nil }).shortcut_tree }

    it 'アプリ → カテゴリ → ラベル。1 シーケンスは Shortcut の名前の形、macro: の定義は preset: の名前' do
      vscode = tree.find { |app| app[:name] == 'VS Code' }
      expect(vscode[:icon]).to eq('material-icon-theme:vscode')
      basic = vscode[:categories].find { |c| c[:name] == '基本操作' }
      expect(basic[:items]).to include(
        { label: 'コマンドパレット', insert_text: "Shortcut('VS Code:基本操作:コマンドパレット')", text: 'Shift + Command + P',
          macro: false },
        { label: 'キーボードショートカット', insert_text: 'VS Code:基本操作:キーボードショートカット', text: nil, macro: true }
      )
    end

    it '同梱のすべての定義を 1 回ずつ含む' do
      catalog = Cornix::Mapping::ShortcutCatalog.default
      count = tree.sum { |app| app[:categories].sum { |c| c[:items].size } }
      expect(count).to eq(catalog.preset_names.size)
    end
  end

  describe Cornix::Mapping::CandidateCatalog::Categories do
    let(:catalog) { Cornix::Mapping::KeycodeCatalog.default }

    it 'data/keycode_categories.yaml のキーはどれも keycodes.yaml の name' do
      expect(described_class.load.names).to all(satisfy { |name| catalog.name(catalog.code_for_name(name).to_i) == name })
    end

    it '書いていないキーは keycodes.yaml の節で分類する' do
      categories = described_class.load
      expect(categories.category('KC_A', :basic)).to eq('basic')
      expect(categories.category('KC_LGUI', :basic)).to eq('modifier')
      expect(categories.category('QK_REPEAT_KEY', :quantum)).to eq('special')
      expect(categories.category(nil, :modified)).to eq('basic')
    end

    it '形の誤りは ConfigError' do
      base = { categories: { 'media' => ['KC_VOLU'] }, defaults: { 'special' => 'special', 'basic' => 'basic',
                                                                      'quantum' => 'special', 'modified' => 'basic' },
               order: %w[basic media special], contexts: { 'layerKey' => { 'prefer' => { 'categories' => ['basic'] } } } }
      expect { described_class.new(**base) }.not_to raise_error
      expect { described_class.new(**base, categories: { 'media' => ['KC_VOLU'], 'basic' => ['KC_VOLU'] }) }
        .to raise_error(Cornix::ConfigError, /2 つの分類/)
      expect { described_class.new(**base, order: %w[basic special]) }.to raise_error(Cornix::ConfigError, /order/)
      expect { described_class.new(**base, defaults: { 'basic' => 'basic' }) }.to raise_error(Cornix::ConfigError, /defaults/)
    end
  end
end
