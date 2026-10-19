# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Cornix::Storage::TextEdit do
  def at(line, character) = Cornix::Storage::TextRange.at(line, character)
  def span(sl, sc, el, ec) = Cornix::Storage::TextRange.new(start_line: sl, start_character: sc, end_line: el, end_character: ec)
  def edit(range, text) = described_class.new(range: range, new_text: text)

  describe '.apply' do
    it '元のテキストでの位置で当て、同じ位置への挿入は並びの順に入る' do
      text = "ab\ncd\n"
      edits = [edit(span(0, 0, 0, 1), 'A'), edit(at(1, 2), 'X'), edit(at(1, 2), 'Y'), edit(span(1, 0, 1, 1), '')]
      expect(described_class.apply(text, edits)).to eq("Ab\ndXY\n")
    end

    it '列は UTF-16 のコード単位、BOM は数えずに残す' do
      text = "﻿😀a: b\n"
      expect(described_class.apply(text, [edit(span(0, 2, 0, 3), 'c')])).to eq("﻿😀c: b\n")
    end

    it '同じ位置から始まる挿入と置き換えは、並びの順によらず挿入が前に入る' do
      replace = edit(span(0, 1, 0, 3), 'XY')
      insert = edit(at(0, 1), '_')
      expect(described_class.apply('abcdef', [replace, insert])).to eq('a_XYdef')
      expect(described_class.apply('abcdef', [insert, replace])).to eq('a_XYdef')
    end

    it 'UTF-8 でない文字列（BINARY）も UTF-8 として当てる' do
      expect(described_class.apply('ベース: a'.b, [edit(span(0, 5, 0, 6), 'b')])).to eq('ベース: b')
    end

    it '範囲が重なれば ArgumentError' do
      expect { described_class.apply("abc\n", [edit(span(0, 0, 0, 2), 'x'), edit(span(0, 1, 0, 3), 'y')]) }
        .to raise_error(ArgumentError)
    end

    it '負の値・逆向きの範囲・文字列でない new_text は InvalidValue' do
      expect { span(0, 3, 0, 1) }.to raise_error(Cornix::InvalidValue)
      expect { span(1, 0, 0, 5) }.to raise_error(Cornix::InvalidValue)
      expect { at(-1, 0) }.to raise_error(Cornix::InvalidValue)
      expect { edit(at(0, 0), nil) }.to raise_error(Cornix::InvalidValue)
      expect { described_class.new(range: nil, new_text: '') }.to raise_error(Cornix::InvalidValue)
    end

    it 'protocol.md の形にできる' do
      expect(edit(span(7, 11, 7, 33), 'Escape').to_protocol)
        .to eq({ range: { start: { line: 7, character: 11 }, end: { line: 7, character: 33 } }, newText: 'Escape' })
    end
  end

  describe '.diff' do
    it '変わった行のまとまりごとに、前後の同じ文字を除いた書き換えにする' do
      before = "a\nb\nc\nd\n"
      after = "a\nB\nc\nd\ne\n"
      edits = described_class.diff(before, after)
      expect(edits).to eq([edit(span(1, 0, 1, 1), 'B'), edit(at(4, 0), "e\n")])
      expect(described_class.apply(before, edits)).to eq(after)
    end

    it '1 つの値だけが変わったなら、その値の範囲だけ（replace と同じ）' do
      before = "row0:\n  tab: TapDance('Tab Escape')   # c\n  Q: Q\n"
      doc = Cornix::Storage::YamlDocument.parse(before)
      edits = doc.replace(%w[row0 tab], 'Escape')
      expect(described_class.diff(before, described_class.apply(before, edits))).to eq(edits)
    end

    it 'CRLF の \\r と \\n の間では切らない' do
      before = "a: 1\r\nb: 2\r\n"
      after = "a: 1\nb: 2\r\n"
      edits = described_class.diff(before, after)
      expect(edits).to eq([edit(span(0, 4, 1, 0), "\n")])
      expect(described_class.apply(before, edits)).to eq(after)
    end

    it '同じなら []、末尾の改行がなくても戻せる' do
      expect(described_class.diff("a\n", "a\n")).to eq([])
      before = "a\nb"
      after = "a\nb\nc"
      expect(described_class.apply(before, described_class.diff(before, after))).to eq(after)
    end
  end
end
