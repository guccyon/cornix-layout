# frozen_string_literal: true

require 'yaml'

module Cornix
  module Application
    module Editor
      class ItemEdits
        # マッピングの名前（キー）の書き換えと、項目 1 つの行の削除（Storage::YamlDocument は値の部分だけを扱うので、
        # 名前の変更で要るキーの側をここで扱う）。範囲は YamlDocument と同じく BOM を除いたテキストでの位置（列は UTF-16）。
        #
        #   keys = YamlKeys.new(text)
        #   keys.key?(%w[mapping left_hand row0 tab])                  #=> true
        #   keys.rename_key(%w[mapping left_hand row0 tab], 'esc')     #=> Storage::TextEdit（名前の部分だけ。なければ nil）
        #   keys.remove_entry(['shortcuts', '前のタブへ'])              #=> Storage::TextEdit（その項目の行ごと。なければ nil）
        #
        # 局所的に扱えないとき（複数行の名前、フロー表記の中の項目の削除）は Storage::EditNotLocal
        class YamlKeys
          Nodes = Psych::Nodes
          QUOTES = { Nodes::Scalar::SINGLE_QUOTED => "'", Nodes::Scalar::DOUBLE_QUOTED => '"' }.freeze

          def initialize(text)
            text = text.to_s
            text = text.dup.force_encoding(Encoding::UTF_8) unless text.encoding == Encoding::UTF_8
            @body = text.delete_prefix(Storage::YamlFile::BOM)
            @lines = Storage::YamlDocument::LineIndex.new(@body)
            @root = Psych.parse(@body)&.root
          rescue Psych::SyntaxError => e
            raise Storage::YamlFile::Unreadable, "YAML の文法エラーです（#{e.line} 行 #{e.column} 桁）: #{e.problem}"
          end

          def key?(path) = !entry(path).nil?

          def rename_key(path, name)
            found = entry(path) or return nil
            key, _, parent = found
            raise Storage::EditNotLocal.new(reason: :multiline, path: path) unless key.start_line == key.end_line

            flow = parent.style == Nodes::Mapping::FLOW
            text = Storage::YamlDocument::ScalarFormat.format(name, flow: flow, quote: QUOTES[key.style])
            Storage::TextEdit.new(range: range(key.start_line, key.start_column, key.end_line, key.end_column), new_text: text)
          end

          def remove_entry(path)
            found = entry(path) or return nil
            key, value, parent = found
            raise Storage::EditNotLocal.new(reason: :flow_insert, path: path) if parent.style == Nodes::Mapping::FLOW

            prefix = @lines.line(key.start_line)[0, key.start_column]
            raise Storage::EditNotLocal.new(reason: :flow_insert, path: path) unless prefix.strip.empty?

            Storage::TextEdit.new(range: line_range(key.start_line, last_line(key, value)), new_text: '')
          end

          private

          # path の最後の段の [名前のノード, 値のノード, 親のマッピング]。なければ nil
          def entry(path)
            node = @root
            found = nil
            path.each do |segment|
              found = nil
              case node
              when Nodes::Mapping
                key, value = node.children.each_slice(2).find { |k, _| k.is_a?(Nodes::Scalar) && k.value == segment.to_s }
                return nil unless key

                found = [key, value, node]
                node = value
              when Nodes::Sequence
                return nil unless segment.is_a?(Integer) && segment >= 0 && segment < node.children.size

                node = node.children[segment]
              else return nil
              end
            end
            found
          end

          def range(start_line, start_column, end_line, end_column)
            Storage::TextRange.new(start_line: start_line, start_character: @lines.utf16(start_line, start_column),
                                   end_line: end_line, end_character: @lines.utf16(end_line, end_column))
          end

          # first 行から last 行までを、行の終わりの改行ごと消す範囲（最後の行なら前の行の改行から）
          def line_range(first, last)
            if last + 1 < @lines.line_count
              return Storage::TextRange.new(start_line: first, start_character: 0, end_line: last + 1, end_character: 0)
            end

            stop_line, stop_character = @lines.end_position
            return Storage::TextRange.new(start_line: first, start_character: 0, end_line: stop_line, end_character: stop_character) if first.zero?

            Storage::TextRange.new(start_line: first - 1, start_character: @lines.utf16_length(first - 1),
                                   end_line: stop_line, end_character: stop_character)
          end

          # 項目の中身がある最後の行
          def last_line(key, value) = [key.end_line, content_line(value)].compact.max

          def content_line(node)
            case node
            when Nodes::Scalar
              return nil if node.value.empty? && node.style == Nodes::Scalar::PLAIN

              node.end_column.zero? && node.end_line > node.start_line ? node.end_line - 1 : node.end_line
            when Nodes::Mapping, Nodes::Sequence
              flow = node.style == (node.is_a?(Nodes::Mapping) ? Nodes::Mapping::FLOW : Nodes::Sequence::FLOW)
              flow ? node.end_line : node.children.filter_map { |child| content_line(child) }.max
            else node&.end_line
            end
          end
        end
      end
    end
  end
end
