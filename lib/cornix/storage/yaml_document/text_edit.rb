# frozen_string_literal: true

require_relative 'line_index'

module Cornix
  module Storage
    # テキストの中の範囲。行も列も 0 始まりで、列は UTF-16 のコード単位（LSP の Range と同じ）。
    # 先頭の BOM は数えない（VS Code の TextDocument と同じ）
    class TextRange < Data.define(:start_line, :start_character, :end_line, :end_character)
      def self.at(line, character) = new(start_line: line, start_character: character, end_line: line, end_character: character)

      def empty? = start_line == end_line && start_character == end_character

      # protocol.md の Range の形（{ start: { line:, character: }, end: { ... } }）
      def to_protocol
        { start: { line: start_line, character: start_character }, end: { line: end_line, character: end_character } }
      end
    end

    # 範囲を new_text で置き換える書き換え 1 つ（LSP の TextEdit と同じ）
    class TextEdit < Data.define(:range, :new_text)
      BOM = "﻿"

      def to_protocol = { range: range.to_protocol, newText: new_text }

      # edits をすべて当てたテキスト。範囲はすべて元の text での位置（同じ位置への挿入は並びの順に入る）。重なれば ArgumentError
      def self.apply(text, edits)
        bom = text.start_with?(BOM) ? BOM : ''
        body = text.delete_prefix(BOM)
        index = YamlDocument::LineIndex.new(body)
        spans = edits.each_with_index.map do |edit, i|
          r = edit.range
          [index.offset(r.start_line, r.start_character), index.offset(r.end_line, r.end_character), i, edit.new_text]
        end
        spans.sort_by { |start, stop, i, _| [start, stop, i] }.each_cons(2) do |(_, stop, _, _), (start, _, _, _)|
          raise ArgumentError, '書き換えの範囲が重なっています' if stop > start
        end
        result = spans.sort_by { |start, _, i, _| [-start, -i] }.reduce(body.dup) do |out, (start, stop, _, new_text)|
          out[start...stop] = new_text
          out
        end
        bom + result
      end

      # before を after にする行ごとの書き換え（変わった行のまとまりごとに 1 つ）。
      # 同じファイルへの変更を 1 つずつ当てて読み直したあと、元のテキストに対する書き換えにまとめるのに使う
      def self.diff(before, after)
        old_lines = split_lines(before.delete_prefix(BOM))
        new_lines = split_lines(after.delete_prefix(BOM))
        index = YamlDocument::LineIndex.new(before.delete_prefix(BOM))
        offsets = old_lines.each_with_object([0]) { |line, acc| acc << (acc.last + line.size) }
        hunks(old_lines, new_lines).map do |old_from, old_to, new_from, new_to|
          start = index.position(offsets[old_from])
          stop = index.position(offsets[old_to])
          new(range: TextRange.new(start_line: start[0], start_character: start[1], end_line: stop[0], end_character: stop[1]),
              new_text: new_lines[new_from...new_to].join)
        end
      end

      # 改行を含めた行の並び
      def self.split_lines(text) = text.scan(/[^\r\n]*(?:\r\n|\r|\n)|[^\r\n]+\z/)

      # 最長共通部分列で、変わったまとまり [元の開始, 元の終わり, 新しい開始, 新しい終わり] の並び
      def self.hunks(old_lines, new_lines)
        n = old_lines.size
        m = new_lines.size
        lcs = Array.new(n + 1) { Array.new(m + 1, 0) }
        (n - 1).downto(0) do |i|
          (m - 1).downto(0) do |j|
            lcs[i][j] = old_lines[i] == new_lines[j] ? lcs[i + 1][j + 1] + 1 : [lcs[i + 1][j], lcs[i][j + 1]].max
          end
        end
        result = []
        i = j = 0
        hunk = nil
        while i < n || j < m
          if i < n && j < m && old_lines[i] == new_lines[j]
            if hunk
              result << hunk.push(i, j)
              hunk = nil
            end
            i += 1
            j += 1
          else
            hunk ||= [i, j]
            if j < m && (i >= n || lcs[i][j + 1] >= lcs[i + 1][j])
              j += 1
            else
              i += 1
            end
          end
        end
        result << hunk.push(i, j) if hunk
        result.map { |old_from, new_from, old_to, new_to| [old_from, old_to, new_from, new_to] }
      end
      private_class_method :split_lines, :hunks
    end
  end
end
