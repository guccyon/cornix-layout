# frozen_string_literal: true

module Cornix
  module Storage
    class YamlDocument
      # テキストの行と、文字単位の列 ⇄ UTF-16 のコード単位の列の変換（LSP の Position の列は UTF-16）。
      #
      # 行の区切りは \r\n・\r・\n（YAML と VS Code の数え方）。先頭の BOM はテキストに含めない（呼ぶ側で除く）
      class LineIndex
        BREAK = /\r\n|\r|\n/

        def initialize(text)
          @text = text
          @starts = [0]
          text.scan(BREAK) { @starts << Regexp.last_match.end(0) }
        end

        def line_count = @starts.size

        # 改行を除いた行の中身
        def line(number)
          return '' unless number.between?(0, @starts.size - 1)

          stop = number + 1 < @starts.size ? @starts[number + 1] : @text.size
          @text[@starts[number]...stop].sub(/(?:\r\n|\r|\n)\z/, '')
        end

        # 文字単位の列 → UTF-16 の列
        def utf16(line_number, char_column)
          prefix = line(line_number)[0, char_column] || ''
          prefix.size + prefix.each_char.count { |c| c.ord > 0xFFFF }
        end

        # 行の長さ（UTF-16 のコード単位）
        def utf16_length(line_number) = utf16(line_number, line(line_number).size)

        # 位置（行、UTF-16 の列）→ テキストの中の文字の位置
        def offset(line_number, character)
          raise ArgumentError, "行がありません: #{line_number}" unless line_number.between?(0, @starts.size - 1)

          units = 0
          chars = 0
          line(line_number).each_char do |c|
            break if units >= character

            units += c.ord > 0xFFFF ? 2 : 1
            chars += 1
          end
          @starts[line_number] + chars
        end

        # テキストの中の文字の位置 → [行, UTF-16 の列]
        def position(offset)
          number = (@starts.bsearch_index { |start| start > offset } || @starts.size) - 1
          [number, utf16(number, offset - @starts[number])]
        end

        # テキストの末尾の位置
        def end_position = position(@text.size)

        # 文書で使っている改行（最初の改行。なければ \n）
        def newline = @text[BREAK] || "\n"
      end
    end
  end
end
