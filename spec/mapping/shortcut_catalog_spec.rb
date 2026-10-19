# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe Cornix::Mapping::ShortcutCatalog do
  let(:notation) { Cornix::Mapping::KeycodeNotation.new }

  def catalog_from(files)
    Dir.mktmpdir do |dir|
      files.each { |name, text| File.write(File.join(dir, name), text) }
      return described_class.load(dir)
    end
  end

  # 入れ子の中の { macro: [...] } の keys の表記すべて
  def macro_keys_in(node)
    return [] unless node.is_a?(Hash)
    return node['macro'].flat_map { |step| Array(step['keys']) } if node.keys == ['macro']

    node.values.flat_map { |value| macro_keys_in(value) }
  end

  describe '同梱の data/shortcuts/' do
    subject(:catalog) { described_class.default }

    it 'すべての定義をキーコードとして解釈できる' do
      library = catalog.library(notation)
      expect(library.names.size).to eq(catalog.texts.size)
      expect(library.names.size).to be > 800
    end

    it '名前は「アプリ:カテゴリ:ラベル」の 3 段' do
      expect(catalog.texts.keys).to all(satisfy { |name| name.split(':').size == 3 })
      expect(catalog.texts['Spotify:再生:次のクリップ']).to eq('Command + Right')
      expect(catalog.library(notation).entries['macOS:システム:全画面キャプチャ']).to eq(notation.parse('Shift + Command + 3'))
    end

    it '表記は正規形で書いてある（decompile が書く形と同じ。マクロの keys も）' do
      catalog.texts.each do |name, text|
        expect(notation.format(notation.parse(text))).to eq(text), name
      end
      macro_keys = Dir[File.join(described_class::DIR, '*.yaml')].flat_map { |path| macro_keys_in(YAML.safe_load_file(path)) }
      expect(macro_keys).not_to be_empty
      macro_keys.each { |key| expect(notation.format(notation.parse(key))).to eq(key) }
    end

    it '複数の手順のもの（#13 で入れなかったもの）はマクロの定義で、preset で手順になる' do
      expect(catalog.macro_names).to include('macOS:システム:ウィンドウキャプチャ', 'VS Code:基本操作:キーボードショートカット',
                                             'Android Studio:ナビゲーション:全体を検索', 'Fusion 360:スケッチ:スプライン',
                                             'Fusion 360:スケッチ:ミラー')
      expect(catalog.macro_names).to all(satisfy { |name| !catalog.texts.key?(name) })
      catalog.macro_names.each { |name| expect(catalog.preset(name, notation)).to all(be_a(Cornix::Domain::MacroStep::Value)) }
      expect(catalog.preset_names.size).to eq(catalog.texts.size + catalog.macro_names.size)
    end

    it 'library は直前と同じ notation なら解析し直さない' do
      expect(catalog.library(notation)).to equal(catalog.library(notation))
    end
  end

  it '入れ子のキーを : でつなぐ（深さは問わない。前後の空白は除く）' do
    catalog = catalog_from('a.yaml' => "App:\n  Cat:\n    ' Label ': Tab\n  Top: Esc\n")
    expect(catalog.texts).to eq('App:Cat:Label' => 'Tab', 'App:Top' => 'Esc')
  end

  describe '#preset' do
    let(:step) { Cornix::Domain::MacroStep }
    let(:catalog) do
      catalog_from('a.yaml' => <<~YAML)
        App:
          Key: A
          Mod: Shift + Command + 4
          Right: RCTL(KC_A)
          Two:
            macro:
              - { action: down, keys: LGui }
              - { action: tap, keys: [K, S] }
              - { action: up, keys: LGui }
      YAML
    end

    def keys(*texts) = texts.map { |t| notation.parse(t) }

    it 'マクロの定義は書いた手順' do
      expect(catalog.macro_names).to eq(['App:Two'])
      expect(catalog.texts.keys).to eq(%w[App:Key App:Mod App:Right])
      expect(catalog.preset('App:Two', notation)).to eq([step::Down.new(keys: keys('LGui')), step::Tap.new(keys: keys('K', 'S')),
                                                         step::Up.new(keys: keys('LGui'))])
    end

    it '1 シーケンスの定義は押して離す手順（修飾キーは押す → キー → 逆順に離す。右側の修飾キーは右側のまま）' do
      expect(catalog.preset('App:Key', notation)).to eq([step::Tap.new(keys: keys('A'))])
      expect(catalog.preset('App:Mod', notation)).to eq([step::Down.new(keys: keys('LShift', 'LGui')), step::Tap.new(keys: keys('4')),
                                                         step::Up.new(keys: keys('LGui', 'LShift'))])
      expect(catalog.preset('App:Right', notation)).to eq([step::Down.new(keys: keys('RCtrl')), step::Tap.new(keys: keys('A')),
                                                           step::Up.new(keys: keys('RCtrl'))])
    end

    it 'なければ nil。同じ notation なら同じ結果を返す' do
      expect(catalog.preset('App:None', notation)).to be_nil
      expect(catalog.preset('App:Two', notation)).to equal(catalog.preset('App:Two', notation))
    end
  end

  it '同梱データの誤りは ConfigError' do
    expect { catalog_from('a.yaml' => "App:\n  'A:B': Tab\n") }.to raise_error(Cornix::ConfigError, /':' を含まない/)
    expect { catalog_from('a.yaml' => "App:\n  X: 1\n") }.to raise_error(Cornix::ConfigError, /App:X」の値はキーコードの表記（文字列）か/)
    expect { catalog_from('a.yaml' => "App:\n  X:\n    macro: []\n") }.to raise_error(Cornix::ConfigError, /App:X」の macro は手順の空でない/)
    expect { catalog_from('a.yaml' => "App:\n  X:\n    macro: [{ action: delay, keys: A }]\n") }
      .to raise_error(Cornix::ConfigError, /App:X」の macro\[0\] は \{ action: tap/)
    expect { catalog_from('a.yaml' => "App:\n  X:\n    macro: [{ action: tap, keys: 4 }]\n") }
      .to raise_error(Cornix::ConfigError, /App:X」の macro\[0\]/)
    expect { catalog_from('a.yaml' => "App:\n  X:\n    macro: [{ action: tap, keys: Nope }]\n").preset('App:X', notation) }
      .to raise_error(Cornix::ConfigError, /ショートカット「App:X」: キーコード「Nope」を解釈できません/)
    expect { catalog_from('a.yaml' => "App:\n  X: Tab\n  Y: { macro: [{ action: tap, keys: A }] }\n", 'b.yaml' => "App:\n  Y: Esc\n") }
      .to raise_error(Cornix::ConfigError, /「App:Y」が重複/)
    expect { catalog_from('a.yaml' => "App:\n  X: {}\n") }.to raise_error(Cornix::ConfigError, /App:X は空でない Hash/)
    expect { catalog_from('a.yaml' => "- Tab\n") }.to raise_error(Cornix::ConfigError, /ファイルの先頭/)
    expect { catalog_from('a.yaml' => "App:\n  X: Tab\n", 'b.yaml' => "App:\n  X: Esc\n") }
      .to raise_error(Cornix::ConfigError, /「App:X」が重複/)
    expect { catalog_from('a.yaml' => "App: [\n") }.to raise_error(Cornix::ConfigError)
    expect { catalog_from('a.yaml' => "App:\n  X: NoSuchKey\n").library(notation) }
      .to raise_error(Cornix::ConfigError, %r{/a\.yaml: ショートカット「App:X」: キーコード「NoSuchKey」を解釈できません})
    expect { described_class.new('App:X' => 'NoSuchKey').library(notation) }
      .to raise_error(Cornix::ConfigError, /ショートカット「App:X」: キーコード「NoSuchKey」を解釈できません/)
  end
end
