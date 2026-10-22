# frozen_string_literal: true

require 'yaml'
require_relative 'yaml_file'
require_relative 'yaml_document/line_index'
require_relative 'text_range'
require_relative 'text_edit'
require_relative 'edit_not_local'
require_relative 'yaml_document/scalar_format'
require_relative 'yaml_document/collection_edits'

module Cornix
  module Storage
    # 設定ファイル 1 つの YAML のノードの位置と、値の部分だけの書き換え（protocol.md の 2 の位置と範囲、6.3）。
    #
    #   doc = YamlDocument.parse(text)
    #   doc.range(%w[mapping left_hand row0 tab])           # => TextRange（列は UTF-16 のコード単位）
    #   doc.scalar(%w[mapping left_hand row0 tab])          # => "TapDance('Tab Escape')"
    #   doc.replace(%w[mapping left_hand row0 tab], 'Esc')  # => [TextEdit]（同じ値なら []）
    #   doc.insert(%w[mapping left_hand row2 Z], 'Z', order: %w[lshift Z X C V B])   # まだない場所に足す
    #   TextEdit.apply(text, edits)                         # => 書き換えたテキスト
    #
    # 項目の削除・並びの要素の挿入と移動・注記の書き換え（remove / insert_item / move_item / set_note / remove_note）は
    # yaml_document/collection_edits.rb。
    #
    # path はファイルの中のキーの道筋（文字列はマッピングのキー、整数は並びの位置）。
    # 注記付きの形（{ key: 表記, note: 注記 }）は、割り当ての場所を指せば key の値を扱う（note は残す）。
    # 局所的に書き換えられないとき（複数行の値、アンカーとエイリアス、フロー表記の中への挿入）は EditNotLocal。
    # ファイル全体を書き直す逃げ道は持たない。
    #
    # Psych のノードの列は文字単位なので、行の中身から UTF-16 の列に直す。先頭の BOM は除いて数える（VS Code と同じ）
    class YamlDocument
      Nodes = Psych::Nodes
      # path を辿った 1 段。node はその場所の値、key は値の名前のスカラー（ルートと並びの要素は nil）、parent は親の値
      Step = Data.define(:node, :key, :parent)
      NULLS = ['', '~', 'null', 'Null', 'NULL'].freeze
      DEFAULT_INDENT = 2

      def self.parse(text) = new(text)

      def initialize(text)
        text = text.to_s
        text = text.dup.force_encoding(Encoding::UTF_8) unless text.encoding == Encoding::UTF_8
        raise YamlFile::Unreadable, 'UTF-8 として読めません' unless text.valid_encoding?

        @text = text.delete_prefix(YamlFile::BOM)
        @lines = LineIndex.new(@text)
        document = Psych.parse(@text)
        @root = document ? document.root : nil
      rescue Psych::SyntaxError => e
        raise YamlFile::Unreadable, "YAML の文法エラーです（#{e.line} 行 #{e.column} 桁）: #{e.problem}"
      end

      # BOM を除いたテキスト（範囲はこのテキストでの位置）
      attr_reader :text

      # path の値の範囲。注記付きの形なら key の値、値が空なら名前（キー）の範囲。なければ nil
      def range(path)
        steps = walk(path) or return nil
        node = assignment(steps.last.node)
        return node_range(steps.last.key) if empty_null?(node) && steps.last.key

        node_range(node)
      end

      # path の値の表記（スカラーの文字列）。注記付きの形なら key の値。ない・空・スカラーでなければ nil
      def scalar(path)
        steps = walk(path) or return nil
        node = assignment(steps.last.node)
        return nil unless node.is_a?(Nodes::Scalar) && !null?(node)

        node.value
      end

      # path の値を value（文字列・整数・真偽値）にする書き換え。値の部分だけを置き換え、同じ値なら []
      def replace(path, value)
        steps = walk_partial(path)
        check_anchor!(steps, path)
        raise ArgumentError, "値がありません: #{path.join('.')}" unless steps.size == path.size + 1

        node = steps.last.node
        container = steps.last.parent
        name = steps.last.key
        if (pair = assignment_pair(node))
          container = node
          name, node = pair
        end
        raise EditNotLocal.new(reason: :multiline, path: path) unless node.is_a?(Nodes::Scalar)

        return fill_empty(name, value, path, flow: flow?(steps, container)) if empty_null?(node)

        check_single_line!(node, path)
        return [] if same?(node, value)

        text = ScalarFormat.format(value, flow: flow?(steps, container), quote: quote_of(node))
        [TextEdit.new(range: node_range(node), new_text: text)]
      end

      # まだない path に value を足す書き換え。もうあれば replace と同じ。
      # order は足すキーの並びの基準: 配列なら足すキー（path の最後）の兄弟の並び、
      # Hash なら { 親の path => その下のキーの並び }（見出しごと足すときの、途中の段の並び）。並びにないキーは最後に足す
      def insert(path, value, order: [])
        steps = walk_partial(path)
        return replace(path, value) if steps.size == path.size + 1

        check_anchor!(steps, path)
        depth = steps.size - 1
        missing = path[depth..]
        raise ArgumentError, "並びの中には足せません: #{path.join('.')}" if missing.any?(Integer)

        parent = steps.last.node
        case parent
        when nil then insert_at_end(new_lines(missing, value, 0))
        when Nodes::Mapping
          # 空のフロー表記（"row1: {}"。レイヤーを足したときのファイルの形）は、値なしの見出しと同じく下に字下げして足す
          return insert_under_empty(steps.last, missing, value, path) if empty_flow_mapping?(parent) && steps.last.key

          insert_into_mapping(parent, path, depth, value, order)
        when Nodes::Scalar
          raise ArgumentError, "値の中には足せません: #{path[0, depth].join('.')}" unless null?(parent)

          insert_under_empty(steps.last, missing, value, path)
        else raise ArgumentError, "足せる場所ではありません: #{path[0, depth].join('.')}"
        end
      end

      private

      # ---- 辿る ----

      # path をすべて辿れたら Step の並び（先頭はルート）、辿れなければ nil
      def walk(path)
        steps = walk_partial(path)
        steps.size == path.size + 1 ? steps : nil
      end

      # 辿れたところまでの Step の並び
      def walk_partial(path)
        steps = [Step.new(node: @root, key: nil, parent: nil)]
        path.each do |segment|
          child = child_step(steps.last.node, segment) or break
          steps << child
        end
        steps
      end

      def child_step(node, segment)
        case node
        when Nodes::Mapping
          node.children.each_slice(2) do |key, value|
            return Step.new(node: value, key: key, parent: node) if key.is_a?(Nodes::Scalar) && key.value == segment.to_s
          end
          nil
        when Nodes::Sequence
          value = segment.is_a?(Integer) && segment >= 0 ? node.children[segment] : nil
          value && Step.new(node: value, key: nil, parent: node)
        end
      end

      # 注記付きの形（キーが key と note だけで key がある。KeycodeField::ASSIGNMENT_KEYS と同じ）なら
      # [key の名前のノード, key の値のノード]
      def assignment_pair(node)
        return nil unless node.is_a?(Nodes::Mapping)

        pairs = node.children.each_slice(2).to_a
        names = pairs.map { |key, _| key.is_a?(Nodes::Scalar) ? key.value : nil }
        return nil unless names.include?('key') && (names - Schema::KeycodeField::ASSIGNMENT_KEYS).empty?

        pairs.find { |key, _| key.value == 'key' }
      end

      # 注記付きの形なら key の値のノード
      def assignment_key(node) = assignment_pair(node)&.last

      def assignment(node) = assignment_key(node) || node

      # ---- 検査 ----

      def check_anchor!(steps, path)
        nodes = steps.map(&:node).compact
        nodes << assignment_key(nodes.last) if assignment_key(nodes.last)
        return unless nodes.any? { |n| n.is_a?(Nodes::Alias) || (n.respond_to?(:anchor) && n.anchor) }

        raise EditNotLocal.new(reason: :anchor, path: path)
      end

      def check_single_line!(node, path)
        block = [Nodes::Scalar::LITERAL, Nodes::Scalar::FOLDED].include?(node.style)
        raise EditNotLocal.new(reason: :multiline, path: path) if block || node.start_line != node.end_line
      end

      def flow?(steps, container)
        nodes = steps.map(&:node)[0...-1] + [container]
        nodes.any? { |n| (n.is_a?(Nodes::Mapping) || n.is_a?(Nodes::Sequence)) && n.style == flow_style(n) }
      end

      def flow_style(node) = node.is_a?(Nodes::Mapping) ? Nodes::Mapping::FLOW : Nodes::Sequence::FLOW

      def quoted?(node) = [Nodes::Scalar::SINGLE_QUOTED, Nodes::Scalar::DOUBLE_QUOTED].include?(node.style)

      def quote_of(node)
        { Nodes::Scalar::SINGLE_QUOTED => "'", Nodes::Scalar::DOUBLE_QUOTED => '"' }[node.style]
      end

      # 引用符なしの null（空・~・null）
      def null?(node) = node.is_a?(Nodes::Scalar) && !quoted?(node) && node.tag.nil? && NULLS.include?(node.value)

      # 何も書いていない値（"row2:" の値）
      def empty_null?(node) = null?(node) && node.value.empty?

      # 今の値と同じか（表記の文字と、読んだときの型が同じ）
      def same?(node, value)
        current = quoted?(node) ? node.value : scanner.tokenize(node.value)
        current == value && current.instance_of?(value.class)
      end

      def scanner = @scanner ||= Psych::ScalarScanner.new(Psych::ClassLoader.new)

      # ---- 範囲 ----

      def node_range(node)
        return nil unless node

        end_line = node.end_line
        end_column = node.end_column
        # ブロックの集まりとブロックスカラーの終わりは次の行の先頭になるので、前の行の終わりにする
        if end_column.zero? && end_line > node.start_line
          end_line -= 1
          end_column = @lines.line(end_line).size
        end
        TextRange.new(start_line: node.start_line, start_character: @lines.utf16(node.start_line, node.start_column),
                      end_line: end_line, end_character: @lines.utf16(end_line, end_column))
      end

      # 名前のあとのコロンの直後の位置（[行, UTF-16 の列]）
      def after_colon(key)
        line = @lines.line(key.end_line)
        column = key.end_column
        column += 1 while column < line.size && [' ', "\t"].include?(line[column])
        raise ArgumentError, 'コロンが見つかりません' unless line[column] == ':'

        [key.end_line, @lines.utf16(key.end_line, column + 1)]
      end

      # ノードの中身がある最後の行
      def last_line(node)
        case node
        when Nodes::Scalar
          return nil if empty_null?(node)

          node.end_column.zero? && node.end_line > node.start_line ? node.end_line - 1 : node.end_line
        when Nodes::Mapping, Nodes::Sequence
          return node.end_line if node.style == flow_style(node)

          node.children.filter_map { |child| last_line(child) }.max
        else node.end_line
        end
      end

      # ---- 書き換えを作る ----

      # "tab:"（値なし）に値を書く: コロンの直後に " 値" を足す
      def fill_empty(key, value, path, flow:)
        raise ArgumentError, "値がありません: #{path.join('.')}" unless key

        line, character = after_colon(key)
        [TextEdit.new(range: TextRange.at(line, character), new_text: " #{ScalarFormat.format(value, flow: flow)}")]
      end

      # 足す行（missing の最後のキーに value。途中のキーは見出し）
      def new_lines(missing, value, indent)
        step = indent_step
        missing.each_with_index.map do |key, i|
          head = "#{' ' * (indent + (i * step))}#{ScalarFormat.format(key.to_s)}:"
          i == missing.size - 1 ? "#{head} #{ScalarFormat.format(value)}" : head
        end
      end

      # 文書の字下げの幅（入れ子のブロックのマッピングから。なければ 2）
      def indent_step
        @indent_step ||= find_indent_step(@root) || DEFAULT_INDENT
      end

      def find_indent_step(node)
        return nil unless node.is_a?(Nodes::Mapping) && node.style != Nodes::Mapping::FLOW

        node.children.each_slice(2) do |key, value|
          if value.is_a?(Nodes::Mapping) && value.style != Nodes::Mapping::FLOW && !value.children.empty? &&
             value.start_line > key.start_line
            return value.children.first.start_column - key.start_column
          end
        end
        node.children.each_slice(2) { |_, value| (found = find_indent_step(value)) and return found }
        nil
      end

      def nl = @lines.newline

      # 空の文書（--- だけも）の終わりに足す
      def insert_at_end(lines)
        line, character = @lines.end_position
        text = if @text.empty? || @text.end_with?("\n", "\r") then lines.join(nl) + nl
               else nl + lines.join(nl)
               end
        [TextEdit.new(range: TextRange.at(line, character), new_text: text)]
      end

      # 文書全体が null（--- だけ、~、null）のとき: ~ や null を（前の空白ごと）消して、文書の終わりに足す
      def insert_into_null_root(node, lines)
        return insert_at_end(lines) if node.value.empty?

        range = node_range(node)
        line = @lines.line(range.start_line)
        column = node.start_column
        column -= 1 while column.positive? && [' ', "\t"].include?(line[column - 1])
        removal = TextEdit.new(range: TextRange.new(start_line: range.start_line,
                                                    start_character: @lines.utf16(range.start_line, column),
                                                    end_line: range.end_line, end_character: range.end_character),
                               new_text: '')
        [removal, *insert_at_end(lines)]
      end

      # ブロック形式のマッピングに、並びの順の場所でキー（と見出し）を足す
      def insert_into_mapping(mapping, path, depth, value, order)
        raise EditNotLocal.new(reason: :flow_insert, path: path) if mapping.style == Nodes::Mapping::FLOW

        entries = mapping.children.each_slice(2).to_a
        return insert_at_end(new_lines(path[depth..], value, 0)) if entries.empty? && depth.zero?

        indent = entries.first.first.start_column
        lines = new_lines(path[depth..], value, indent)
        keys = order_for(order, path, depth).map(&:to_s)
        rank = keys.index(path[depth].to_s)
        before = rank && entries.select { |k, _| (r = keys.index(k.value.to_s)) && r < rank }.last
        after = rank && entries.find { |k, _| (r = keys.index(k.value.to_s)) && r > rank }
        if before || !after
          insert_after_entry(before || entries.last, lines)
        else
          insert_before_entry(after.first, lines, path)
        end
      end

      def order_for(order, path, depth)
        parent = path[0, depth]
        return (parent == path[0...-1] ? order : []) if order.is_a?(Array)

        order.fetch(parent) { order.fetch(parent.map(&:to_s), []) }
      end

      def insert_after_entry((key, value), lines)
        line = [key.end_line, last_line(value)].compact.max
        [TextEdit.new(range: TextRange.at(line, @lines.utf16_length(line)), new_text: nl + lines.join(nl))]
      end

      # 最初のキーの前に字下げ以外がある（"- k: 1" や "--- k: 1"）ときも、同じ行には足せないので :flow_insert にする
      # （ブロック形式でも、前の内容と同じ行に書いた形をフロー表記と同じく扱う）
      def insert_before_entry(key, lines, path)
        prefix = @lines.line(key.start_line)[0, key.start_column]
        raise EditNotLocal.new(reason: :flow_insert, path: path) unless prefix.strip.empty?

        [TextEdit.new(range: TextRange.at(key.start_line, 0), new_text: lines.join(nl) + nl)]
      end

      # 中身のない 1 行のフロー表記のマッピング（{}）
      def empty_flow_mapping?(node)
        node.style == Nodes::Mapping::FLOW && node.children.empty? && node.start_line == node.end_line
      end

      # 値なしの見出し（"row2:"）の下に字下げして足す。~ や null、{} と書いてあればそれを消す
      def insert_under_empty(step, missing, value, path)
        key = step.key
        unless key
          raise ArgumentError, "並びの中には足せません: #{path.join('.')}" if step.parent

          return insert_into_null_root(step.node, new_lines(missing, value, 0))
        end
        raise EditNotLocal.new(reason: :flow_insert, path: path) if step.parent.style == Nodes::Mapping::FLOW

        lines = new_lines(missing, value, key.start_column + indent_step)
        edits = []
        unless step.node.is_a?(Nodes::Scalar) && step.node.value.empty?
          start_line, start_character = after_colon(key)
          stop = node_range(step.node)
          edits << TextEdit.new(range: TextRange.new(start_line: start_line, start_character: start_character,
                                                     end_line: stop.end_line, end_character: stop.end_character),
                                new_text: '')
        end
        line = key.end_line
        edits << TextEdit.new(range: TextRange.at(line, @lines.utf16_length(line)), new_text: nl + lines.join(nl))
      end
    end
  end
end
