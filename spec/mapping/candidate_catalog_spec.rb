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
      expect { search('A', context: 'unknown') }.to raise_error(ArgumentError, /context/)
      expect(candidates.contexts).to eq(%w[layerKey encoder macroKey tapDanceAction comboTrigger comboOutput shortcutValue])
    end

    describe 'v0.2 の context（protocol.md の 12.4）' do
      let(:references) do
        Cornix::Mapping::References.new(macros: { 'Bracket Pair' => 0 }, tap_dances: { 'Tab Escape' => 4 },
                                        shortcuts: { '前のタブへ' => notation.parse('Command + Shift + [') },
                                        preset_shortcuts: Cornix::Mapping::ShortcutCatalog.default.library(notation).entries)
      end

      def categories_of(query, context, **options)
        candidates.search(query: query, context: context, references: references, layer_names: { 1 => 'Symbols' },
                          limit: 500, **options).items.map(&:category).uniq
      end

      it 'macroKey と comboTrigger はレイヤー操作・マクロ・タップダンス・ショートカットを出さず、all: true なら出す' do
        %w[macroKey comboTrigger].each do |context|
          expect(categories_of('', context)).not_to include('layer', 'macro', 'tapDance', 'shortcut', 'presetShortcut')
        end
        expect(categories_of('', 'macroKey', all: true)).to include('layer', 'macro', 'tapDance', 'shortcut')
        expect(categories_of('', 'layerKey')).to include('layer', 'macro', 'tapDance', 'shortcut', 'presetShortcut')
      end

      it 'shortcutValue は Shortcut(...) を出さない' do
        expect(categories_of('', 'shortcutValue')).not_to include('shortcut', 'presetShortcut')
        expect(categories_of('', 'shortcutValue')).to include('macro', 'tapDance')
      end

      it 'format_references で候補の表記を変える（マクロの手順のキーでは M0 / TD(4)、label は名前のまま）' do
        items = candidates.search(query: 'Bracket Pair', context: 'macroKey', references: references, all: true,
                                  format_references: Cornix::Mapping::References::NONE).items
        expect(items.first.to_h).to include(insert_text: 'M0', label: 'Bracket Pair', category: 'macro')
      end

      it 'exclude はその 16bit 値と同じ候補を除く' do
        td = Cornix::Mapping::KeycodeCodec.new.encode(Cornix::Domain::Keycode::TapDanceCall.new(index: 4))
        texts = ->(**o) { candidates.search(query: 'Tab', context: 'tapDanceAction', references: references, **o).items.map(&:insert_text) }
        expect(texts.call).to include("TapDance('Tab Escape')")
        expect(texts.call(exclude: td)).not_to include("TapDance('Tab Escape')")
        expect(texts.call(exclude: 0x2B)).not_to include('Tab')
      end

      it '上に出すものどうしは書いた順（comboOutput はマクロを基本キーより先に）' do
        items = candidates.search(query: '', context: 'comboOutput', references: references, limit: 2).items
        expect(items.map(&:category)).to eq(%w[macro basic])
      end

      it 'comboTrigger は base_codes の値を上に出す（ほかの context では効かない）' do
        base = [0x14, 0x04] # Q, A
        first = ->(context) { candidates.search(query: '', context: context, base_codes: base, limit: 2).items.map(&:insert_text) }
        expect(first.call('comboTrigger')).to eq(%w[A Q])
        expect(first.call('layerKey')).to eq(%w[A B])
      end
    end

    describe 'あいまい一致（protocol.md の 13.3）' do
      def texts(query, **options) = search(query, **options).items.map(&:insert_text)

      it '前方一致・部分一致のあとに、query の文字を順に含むものを出す' do
        # Tab は完全一致、TapDance などがなければ残りは t・a・b を順に含むもの（VerticalBar・LeftAngleBracket など）
        expect(texts('tab')).to eq(['Tab', '|', '<', '>', 'ToggleBackslashBackspace'])
        expect(texts('lbrkt')).to eq(['[', '<', '>'])
      end

      it '大文字小文字・_・空白は区別しない' do
        expect(texts('KC_L BRACKET').first).to eq('[')
        expect(texts('kcl_brkt').first).to eq('[')
        expect(texts('KC U P').first).to eq('Up')
      end

      it '飛ばした文字の少ないものを上に（前に付いた KC_ などは数えない）' do
        # kc up: KC_UP は 0 文字、KC_PGUP・KC_MS_UP は 2 文字飛ばす
        expect(texts('kc up', limit: 3)).to eq(%w[Up PageUp MouseUp])
      end

      it '順に含まなければ出さない。_ や空白だけの query はあいまい一致に使わない' do
        expect(texts('brktl')).to be_empty
        expect(texts('_ _')).to be_empty
      end
    end

    describe 'よく使うキーを上に（usage）' do
      def texts(query, limit: 50, **options)
        candidates.search(query: query, context: 'layerKey', limit: limit, **options).items.map(&:insert_text)
      end

      it '当てはまり方が同じ候補の中で、usage の回数の多いものを上に（同じ回数なら今の並び）' do
        expect(texts('', limit: 4)).to eq(%w[A B C D])
        expect(texts('', limit: 4, usage: { 0x06 => 2, 0x05 => 5 })).to eq(%w[B C A D])
        # | は 3 文字、< と > は 5 文字飛ばす。よく使う > は飛ばした数が同じ < の上に出るが、| は越えない
        expect(texts('tab', usage: { 0x237 => 3 })).to eq(['Tab', '|', '>', '<', 'ToggleBackslashBackspace'])
      end

      it '当てはまり方が先（よく使うあいまい一致のキーより、完全一致のキーが上）' do
        expect(texts('tab', usage: { 0x231 => 9 }).first).to eq('Tab')
      end

      it 'context の上に出すものが先（layerKey の基本キーは、よく使うレイヤー操作より上）' do
        items = texts('', limit: 10_000, layer_names: { 1 => 'Symbols' }, usage: { 0x5261 => 50 })
        expect(items.index('Z')).to be < items.index('TG(1)')
        expect(items.index('TG(1)')).to be < items.index('MO(1)')
      end
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
      expect { described_class.new(**base, contexts: { 'x' => { 'prefer' => { 'baseLayer' => 1 } } }) }
        .to raise_error(Cornix::ConfigError, /baseLayer/)
      expect { described_class.new(**base, contexts: { 'x' => { 'exclude' => { 'categories' => ['nope'] } } }) }
        .to raise_error(Cornix::ConfigError, /order/)
      expect { described_class.new(**base, contexts: { 'x' => { 'prefre' => {} } }) }
        .to raise_error(Cornix::ConfigError, /prefre/)
    end

    it 'contexts の分類にはプロファイルから作る分類も書け、exclude? / prefer_base_layer? / prefer_rank で引ける' do
      categories = described_class.load
      expect(categories.exclude?('macroKey', 'layer')).to be(true)
      expect(categories.exclude?('layerKey', 'layer')).to be(false)
      expect(categories.prefer_base_layer?('comboTrigger')).to be(true)
      expect(categories.prefer_base_layer?('layerKey')).to be(false)
      expect(categories.prefer_rank('comboOutput', 'macro', nil)).to eq(0)
      expect(categories.prefer_rank('comboOutput', 'basic', 'KC_A')).to eq(1)
      expect(categories.prefer_rank('encoder', 'mouse', 'KC_WH_U')).to eq(1)
      expect(categories.prefer_rank('encoder', 'mouse', 'KC_BTN1')).to be_nil
    end
  end
end
