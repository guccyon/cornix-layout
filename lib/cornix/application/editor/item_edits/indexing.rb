# frozen_string_literal: true

require_relative 'operation'

module Cornix
  module Application
    module Editor
      class ItemEdits
        # 番号（index:）の操作の基底（v0.5 の use / unuse / setIndex。protocol.md の 15.3）。
        # ファイルは書き換えず、未保存の変更に積む Change（["index"] の set / remove と、番号の参照の書き換え）を outcome.changes に返す。
        # reading は今の未保存の変更を当てた状態（ItemEdits が作る）。項目はファイル（edit.file）で指す（名前も番号も 1 つに決まらないため）
        class Indexing < Operation
          INDEX_PATH = ['index'].freeze

          private

          # edit.file の項目。使っていれば [:used, 項目, ファイル]、未使用なら [:unused, UnusedFile, ファイル]。
          # そのファイルのその種類の項目がなければ InvalidChange（"edit.file"）
          def locate!(kind, file)
            position = used_files(kind).index(file)
            return [:used, kind.items(profile)[position], file] if position

            unused = reading.unused.find { |u| u.kind == kind.files && u.file == file }
            return [:unused, unused, file] if unused

            raise InvalidChange.new('edit.file', "#{kind.label}のファイル #{file} がありません")
          end

          def used_files(kind)
            kind.items(profile).each_index.map { |i| reading.repository.address("#{kind.collection}[#{i}]").first }
          end

          def limit(kind) = kind.limit(env.capabilities)

          def set_index(file, index) = PlanEdits::Change.new(file: file, path: INDEX_PATH, value: index)

          def remove_index(file) = PlanEdits::Change.new(file: file, path: INDEX_PATH, op: :remove)
        end

        # 未使用の項目を使い始める（use）。番号は、使っているいちばん大きい番号の次。それが上限なら空いているいちばん小さい番号。
        # 何も使っていなければ 0。空きがなければ InvalidChange（"edit"）、使っている項目なら "edit.file"。参照は書き換えない
        class Use < Indexing
          private

          def run(edit)
            kind = kind_of(edit)
            state, = locate!(kind, edit.file)
            raise InvalidChange.new('edit.file', "#{kind.label}のファイル #{edit.file} はもう使っています") if state == :used

            index = next_index(kind.items(profile).map(&:index), limit(kind))
            unless index
              raise InvalidChange.new('edit', "#{kind.label}は #{limit(kind)} 件までです（空いている番号がありません。先にどれかを未使用にしてください）")
            end

            outcome(changes: [set_index(edit.file, index)])
          end

          def next_index(used, limit)
            return 0 if used.empty?

            last = used.max + 1
            return last if last < limit

            (0...limit).find { |i| !used.include?(i) }
          end
        end

        # 使っている項目を未使用にする（unuse）。参照は書き換えず、references に壊れる参照の場所を返す
        # （Delete と同じ数え方。そのファイルの中の欄は入れない）。未使用の項目なら InvalidChange（"edit.file"）
        class Unuse < Indexing
          private

          def run(edit)
            kind = kind_of(edit)
            state, item, file = locate!(kind, edit.file)
            raise InvalidChange.new('edit.file', "#{kind.label}のファイル #{file} はもう未使用です") if state == :unused

            outcome(changes: [remove_index(file)], references: item_references(edit.kind, item, file))
          end
        end

        # 使っている項目の番号を変える（setIndex）。新しい番号をほかの使っている項目が使っていれば、その項目に今の番号を付ける（入れ替え）。
        # 範囲の外・今と同じ番号なら InvalidChange（"edit.index"）、未使用の項目なら "edit.file"。
        # マクロ・タップダンスは、番号で書いた参照（Macro(3) / M3 / TapDance(2) / TD(2) / 0x7703）を表記の形を保って新しい番号に書き換える
        # Change を足し、その場所を references に返す（NumberedReference）。名前の参照・Shortcut(...) は書き換えない（名前で引くので追従する）。
        # レイヤーの参照（MO(1) など）は書き換えない（中身を入れ替えるのが目的。#105）。コンボは参照されない。
        # 書き換えのあとに参照の指す先が変わらないことは ItemEdits が確かめる（verify）
        class SetIndex < Indexing
          private

          def run(edit)
            kind = kind_of(edit)
            state, item, file = locate!(kind, edit.file)
            raise InvalidChange.new('edit.file', "#{kind.label}のファイル #{file} は未使用です（先に使ってください）") if state == :unused

            check_index!(kind, edit.index, item.index)
            changes = [set_index(file, edit.index)]
            moves = { item.index => edit.index }
            other = swapped(kind, edit.index, file)
            if other
              changes << set_index(other, item.index)
              moves[edit.index] = item.index
            end
            references = []
            numbered_references(edit.kind, moves).each do |slot, text|
              changes << PlanEdits::Change.new(file: slot.address[:file], path: slot.address[:path], value: text)
              references << slot.address
            end
            outcome(changes: changes, references: references, verify: { file: file, path: INDEX_PATH })
          end

          def check_index!(kind, index, current)
            unless (0...limit(kind)).cover?(index)
              raise InvalidChange.new('edit.index', "#{kind.label}の番号は 0〜#{limit(kind) - 1} です: #{index}")
            end
            raise InvalidChange.new('edit.index', "#{kind.label}の番号はもう #{index} です") if index == current
          end

          # その番号を使っているほかの項目のファイル（なければ nil）
          def swapped(kind, index, file)
            files = used_files(kind)
            position = kind.items(profile).each_index.find { |i| kind.items(profile)[i].index == index && files[i] != file }
            position && files[position]
          end

          # [Slot, 新しい表記]（番号で書いた参照だけ）
          def numbered_references(kind_name, moves)
            call = CALLS[kind_name] or return []

            slots.filter_map do |slot|
              next unless slot.keycode.is_a?(call) && moves.key?(slot.keycode.index) && slot.text

              to = moves.fetch(slot.keycode.index)
              text = NumberedReference.rewrite(slot.text, call.new(index: to), env.notation.codec)
              [slot, text] if text
            end
          end
        end

        # 番号で書いた参照の表記を、形を保ったまま別の番号にする（SetIndex）。
        #
        #   NumberedReference.rewrite('Macro(3)', MacroCall.new(index: 5), codec)   #=> "Macro(5)"
        #   NumberedReference.rewrite('M3', ...)       #=> "M5"
        #   NumberedReference.rewrite('TD( 2 )', TapDanceCall.new(index: 4), codec)   #=> "TD( 4 )"
        #   NumberedReference.rewrite('0x7703', ...)   #=> "0x7705"（桁数と大文字・小文字を保つ）
        #   NumberedReference.rewrite("Macro('Copy')", ...)   #=> nil（名前の参照は書き換えない）
        module NumberedReference
          FORMS = {
            Domain::Keycode::MacroCall => [/\A(Macro\s*\(\s*)(\d+)(\s*\))\z/, /\A(M)(\d+)()\z/],
            Domain::Keycode::TapDanceCall => [/\A(TapDance\s*\(\s*)(\d+)(\s*\))\z/, /\A(TD\s*\(\s*)(\d+)(\s*\))\z/]
          }.freeze
          HEX = /\A(0[xX])(\h+)\z/

          module_function

          def rewrite(text, keycode, codec)
            FORMS.fetch(keycode.class).each do |pattern|
              m = pattern.match(text) or next
              return "#{m[1]}#{keycode.index}#{m[3]}"
            end
            m = HEX.match(text) or return nil
            digits = format("%0#{m[2].size}X", codec.encode(keycode))
            "#{m[1]}#{m[2].match?(/[a-f]/) ? digits.downcase : digits}"
          end
        end
      end
    end
  end
end
