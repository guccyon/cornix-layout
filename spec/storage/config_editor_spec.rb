# frozen_string_literal: true

require 'spec_helper'
require_relative 'support/storage_helpers'

RSpec.describe Cornix::Storage::ConfigEditor do
  include StorageHelpers

  it 'update_fields は 1 行の項目だけを置き換え、ほかの行とコメントを保つ' do
    with_config_copy do |dir|
      path = File.join(dir, 'macros/00_macro.yaml')
      File.write(path, "# メモ\nindex: 0\nname: Macro 0\ndescription: ''\nsequence: []\n")
      described_class.new(dir).update_fields(path, 'name' => 'Copy: all', description: '説明')
      expect(File.read(path)).to eq("# メモ\nindex: 0\nname: 'Copy: all'\ndescription: 説明\nsequence: []\n")
    end
  end

  it 'update_fields は 1 行でない項目やない項目があればファイル全体を書き直す' do
    with_config_copy do |dir|
      path = File.join(dir, 'macros/00_macro.yaml')
      File.write(path, "index: 0\nname: Macro 0\ndescription: |\n  長い\n  説明\nsequence: []\n")
      described_class.new(dir).update_fields(path, 'description' => '短い', 'extra' => 1)
      expect(YAML.safe_load_file(path)).to eq('index' => 0, 'name' => 'Macro 0', 'description' => '短い',
                                              'sequence' => [], 'extra' => 1)
    end
  end

  it 'replace_references は引用符の種類（YAML の中で重ねた引用符も）を保ち、名前が完全に一致するものだけ変える' do
    with_config_copy do |dir|
      path = File.join(dir, 'layers/0_layer_0.yaml')
      File.write(path, <<~YAML)
        mapping:
          left_hand:
            row0: { tab: Macro('Copy'), Q: "Macro(\\"Copy\\")", W: 'Macro(''Copy'')' }
            row1:
              A: Macro( "Copy" )
              S: Macro('Copy All')
              D: TapDance('Copy')
      YAML
      changed = described_class.new(dir).replace_references('Macro', 'Copy', "Paste's")
      expect(changed).to eq(['layers/0_layer_0.yaml'])
      expect(File.read(path)).to eq(<<~YAML)
        mapping:
          left_hand:
            row0: { tab: Macro("Paste's"), Q: "Macro(\\"Paste's\\")", W: 'Macro(''Paste's'')' }
            row1:
              A: Macro("Paste's")
              S: Macro('Copy All')
              D: TapDance('Copy')
      YAML
    end
  end

  it 'replace_references_in はテキストの中だけで置き換え（ファイルは書かない）、Shortcut(...) も扱う' do
    text = "tab: Shortcut('Mine')\nQ: Shortcut(\"Mine\")\nW: Shortcut('Mine 2')\nE: Macro('Mine')\n"
    expect(described_class.replace_references_in(text, 'Shortcut', 'Mine', '自分の'))
      .to eq("tab: Shortcut('自分の')\nQ: Shortcut(\"自分の\")\nW: Shortcut('Mine 2')\nE: Macro('Mine')\n")
    expect(described_class.reference_pattern('Macro', 'Mine')).to match("Macro( 'Mine' )")
    expect { described_class.reference_pattern('Layer', 'x') }.to raise_error(ArgumentError)
    with_config_copy do |dir|
      expect { described_class.new(dir).replace_references('Shortcut', 'a', 'b') }.to raise_error(ArgumentError)
    end
  end

  it 'backup / restore / backups / delete_backup' do
    with_config_copy do |dir|
      editor = described_class.new(dir)
      time = Time.new(2026, 1, 2, 3, 4, 5)
      first = editor.backup(time: time)
      second = editor.backup(time: time)
      expect([first, second]).to eq(["#{dir}.backup_20260102_030405", "#{dir}.backup_20260102_030405_2"])
      expect(YAML.safe_load_file(File.join(first, '.backup_manifest.yaml'))).to include('source_dir' => dir)
      File.write(File.join(dir, 'metadata.yaml'), "broken\n")
      File.write(File.join(dir, 'new.yaml'), "a: 1\n")
      expect(editor.restore(first)).to be(true)
      expect(File).not_to exist(File.join(dir, 'new.yaml'))
      expect(File).not_to exist(File.join(dir, '.backup_manifest.yaml'))
      expect(File.read(File.join(dir, 'metadata.yaml'))).to eq(File.read(File.join(StorageHelpers::TEST_CONFIG, 'metadata.yaml')))
      expect(editor.backups).to eq([first, second])
      editor.delete_backup(first)
      expect(editor.backups).to eq([second])
      expect(editor.restore(nil)).to be(false)
    end
  end

  it 'resolve は config/ 付き・設定ディレクトリからの相対・絶対パスを受け付ける' do
    with_config_copy do |dir|
      editor = described_class.new(dir)
      root = File.dirname(dir)
      expect(editor.resolve('config/macros/00_macro.yaml', base: root)).to eq(File.join(dir, 'macros/00_macro.yaml'))
      expect(editor.resolve('macros/00_macro.yaml', base: root)).to eq(File.join(dir, 'macros/00_macro.yaml'))
      expect(editor.resolve('/x/y.yaml', base: root)).to eq('/x/y.yaml')
    end
  end
end

RSpec.describe Cornix::Storage::DecompileLock do
  it '旧実装と同じ項目で書き、読む' do
    Dir.mktmpdir do |dir|
      lock = described_class.new(dir)
      expect(lock.read).to be_nil
      source = File.join(dir, 'a.vil')
      File.write(source, '{}')
      expect(lock.write(source: source, time: Time.new(2026, 1, 2, 3, 4, 5, '+09:00'))).to eq(File.join(dir, '.decompile.lock'))
      expect(lock.read).to eq('decompiled_at' => '2026-01-02 03:04:05 +0900', 'source_file' => source,
                              'checksum' => Digest::SHA256.hexdigest('{}'))
      File.write(lock.path, ": [")
      expect(lock.read).to eq({})
    end
  end
end
