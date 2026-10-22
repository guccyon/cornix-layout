# frozen_string_literal: true

require_relative 'operation'

module Cornix
  module Application
    module Editor
      class ItemEdits
        # preset: で書いたマクロを手順に展開する（protocol.md の 13.1 の expandPreset）。
        #
        # preset: の行（項目）を、同梱の定義の手順（Mapping::ShortcutCatalog#preset。読み込みで Domain::Macro#steps に入っているもの）の
        # sequence: に置き換える。手順の書き方は Schema::MacroFile.write と同じ形（keys はいつもリスト。名前参照は使わない）。
        # name: を書いていなければ（preset の名前が名前になっている）、展開しても名前が変わらないように name: を足す。
        # ほかの行（description・index・コメント）は変えない。前後の compile の結果の照合は ItemEdits が行う
        #
        #   preset: 'macOS:システム:ウィンドウキャプチャ'    →    sequence:
        #                                                          - action: down
        #                                                            keys:
        #                                                            - KC_LGUI
        #                                                          ...
        #
        # preset: で書いていないマクロ・知らない名前は InvalidChange（field "edit.name"）
        class ExpandPreset < Operation
          def requires_complete? = true

          PRESET = 'preset'
          KEY_LINE = /\A[ \t]*(?:#{PRESET}|'#{PRESET}'|"#{PRESET}")[ \t]*:/

          private

          def run(edit)
            kind = kind_of(edit)
            macro, file = find_item(kind, edit.name)
            raise InvalidChange.new('edit.name', "マクロ「#{edit.name}」は preset: で書いていません") unless macro.preset

            name = Storage::YamlDocument.parse(changeset.text(file)).range(['name']) ? nil : macro.name
            edit_file(file) { |text| Storage::YamlDocument.parse(text).insert(['name'], name, order: kind.keys) } if name
            edit_file(file) { |text| sequence_edits(text, macro) }
            outcome(verify: { file: file, path: [PRESET] })
          end

          # preset: の項目を消す書き換え（YamlDocument#remove。行ごと）の範囲に、sequence: の行を書く
          def sequence_edits(text, macro)
            removal = Storage::YamlDocument.parse(text).remove([PRESET]).first
            range = removal.range
            body = text.delete_prefix(Storage::YamlFile::BOM)
            lines = body.lines
            # 最後の行を消す書き換えは前の行の改行から始まる
            key_line = range.start_character.zero? ? range.start_line : range.start_line + 1
            key_text = lines[key_line].to_s
            unless key_text.match?(KEY_LINE)
              raise Storage::EditNotLocal.new(reason: :flow_insert, path: [PRESET])
            end

            nl = body.include?("\r\n") ? "\r\n" : "\n"
            block = sequence_lines(macro, key_text[/\A[ \t]*/]).join(nl)
            new_text = if range.start_character.positive? then nl + block
                       elsif range.end_line > range.start_line && range.end_character.zero? then block + nl
                       else block
                       end
            [Storage::TextEdit.new(range: range, new_text: new_text)]
          end

          # sequence: とその下の行（YamlFile.dump の形を、preset: の行の字下げにそろえたもの）
          def sequence_lines(macro, indent)
            keycodes = Storage::Schema::KeycodeField.new(env.notation)
            steps = macro.steps.map { |step| Storage::Schema::MacroFile.write_step(step, keycodes) }
            Storage::YamlFile.dump({ 'sequence' => steps }).lines(chomp: true).reject { |line| line == '---' }
                             .map { |line| "#{indent}#{line}" }
          end
        end
      end
    end
  end
end
