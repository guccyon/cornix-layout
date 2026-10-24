# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Cornix::Application::Editor::ItemEdits::YamlKeys do
  def apply(text, edit) = Cornix::Storage::TextEdit.apply(text, [edit])

  describe '#rename_key' do
    it '名前の部分だけを書き換え、値・コメントは保つ' do
      text = "mapping:\n  row0:\n    tab: Tab # メモ\n    Q: Q\n"
      edit = described_class.new(text).rename_key(%w[mapping row0 tab], 'esc')
      expect(apply(text, edit)).to eq("mapping:\n  row0:\n    esc: Tab # メモ\n    Q: Q\n")
    end

    it 'もとの引用符を保ち、フロー表記の中でも名前だけを書き換える' do
      text = "row0: { 'tab': Tab, \"Q\": Q }\n"
      keys = described_class.new(text)
      expect(apply(text, keys.rename_key(%w[row0 tab], 'esc'))).to eq("row0: { 'esc': Tab, \"Q\": Q }\n")
      expect(apply(text, keys.rename_key(%w[row0 Q], 'q'))).to eq("row0: { 'tab': Tab, \"q\": Q }\n")
    end

    it '列は UTF-16 で数え、BOM は数えない' do
      text = "\uFEFFshortcuts:\n  前のタブへ: KC_A\n"
      edit = described_class.new(text).rename_key(%w[shortcuts 前のタブへ], '😀')
      expect(edit.range.to_protocol).to eq({ start: { line: 1, character: 2 }, end: { line: 1, character: 7 } })
      expect(apply(text, edit)).to eq("\uFEFFshortcuts:\n  😀: KC_A\n")
    end

    it 'ない名前は nil' do
      expect(described_class.new("a: 1\n").rename_key(%w[b], 'c')).to be_nil
      expect(described_class.new("a: [1]\n").key?(['a', 0])).to be(false)
    end
  end

  describe '#remove_entry' do
    it '項目の行（複数行の値も）を行の終わりの改行ごと消す' do
      text = "shortcuts:\n  a: KC_A\n  b: |\n    long\n  c: KC_C\n"
      keys = described_class.new(text)
      expect(apply(text, keys.remove_entry(%w[shortcuts a]))).to eq("shortcuts:\n  b: |\n    long\n  c: KC_C\n")
      expect(apply(text, keys.remove_entry(%w[shortcuts b]))).to eq("shortcuts:\n  a: KC_A\n  c: KC_C\n")
    end

    it '値のない項目と、改行で終わらない最後の項目' do
      text = "shortcuts:\n  a:\n  b: KC_B"
      keys = described_class.new(text)
      expect(apply(text, keys.remove_entry(%w[shortcuts a]))).to eq("shortcuts:\n  b: KC_B")
      expect(apply(text, keys.remove_entry(%w[shortcuts b]))).to eq("shortcuts:\n  a:")
    end

    it 'フロー表記の中の項目は消せない（EditNotLocal の flow_insert）' do
      expect { described_class.new("shortcuts: { a: KC_A }\n").remove_entry(%w[shortcuts a]) }
        .to raise_error(Cornix::Storage::EditNotLocal) { |e| expect(e.reason).to eq(:flow_insert) }
      expect { described_class.new("- a: 1\n  b: 2\n").remove_entry([0, 'a']) }
        .to raise_error(Cornix::Storage::EditNotLocal)
    end
  end

  it 'YAML として読めなければ YamlFile::Unreadable' do
    expect { described_class.new("a: [\n") }.to raise_error(Cornix::Storage::YamlFile::Unreadable)
  end
end
