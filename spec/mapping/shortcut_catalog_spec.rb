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

    it '表記は正規形で書いてある（decompile が書く形と同じ）' do
      catalog.texts.each do |name, text|
        expect(notation.format(notation.parse(text))).to eq(text), name
      end
    end

    it 'library は直前と同じ notation なら解析し直さない' do
      expect(catalog.library(notation)).to equal(catalog.library(notation))
    end
  end

  it '入れ子のキーを : でつなぐ（深さは問わない。前後の空白は除く）' do
    catalog = catalog_from('a.yaml' => "App:\n  Cat:\n    ' Label ': Tab\n  Top: Esc\n")
    expect(catalog.texts).to eq('App:Cat:Label' => 'Tab', 'App:Top' => 'Esc')
  end

  it '同梱データの誤りは ConfigError' do
    expect { catalog_from('a.yaml' => "App:\n  'A:B': Tab\n") }.to raise_error(Cornix::ConfigError, /':' を含まない/)
    expect { catalog_from('a.yaml' => "App:\n  X: 1\n") }.to raise_error(Cornix::ConfigError, /App:X」の値はキーコードの表記/)
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
