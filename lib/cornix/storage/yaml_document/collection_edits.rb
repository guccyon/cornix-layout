# frozen_string_literal: true

module Cornix
  module Storage
    class YamlDocument
      # 項目の削除・並びの要素の挿入と移動・注記の書き換え（protocol.md の 12.3）。値だけの書き換え（6.3）の考え方を、
      # 行の削除と並びの要素に広げたもの。キー・字下げ・コメント・ほかの行は変えない。
      #
      #   doc.remove(%w[mapping left_hand row0 tab])           # マッピングの 1 項目（行）か並びの要素を消す。なければ []
      #   doc.insert_item(['sequence', 0, 'keys'], 1, 'KC_B')  # 並びの index の前に足す（並びの長さなら末尾）
      #   doc.move_item(['trigger_keys'], 0, 2)                 # 並びの from の要素を to の位置へ動かす
      #   doc.set_note(%w[mapping left_hand row0 tab], '注記')  # tab: Escape → tab: { key: Escape, note: 注記 }
      #   doc.remove_note(%w[mapping left_hand row0 tab])       # { key: Escape, note: 注記 } → Escape
      #
      # - ブロック形式の項目・要素は行ごと（字下げから改行まで）消す。要素の中のコメントの行も一緒に消える
      # - ブロック形式の並びへの挿入は、ほかの要素と同じ字下げの「- 値」の行を、前の要素のすぐあと（先頭なら最初の要素の前）に
      #   足す（要素の前のコメントの行はその要素のものとして残す）。Hash の値（マクロの手順）は
      #   「- action: tap」と、その下の字下げした「keys: [KC_A]」の行（中の並びはフロー表記）
      # - ブロック形式の並びの移動は、要素の行（前の要素とのあいだのコメントの行を含む）ごと動かす
      # - フロー表記の並び（[a, b]）への挿入・削除・移動は、並び全体を 1 行のフロー表記として書き直す。
      #   並びが複数行なら EditNotLocal（:flow_insert）
      # - 1 つの値で書いた並びの場所（keys: KC_A）への挿入は、フロー表記の並び（keys: [KC_A, KC_B]）に置き換える
      # - フロー表記の Hash（{ tab: Tab, Q: Q }）の項目の削除は、その項目と区切りの「, 」だけを消す（1 行のときだけ）
      # - 前に別の内容がある行（「- action: tap」の action、「--- k: v」）の項目は行ごと消せないので EditNotLocal（:shared_line）
      SEQUENCE_DASH = /\A[ \t]*-[ \t]+\z/
      LONE_DASH = /\A[ \t]*-[ \t]*(?:#.*)?\z/

      # path の項目（マッピングの 1 項目か並びの要素）を消す書き換え。なければ []
      def remove(path)
        steps = walk(path) or return []
        raise ArgumentError, 'ルートは消せません' if path.empty?

        check_anchor!(steps, path)
        last = steps.last
        case last.parent
        when Nodes::Mapping then remove_entry(last.parent, last.key, last.node, path)
        when Nodes::Sequence then remove_element(last.parent, path.last, path)
        else raise ArgumentError, "消せる場所ではありません: #{path.join('.')}"
        end
      end

      # path の並びの index の前に value（文字列・整数か、Hash・並び）を足す書き換え（index が並びの長さなら末尾）。
      # path の値が 1 つの値なら要素 1 つの並び、値なしなら空の並びとして扱う
      def insert_item(path, index, value)
        steps = walk(path) or raise ArgumentError, "並びがありません: #{path.join('.')}"
        check_anchor!(steps, path)
        node = steps.last.node
        case node
        when Nodes::Sequence then insert_into_sequence(node, index, value, path)
        when Nodes::Scalar then insert_into_scalar(steps.last, index, value, path)
        else raise ArgumentError, "並びではありません: #{path.join('.')}"
        end
      end

      # path の並びの from の要素を to の位置へ動かす書き換え（ほかの要素の順は保つ）。from と to が同じなら []
      def move_item(path, from, to)
        steps = walk(path) or raise ArgumentError, "並びがありません: #{path.join('.')}"
        check_anchor!(steps, path)
        node = steps.last.node
        size = node.is_a?(Nodes::Sequence) ? node.children.size : 1
        raise ArgumentError, "並びの外です: #{from} → #{to}" unless [from, to].all? { |i| i.between?(0, size - 1) }
        return [] if from == to

        raise ArgumentError, "並びではありません: #{path.join('.')}" unless node.is_a?(Nodes::Sequence)

        return rewrite_flow(node, moved(node.children.map { |c| source(c) }, from, to), path) if flow_sequence?(node)

        move_block_element(node, from, to, path)
      end

      # path の割り当ての注記を note にする書き換え。注記のない形（tab: Escape）は { key: Escape, note: 注記 } にする。
      # 割り当てがなければ ArgumentError（呼ぶ側が確かめる）
      def set_note(path, note)
        steps = walk(path) or raise ArgumentError, "割り当てがありません: #{path.join('.')}"
        check_anchor!(steps, path)
        node = steps.last.node
        if (pair = assignment_pair(node))
          return replace(path + ['note'], note) if note_pair(node)

          return add_note(node, pair, path, note)
        end
        raise ArgumentError, "割り当てがありません: #{path.join('.')}" if !node.is_a?(Nodes::Scalar) || null?(node)

        check_single_line!(node, path)
        text = "{ key: #{source(node)}, note: #{ScalarFormat.format(note, flow: true)} }"
        [TextEdit.new(range: node_range(node), new_text: text)]
      end

      # path の割り当ての注記を消し、key の値だけの形に戻す書き換え。注記がなければ []。
      # 1 行のフロー表記（{ key: Escape, note: 注記 }）は Escape に、ブロック形式は note の行だけを消す
      def remove_note(path)
        steps = walk(path) or return []
        check_anchor!(steps, path)
        node = steps.last.node
        pair = assignment_pair(node)
        return [] unless pair && note_pair(node)
        return remove(path + ['note']) unless node.style == Nodes::Mapping::FLOW
        raise EditNotLocal.new(reason: :multiline, path: path) unless single_line?(node)

        [TextEdit.new(range: node_range(node), new_text: source(pair.last))]
      end

      private

      # ---- 削除 ----

      def remove_entry(mapping, key, value, path)
        return remove_flow_entry(mapping, key, path) if mapping.style == Nodes::Mapping::FLOW

        prefix = @lines.line(key.start_line)[0, key.start_column]
        raise EditNotLocal.new(reason: :shared_line, path: path) unless prefix.strip.empty?

        [delete_lines(key.start_line, [key.end_line, last_line(value)].compact.max)]
      end

      # 1 行のフロー表記の Hash から項目を 1 つ消す（区切りの「, 」も）。最後の 1 つなら {}
      def remove_flow_entry(mapping, key, path)
        raise EditNotLocal.new(reason: :flow_insert, path: path) unless single_line?(mapping)

        entries = mapping.children.each_slice(2).to_a
        return [TextEdit.new(range: node_range(mapping), new_text: '{}')] if entries.size == 1

        i = entries.index { |k, _| k.equal?(key) }
        from, to = if i.zero? then [start_of(key), start_of(entries[1].first)]
                   else [end_of_entry(*entries[i - 1]), end_of_entry(*entries[i])]
                   end
        [TextEdit.new(range: TextRange.new(start_line: from[0], start_character: from[1],
                                           end_line: to[0], end_character: to[1]), new_text: '')]
      end

      def remove_element(sequence, index, path)
        if flow_sequence?(sequence)
          texts = sequence.children.map { |c| source(c) }
          texts.delete_at(index)
          return rewrite_flow(sequence, texts, path)
        end

        child = sequence.children.fetch(index)
        [delete_lines(dash_line(child, path), element_end(child))]
      end

      # 行 first から last までを改行ごと消す書き換え（最後の行なら前の行の改行から）
      def delete_lines(first, last)
        range = if last + 1 < @lines.line_count
                  TextRange.new(start_line: first, start_character: 0, end_line: last + 1, end_character: 0)
                elsif first.positive?
                  TextRange.new(start_line: first - 1, start_character: @lines.utf16_length(first - 1),
                                end_line: last, end_character: @lines.utf16_length(last))
                else
                  TextRange.new(start_line: 0, start_character: 0, end_line: last, end_character: @lines.utf16_length(last))
                end
        TextEdit.new(range: range, new_text: '')
      end

      # ---- 挿入 ----

      def insert_into_sequence(sequence, index, value, path)
        children = sequence.children
        raise ArgumentError, "並びの外です: #{index}" unless index.between?(0, children.size)

        if flow_sequence?(sequence)
          texts = children.map { |c| source(c) }
          texts.insert(index, ScalarFormat.inline(value, flow: true))
          return rewrite_flow(sequence, texts, path)
        end

        anchor = children[[index, children.size - 1].min]
        lines = block_element_lines(value, @lines.line(dash_line(anchor, path))[/\A[ \t]*/])
        # 前の要素のすぐあとに足す（要素の前のコメントの行は、移動と同じくその要素のものとして残す）
        return [TextEdit.new(range: TextRange.at(dash_line(anchor, path), 0), new_text: lines.join(nl) + nl)] if index.zero?

        line = element_end(children[index - 1])
        [TextEdit.new(range: TextRange.at(line, @lines.utf16_length(line)), new_text: nl + lines.join(nl))]
      end

      # 1 つの値（keys: KC_A）か値なし（trigger_keys:）の場所に、フロー表記の並びとして足す
      def insert_into_scalar(step, index, value, path)
        node = step.node
        item = ScalarFormat.inline(value, flow: true)
        if null?(node)
          raise ArgumentError, "並びの外です: #{index}" unless index.zero?
          return fill_empty_list(step.key, item, path) if node.value.empty?

          return [TextEdit.new(range: node_range(node), new_text: "[#{item}]")]
        end
        raise ArgumentError, "並びの外です: #{index}" unless index.between?(0, 1)

        check_single_line!(node, path)
        texts = [source(node)].insert(index, item)
        [TextEdit.new(range: node_range(node), new_text: "[#{texts.join(', ')}]")]
      end

      def fill_empty_list(key, item, path)
        raise ArgumentError, "並びがありません: #{path.join('.')}" unless key

        line, character = after_colon(key)
        [TextEdit.new(range: TextRange.at(line, character), new_text: " [#{item}]")]
      end

      # ブロック形式の並びの要素の行。Hash は最初の項目を「- 」の行に、残りをその下に字下げして書く
      def block_element_lines(value, indent)
        return ["#{indent}- #{ScalarFormat.inline(value)}"] unless value.is_a?(Hash)

        entries = value.map { |k, v| "#{ScalarFormat.format(k.to_s)}: #{ScalarFormat.inline(v)}" }
        ["#{indent}- #{entries.first}", *entries.drop(1).map { |e| "#{indent}  #{e}" }]
      end

      # ---- 移動 ----

      # 要素の行のまとまり（2 つめからは前の要素とのあいだの行を含む）を並べ替え、元のテキストとの差分にする
      def move_block_element(sequence, from, to, path)
        children = sequence.children
        ends = children.map { |c| element_end(c) }
        starts = children.each_index.map { |i| i.zero? ? dash_line(children[0], path) : ends[i - 1] + 1 }
        blocks = children.each_index.map { |i| (starts[i]..ends[i]).map { |l| @lines.line(l) }.join(nl) }
        head = @lines.offset(starts.first, 0)
        tail = @lines.offset(ends.last, @lines.utf16_length(ends.last))
        text = @text[0...head] + moved(blocks, from, to).join(nl) + @text[tail..]
        TextEdit.diff(@text, text)
      end

      def moved(list, from, to)
        list = list.dup
        list.insert(to, list.delete_at(from))
      end

      # ---- 注記 ----

      def note_pair(node) = node.children.each_slice(2).find { |k, _| k.is_a?(Nodes::Scalar) && k.value == 'note' }

      # { key: X } に note を足す（1 行のフロー表記は key の値のあとに「, note: 注記」、ブロック形式は key の次の行）
      def add_note(node, pair, path, note)
        return insert(path + ['note'], note, order: %w[key note]) unless node.style == Nodes::Mapping::FLOW
        raise EditNotLocal.new(reason: :flow_insert, path: path) unless single_line?(node)

        line, character = end_of_entry(*pair)
        [TextEdit.new(range: TextRange.at(line, character), new_text: ", note: #{ScalarFormat.format(note, flow: true)}")]
      end

      # ---- 位置と中身 ----

      def flow_sequence?(node) = node.style == Nodes::Sequence::FLOW

      def single_line?(node)
        range = node_range(node)
        range.start_line == range.end_line
      end

      # フロー表記の並びを 1 行で書き直す（もとが「[ a ]」のように内側に空白があれば保つ）
      def rewrite_flow(sequence, texts, path)
        raise EditNotLocal.new(reason: :flow_insert, path: path) unless single_line?(sequence)

        inner = texts.join(', ')
        text = source(sequence).match?(/\A\[[ \t]/) && !texts.empty? ? "[ #{inner} ]" : "[#{inner}]"
        [TextEdit.new(range: node_range(sequence), new_text: text)]
      end

      # ノードのテキスト（引用符などもそのまま）
      def source(node)
        range = node_range(node)
        @text[@lines.offset(range.start_line, range.start_character)...@lines.offset(range.end_line, range.end_character)]
      end

      def start_of(node)
        range = node_range(node)
        [range.start_line, range.start_character]
      end

      # 項目の終わり（値が空ならキーの終わり）の位置
      def end_of_entry(key, value)
        range = empty_null?(value) ? node_range(key) : node_range(value)
        [range.end_line, range.end_character]
      end

      # ブロック形式の並びの要素の「-」がある行。「- 値」の行か、「-」だけの行の次に値があるとき
      def dash_line(child, path)
        prefix = @lines.line(child.start_line)[0, child.start_column]
        return child.start_line if prefix.match?(SEQUENCE_DASH)
        if prefix.strip.empty? && child.start_line.positive? && @lines.line(child.start_line - 1).match?(LONE_DASH)
          return child.start_line - 1
        end

        raise EditNotLocal.new(reason: :shared_line, path: path)
      end

      # 要素の中身がある最後の行（値が空なら始まりの行）
      def element_end(child) = last_line(child) || child.start_line
    end
  end
end
