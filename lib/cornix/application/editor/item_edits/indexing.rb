# frozen_string_literal: true

require_relative 'operation'

module Cornix
  module Application
    module Editor
      class ItemEdits
        # 番号（index:）の操作の基底（v0.5 の use / unuse / setIndex / reorder。protocol.md の 15.3）。
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

        # 番号を付け替える操作（setIndex / reorder）の基底。番号の変わる項目の、元の番号を指す参照を新しい番号に書き換える。
        # 書き換えは番号の変わるすべての項目について同時に決める（moves は { 元の番号 => 新しい番号 }。入れ替わる番号どうしでも取り違えない）。
        # - マクロ・タップダンス: 番号で書いた参照（Macro(3) / M3 / TapDance(2) / TD(2) / 0x7703）を表記の形を保って書き換える（NumberedReference）。
        #   名前の参照・Shortcut(...) は書き換えない（名前で引くので追従する）
        # - レイヤー: 16bit 値の中にレイヤーの番号を持つもの（MO / TG / TO / TT / OSL / DF / PDF(n)、LT(n, kc)、LT<n>(kc)、LM(n, mod)、
        #   それらの 0xHHHH）を表記の形を保って書き換える（LayerReference。ADR 025）
        # - コンボ: 参照されない
        # 書き換えのあとに参照の指す先が変わらないことは ItemEdits が確かめる（verify。書き換えられない参照が残れば Unverified）
        class Renumbering < Indexing
          private

          # [Change], [Address]（参照の書き換えと、その場所）
          def rewrite_references(kind_name, moves)
            rewrites = kind_name == 'layer' ? layer_references(moves) : numbered_references(kind_name, moves)
            changes = rewrites.map { |slot, text| PlanEdits::Change.new(file: slot.address[:file], path: slot.address[:path], value: text) }
            [changes, rewrites.map { |slot, _| slot.address }]
          end

          # [Slot, 新しい表記]（番号で書いた参照だけ）
          def numbered_references(kind_name, moves)
            call = CALLS[kind_name] or return []

            slots.filter_map do |slot|
              next unless slot.keycode.is_a?(call) && moves.key?(slot.keycode.index) && slot.text

              to = moves.fetch(slot.keycode.index)
              text = NumberedReference.rewrite(slot.text, call.new(index: to), codec)
              [slot, text] if text
            end
          end

          # [Slot, 新しい表記]（元の番号のレイヤーを指すレイヤー操作）
          def layer_references(moves)
            slots.filter_map do |slot|
              code = encode(slot.keycode) or next
              layer = codec.layer_of(code)
              next unless layer && moves.key?(layer) && slot.text

              to = moves.fetch(layer)
              moved = codec.with_layer(code, to) or next
              text = LayerReference.rewrite(slot.text, to, moved)
              [slot, text] if text
            end
          end

          def encode(keycode)
            codec.encode(keycode)
          rescue Cornix::Error
            nil
          end

          def codec = env.notation.codec
        end

        # 使っている項目の番号を変える（setIndex）。新しい番号をほかの使っている項目が使っていれば、その項目に今の番号を付ける（入れ替え）。
        # 範囲の外・今と同じ番号なら InvalidChange（"edit.index"）、未使用の項目なら "edit.file"。参照の書き換えは Renumbering
        class SetIndex < Renumbering
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
            rewrites, references = rewrite_references(edit.kind, moves)
            outcome(changes: changes + rewrites, references: references, verify: { file: file, path: INDEX_PATH })
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
        end

        # 使っている項目を並べ直す（reorder。ADR 025）。edit.files は使っている項目すべてのファイルの新しい並び。
        # 今の番号を小さい順に並べ、新しい並びの順に当てる（抜け番はそのまま。0・2・5 の A・B・C を [C, A, B] にすると C=0・A=2・B=5）。
        # 番号の変わる項目ごとに ["index"] の set（新しい並びの順）、続けて参照の書き換え（Renumbering）。並びが今と同じなら changes は []。
        # edit.files が使っている項目の集まりと違えば（足りない・余分・重複・未使用のファイル）InvalidChange（"edit.files"）。
        # 使っている項目の番号が重なっていれば（意味検証の error）、どちらの参照か決まらないので InvalidChange（"edit"）
        class Reorder < Renumbering
          private

          def run(edit)
            kind = kind_of(edit)
            files = used_files(kind)
            check_files!(kind, edit.files, files)
            items = kind.items(profile)
            indexes = items.map(&:index)
            if indexes.uniq.size != indexes.size
              raise InvalidChange.new('edit', "#{kind.label}の番号が重なっているので並び替えられません（先に番号を直してください）")
            end

            changes = []
            moves = {}
            edit.files.zip(indexes.sort) do |file, to|
              from = items[files.index(file)].index
              next if from == to

              changes << set_index(file, to)
              moves[from] = to
            end
            return outcome if changes.empty?

            rewrites, references = rewrite_references(edit.kind, moves)
            outcome(changes: changes + rewrites, references: references, verify: changes.first.then { |c| { file: c.file, path: INDEX_PATH } })
          end

          def check_files!(kind, order, files)
            missing = files - order
            extra = order - files
            duplicated = order.select { |file| order.count(file) > 1 }.uniq
            problems = []
            problems << "足りないファイル: #{missing.join(', ')}" unless missing.empty?
            problems << "使っていないファイル: #{extra.join(', ')}" unless extra.empty?
            problems << "重なっているファイル: #{duplicated.join(', ')}" unless duplicated.empty?
            return if problems.empty?

            raise InvalidChange.new('edit.files', "files は使っている#{kind.label}すべての並びです（#{problems.join('。')}）")
          end
        end

        # 番号で書いた参照の表記を、形を保ったまま別の番号にする（Renumbering）。
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
            hex(m, codec.encode(keycode))
          end

          # HEX の一致を、桁数と大文字・小文字を保って code にする
          def hex(match, code)
            digits = format("%0#{match[2].size}X", code)
            "#{match[1]}#{match[2].match?(/[a-f]/) ? digits.downcase : digits}"
          end
        end

        # レイヤー操作の表記の番号を、形を保ったまま別の番号にする（Renumbering）。code は新しい 16bit 値（0xHHHH の表記に使う）。
        #
        #   LayerReference.rewrite('MO(1)', 2, 0x5222)          #=> "MO(2)"
        #   LayerReference.rewrite('LT( 1, Space )', 2, …)     #=> "LT( 2, Space )"
        #   LayerReference.rewrite('LT1(Space)', 2, …)          #=> "LT2(Space)"
        #   LayerReference.rewrite('LM(1, MOD_LSFT)', 2, …)     #=> "LM(2, MOD_LSFT)"
        #   LayerReference.rewrite('0x5221', 2, 0x5222)         #=> "0x5222"（桁数と大文字・小文字を保つ）
        #   LayerReference.rewrite("Shortcut('Symbols')", …)    #=> nil（ほかの表記は書き換えない）
        module LayerReference
          FORMS = [
            /\A((?:MO|TG|TO|TT|OSL|DF|PDF)\s*\(\s*)(\d+)(\s*\))\z/,
            /\A((?:LT|LM)\s*\(\s*)(\d+)(\s*,.*\))\z/m,
            /\A(LT)(\d+)(\s*\(.*\))\z/m
          ].freeze

          module_function

          def rewrite(text, index, code)
            FORMS.each do |pattern|
              m = pattern.match(text) or next
              return "#{m[1]}#{index}#{m[3]}"
            end
            m = NumberedReference::HEX.match(text) or return nil
            NumberedReference.hex(m, code)
          end
        end
      end
    end
  end
end
