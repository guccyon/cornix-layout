# frozen_string_literal: true

module Cornix
  module Storage
    # テキストの中の範囲。行も列も 0 始まりで、列は UTF-16 のコード単位（LSP の Range と同じ）。
    # 先頭の BOM は数えない（VS Code の TextDocument と同じ）。負の値と、開始が終わりよりうしろの範囲は InvalidValue
    class TextRange < Data.define(:start_line, :start_character, :end_line, :end_character)
      def self.at(line, character) = new(start_line: line, start_character: character, end_line: line, end_character: character)

      def initialize(start_line:, start_character:, end_line:, end_character:)
        values = [start_line, start_character, end_line, end_character]
        unless values.all? { |v| v.is_a?(Integer) && v >= 0 }
          raise InvalidValue, "範囲の行と列は 0 以上の整数です: #{values.inspect}"
        end
        raise InvalidValue, "範囲の開始が終わりよりうしろです: #{values.inspect}" if ([start_line, start_character] <=> [end_line, end_character]).positive?

        super
      end

      def empty? = start_line == end_line && start_character == end_character

      # protocol.md の Range の形（{ start: { line:, character: }, end: { ... } }）
      def to_protocol
        { start: { line: start_line, character: start_character }, end: { line: end_line, character: end_character } }
      end
    end
  end
end
