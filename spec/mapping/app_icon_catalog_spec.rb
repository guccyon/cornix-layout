# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe Cornix::Mapping::AppIconCatalog do
  def catalog_from(text)
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'shortcut_icons.yaml')
      File.write(path, text)
      return described_class.load(path)
    end
  end

  describe '同梱の data/shortcut_icons.yaml' do
    subject(:catalog) { described_class.default }

    let(:app_names) do
      shortcuts = Cornix::Mapping::ShortcutCatalog.default
      shortcuts.preset_names.map { |name| name.split(Cornix::Mapping::ShortcutCatalog::SEPARATOR).first }.uniq
    end

    it 'data/shortcuts/ のすべてのアプリにアイコン ID がある' do
      missing = app_names.reject { |name| catalog.icon(name) }
      expect(missing).to be_empty, "アイコンのないアプリ: #{missing.join(', ')}"
    end

    it 'data/shortcuts/ にないアプリ名はない' do
      expect(catalog.app_names - app_names).to be_empty
      expect(catalog.app_names.size).to eq(27)
    end

    it '素材ごとの数は spec.md の「アイコン」のとおり（Simple Icons 15・Material Icon Theme 3・バッジ 9）' do
      counts = catalog.app_names.map { |name| catalog.icon(name).split(':').first }.tally
      expect(counts).to eq('simple-icons' => 15, 'material-icon-theme' => 3, 'badge' => 9)
    end

    it 'アプリ名で ID を引ける' do
      expect(catalog.icon('Figma')).to eq('simple-icons:figma')
      expect(catalog.icon('VS Code')).to eq('material-icon-theme:vscode')
      expect(catalog.icon('CleanShot X')).to eq('badge:CS')
    end

    it '表にないアプリ（自分のショートカットなど）は nil' do
      expect(catalog.icon('前のタブへ')).to be_nil
      expect(catalog.icon(nil)).to be_nil
    end

    it 'default は 1 回だけ読む' do
      expect(described_class.default).to equal(catalog)
    end
  end

  describe '.load' do
    it 'icons: の Hash を読む' do
      catalog = catalog_from("icons:\n  Figma: simple-icons:figma\n  Word: material-icon-theme:word\n  Slack: badge:S\n")
      expect(catalog.app_names).to eq(%w[Figma Word Slack])
      expect(catalog.icon('Slack')).to eq('badge:S')
    end

    it 'icons: がなければ ConfigError' do
      expect { catalog_from("- Figma\n") }.to raise_error(Cornix::ConfigError, /icons: にアプリ名/)
      expect { catalog_from("icons: []\n") }.to raise_error(Cornix::ConfigError, /icons: にアプリ名/)
    end

    it 'ID の書き方が正しくなければ ConfigError' do
      expect { catalog_from("icons:\n  Figma: figma\n") }.to raise_error(Cornix::ConfigError, /「Figma」のアイコン ID/)
      expect { catalog_from("icons:\n  Figma: simple-icons:Figma\n") }.to raise_error(Cornix::ConfigError, /「Figma」/)
      expect { catalog_from("icons:\n  Slack: badge:SLACK\n") }.to raise_error(Cornix::ConfigError, /「Slack」/)
      expect { catalog_from("icons:\n  Slack:\n") }.to raise_error(Cornix::ConfigError, /「Slack」/)
    end

    it 'ファイルがない・YAML が壊れていれば ConfigError' do
      expect { described_class.load('/nonexistent/shortcut_icons.yaml') }.to raise_error(Cornix::ConfigError)
      expect { catalog_from("icons: [\n") }.to raise_error(Cornix::ConfigError)
    end
  end
end
