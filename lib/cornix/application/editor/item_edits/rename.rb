# frozen_string_literal: true

require_relative 'operation'

module Cornix
  module Application
    module Editor
      class ItemEdits
        # 名前を変える（protocol.md の 12.5 の rename。Application::RenameFiles と同じ手順をメモリの上で行う）。
        #
        # マクロ・タップダンス・コンボ・レイヤー: name の行を書き換え（preset: のマクロで name がなければ足す）、
        #   すべての設定ファイルの Macro('旧名') / TapDance('旧名') をテキストとして置き換え、
        #   ファイル名の slug を新しい名前に合わせる（番号の接頭辞と拡張子は保つ。同じ名前のファイルがほかにあれば変えない）。
        #   コンボとレイヤーは名前で参照されないので、name の行とファイル名だけ
        # レイヤーは file があればファイルで探す（名前は重なってよい）
        # ショートカット: shortcuts.yaml の名前（キー）を書き換え、すべての設定ファイルの Shortcut('旧名') を置き換える
        #
        # references は置き換える参照の場所（変える前の Address）。前後の compile の結果の照合は ItemEdits が行う。
        # 新しい名前が今と同じなら何もしない
        class Rename < Operation
          def requires_complete? = true

          INDEX_PREFIX = Storage::ConfigFiles::INDEX_PREFIX

          private

          def run(edit)
            return rename_shortcut(edit) if edit.kind == 'shortcut'

            kind = kind_of(edit)
            item, file = find_item(kind, edit.name, file: edit.file)
            return outcome if edit.to == item.name

            check_name!(edit.to, 'edit.to', taken_names(kind) - [item.name])
            edit_file(file) { |text| name_edits(text, kind, edit.to) }
            references = []
            if kind.function
              references = text_references(kind.function, edit.name)
              replace_references(kind.function, edit.name, edit.to)
            end
            rename_file(kind, file, edit.to)
            outcome(references: references, verify: { file: file, path: ['name'] })
          end

          def name_edits(text, kind, name)
            doc = Storage::YamlDocument.parse(text)
            doc.range(['name']) ? doc.replace(['name'], name) : doc.insert(['name'], name, order: kind.keys)
          end

          # 番号の接頭辞（03_）と拡張子は保ち、slug だけを新しい名前に合わせる
          def rename_file(kind, file, name)
            base = File.basename(file)
            to = "#{File.dirname(file)}/#{base[INDEX_PREFIX, 1]}#{slug(kind, name)}#{File.extname(base)}"
            stem = to.delete_suffix(File.extname(to))
            return if to == file || Storage::ConfigFiles::EXTENSIONS.any? { |ext| changeset.exist?("#{stem}#{ext}") }

            changeset.rename(file, to)
          end

          def rename_shortcut(edit)
            require_shortcut!(edit.name)
            return outcome if edit.to == edit.name

            check_name!(edit.to, 'edit.to', shortcut_names - [edit.name])
            file = reading.shortcuts_file
            path = ['shortcuts', edit.name]
            edit_file(file) { |text| YamlKeys.new(text).rename_key(path, edit.to) }
            references = text_references('Shortcut', edit.name)
            replace_references('Shortcut', edit.name, edit.to)
            outcome(references: references, verify: { file: file, path: path })
          end
        end
      end
    end
  end
end
