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

    it '範囲が重なれば ArgumentError' do
      expect { described_class.apply("abc\n", [edit(span(0, 0, 0, 2), 'x'), edit(span(0, 1, 0, 3), 'y')]) }
        .to raise_error(ArgumentError)
    end

    it 'protocol.md の形にできる' do
      expect(edit(span(7, 11, 7, 33), 'Escape').to_protocol)
        .to eq({ range: { start: { line: 7, character: 11 }, end: { line: 7, character: 33 } }, newText: 'Escape' })
    end
  end

  describe '.diff' do
    it '変わった行のまとまりだけの書き換えにする' do
      before = "a\nb\nc\nd\n"
      after = "a\nB\nc\nd\ne\n"
      edits = described_class.diff(before, after)
      expect(edits).to eq([edit(span(1, 0, 2, 0), "B\n"), edit(at(4, 0), "e\n")])
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
