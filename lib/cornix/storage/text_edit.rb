# frozen_string_literal: true

require_relative 'text_range'
require_relative 'yaml_file'
require_relative 'yaml_document/line_index'

module Cornix
  module Storage
    # 範囲を new_text で置き換える書き換え 1 つ（LSP の TextEdit と同じ）。
    #
    #   TextEdit.apply(text, edits)     # => edits をすべて当てたテキスト
    #   TextEdit.diff(before, after)    # => before を after にする書き換え（変わった文字のまとまりごと）
    class TextEdit < Data.define(:range, :new_text)
      def initialize(range:, new_text:)
        raise InvalidValue, "範囲は TextRange です: #{range.inspect}" unless range.is_a?(TextRange)
        raise InvalidValue, "書き換える文字は文字列です: #{new_text.inspect}" unless new_text.is_a?(String)

        super(range: range, new_text: new_text.dup.freeze)
      end

      def to_protocol = { range: range.to_protocol, newText: new_text }

      class << self
        # edits をすべて当てたテキスト。範囲はすべて元の text での位置。
        # 同じ位置への挿入は並びの順に入り、同じ位置から始まる置き換えより前に入る。重なれば ArgumentError
        def apply(text, edits)
          text = utf8(text)
          bom = text.start_with?(YamlFile::BOM) ? YamlFile::BOM : ''
          body = text.delete_prefix(YamlFile::BOM)
          index = YamlDocument::LineIndex.new(body)
          spans = edits.each_with_index.map do |edit, i|
            r = edit.range
            [index.offset(r.start_line, r.start_character), index.offset(r.end_line, r.end_character), i, edit.new_text]
          end.sort_by { |start, stop, i, _| [start, stop, i] }
          spans.each_cons(2) do |(_, stop, _, _), (start, _, _, _)|
            raise ArgumentError, '書き換えの範囲が重なっています' if stop > start
          end
          bom + spans.reverse.each_with_object(body.dup) { |(start, stop, _, new_text), out| out[start...stop] = new_text }
        end

        # before を after にする書き換え。行ごとの最長共通部分列で変わった行のまとまりを求め、
        # そのまとまりの前後の同じ文字を除く（1 つの値だけが変わったなら、その値の範囲だけの書き換えになる）。
        # 同じファイルへの変更を 1 つずつ当てて読み直したあと、元のテキストに対する書き換えにまとめるのに使う
        def diff(before, after)
          old_body = utf8(before).delete_prefix(YamlFile::BOM)
          new_body = utf8(after).delete_prefix(YamlFile::BOM)
          old_lines = split_lines(old_body)
          new_lines = split_lines(new_body)
          index = YamlDocument::LineIndex.new(old_body)
          old_offsets = offsets(old_lines)
          hunks(old_lines, new_lines).map do |old_from, old_to, new_from, new_to|
            from = old_offsets[old_from]
            old_text = old_lines[old_from...old_to].join
            new_text = new_lines[new_from...new_to].join
            head, tail = common_ends(old_text, new_text)
            start = index.position(from + head)
            stop = index.position(from + old_text.size - tail)
            new(range: TextRange.new(start_line: start[0], start_character: start[1], end_line: stop[0], end_character: stop[1]),
                new_text: new_text[head...(new_text.size - tail)])
          end
        end

        private

        def utf8(text)
          text = text.to_s
          text.encoding == Encoding::UTF_8 ? text : text.dup.force_encoding(Encoding::UTF_8)
        end

        # 改行を含めた行の並び
        def split_lines(text) = text.scan(/[^\r\n]*(?:\r\n|\r|\n)|[^\r\n]+\z/)

        def offsets(lines) = lines.each_with_object([0]) { |line, acc| acc << (acc.last + line.size) }

        # a と b の先頭と末尾で同じ文字の数（重ならないように。\r\n の間では切らない）
        def common_ends(a, b)
          limit = [a.size, b.size].min
          head = 0
          head += 1 while head < limit && a[head] == b[head]
          head -= 1 if head.positive? && a[head - 1] == "\r" && a[head] == "\n"
          tail = 0
          tail += 1 while tail < limit - head && a[a.size - 1 - tail] == b[b.size - 1 - tail]
          tail -= 1 if tail.positive? && a[a.size - tail] == "\n" && a[a.size - tail - 1] == "\r"
          [head, tail]
        end

        # 最長共通部分列で、変わったまとまり [元の開始, 元の終わり, 新しい開始, 新しい終わり] の並び
        def hunks(old_lines, new_lines)
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
                result << [hunk[0], i, hunk[1], j]
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
          result << [hunk[0], i, hunk[1], j] if hunk
          result
        end
      end
    end
  end
end
