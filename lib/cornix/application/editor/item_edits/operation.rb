# frozen_string_literal: true

require_relative 'changeset'
require_relative 'kind'
require_relative 'slots'
require_relative 'yaml_keys'

module Cornix
  module Application
    module Editor
      class ItemEdits
        # 項目の操作 1 つの基底（Create / Delete / Rename / RenamePosition）。
        #
        #   outcome = Rename.new(reading, env).call(edit)
        #   outcome.changeset    #=> Changeset（メモリの上の変更）
        #   outcome.references   #=> [Address]（書き換える・壊れる参照の場所）
        #   outcome.verify       #=> 前後の compile の結果を比べるときの名前の場所（{ file:, path: }）。比べないなら nil
        #
        # 宛先や名前の誤りは PlanEdits::InvalidChange（field は "edit.name" など）、局所的に書き換えられなければ
        # PlanEdits::NotLocal。どちらもファイルは書かない
        class Operation
          Outcome = Data.define(:changeset, :references, :verify) do
            def initialize(changeset:, references: [], verify: nil) = super(changeset:, references: references.dup.freeze, verify:)
          end

          InvalidChange = PlanEdits::InvalidChange
          NAME_FIELDS = { name: 'edit.name', to: 'edit.to' }.freeze

          def initialize(reading, env)
            @reading = reading
            @env = env
            @changeset = Changeset.new(reading)
          end

          def call(edit)
            unless @reading.ok?
              raise InvalidChange.new('edit', 'プロファイルが構造検証で読めないので、項目を操作できません（先にテキストで直してください）')
            end

            run(edit)
          end

          private

          attr_reader :reading, :env, :changeset

          def profile = @reading.profile

          def run(_edit) = raise(NotImplementedError)

          def outcome(references: [], verify: nil) = Outcome.new(changeset: changeset, references: references, verify: verify)

          def kind_of(edit) = KINDS.fetch(edit.kind)

          # 名前の決まり（空でない・前後の空白なし・改行なし・既存の名前と重ならない）
          def check_name!(name, field, taken)
            problem =
              if name.strip.empty? then '名前が空です'
              elsif name != name.strip then '名前の前後に空白があります'
              elsif name.match?(/[\r\n]/) then '名前に改行があります'
              elsif taken.include?(name) then "同じ名前がもうあります: #{name}"
              end
            raise InvalidChange.new(field, problem) if problem
          end

          # 名前の項目と、そのファイル（設定ディレクトリからの相対パス）。
          # レイヤーは名前が重なってよく（空のレイヤーはどれも Empty など）、番号のないレイヤーも予定している（#85）ので、
          # file があればファイルで探す（issue #84。ファイルのパスは設定ディレクトリの中で一意）
          def find_item(kind, name, file: nil)
            items = kind.items(profile)
            files = items.each_index.map { |i| reading.repository.address("#{kind.collection}[#{i}]").first }
            if file.nil?
              position = items.index { |item| item.name == name }
              raise InvalidChange.new('edit.name', "#{kind.label}「#{name}」がありません") unless position
            else
              position = files.index(file)
              raise InvalidChange.new('edit.file', "#{kind.label}のファイル #{file} がありません") unless position
            end

            [items[position], files[position]]
          end

          # 重なってはいけない名前（レイヤーの名前は重なってよい。ファイル名は番号が付くので分かれる）
          def taken_names(kind) = kind.name == 'layer' ? [] : kind.items(profile).map(&:name)

          def shortcut_names = profile.shortcuts.entries.keys

          def require_shortcut!(name)
            return if shortcut_names.include?(name)

            raise InvalidChange.new('edit.name', "ショートカット「#{name}」が shortcuts.yaml にありません")
          end

          # file の中身を、YamlDocument / YamlKeys の書き換えを当てたものにする。
          # 局所的に書き換えられなければ PlanEdits::NotLocal（address はそのファイルの道筋）
          def edit_file(file)
            text = changeset.text(file) || ''
            edits = Array(yield(text)).compact
            changeset.write(file, Storage::TextEdit.apply(text, edits), edits) unless edits.empty?
          rescue Storage::EditNotLocal => e
            raise PlanEdits::NotLocal.new(address: { file: file, path: e.path }, reason: e.reason, message: e.message)
          end

          # すべての設定ファイルの function('old') を function('new') にする（テキストの置き換え。
          # Storage::ConfigEditor.replace_references_in と同じ）。書き換えは参照 1 つずつの範囲
          def replace_references(function, old_name, new_name)
            pattern = Storage::ConfigEditor.reference_pattern(function, old_name)
            reading.files.each_key do |file|
              text = changeset.text(file) or next
              edits = reference_edits(text, pattern, function, old_name, new_name)
              changeset.write(file, Storage::TextEdit.apply(text, edits), edits) unless edits.empty?
            end
          end

          def reference_edits(text, pattern, function, old_name, new_name)
            body = text.delete_prefix(Storage::YamlFile::BOM)
            lines = nil
            edits = []
            body.scan(pattern) do
              match = Regexp.last_match
              lines ||= Storage::YamlDocument::LineIndex.new(body)
              start_line, start_character = lines.position(match.begin(0))
              end_line, end_character = lines.position(match.end(0))
              range = Storage::TextRange.new(start_line: start_line, start_character: start_character,
                                             end_line: end_line, end_character: end_character)
              new_text = Storage::ConfigEditor.replace_references_in(match[0], function, old_name, new_name)
              edits << Storage::TextEdit.new(range: range, new_text: new_text)
            end
            edits
          end

          def slots = @slots ||= Slots.new(reading).all

          # 書いてある表記に function('name') の参照がある欄の Address
          def text_references(function, name)
            pattern = Storage::ConfigEditor.reference_pattern(function, name)
            slots.select { |slot| slot.text&.match?(pattern) }.map(&:address)
          end

          # ファイル名の slug（ASCII の英数字を小文字にして、ほかを _ にまとめたもの。残らなければ種類の名前）
          def slug(kind, name)
            slug = Storage::ConfigFiles.sanitize(name)
            slug.empty? ? kind.fallback : slug
          end
        end
      end
    end
  end
end
