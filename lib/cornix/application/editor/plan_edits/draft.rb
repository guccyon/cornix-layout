# frozen_string_literal: true

require_relative 'change'
require_relative 'version_conflict'
require_relative 'invalid_change'
require_relative 'not_local'
require_relative 'targets'
require_relative 'values'
require_relative 'state_check'

module Cornix
  module Application
    module Editor
      class PlanEdits
        # 未保存の変更（Change の並び）を、いま読んだ設定ファイルに当てた結果（profile/validate と profile/planEdits の共通の部分）。
        #
        #   draft = Draft.new(reading, settings_catalog).apply(base_versions, changes)
        #   draft.files    #=> [Draft::FileEdit(file:, base_version:, create:, edits: [Storage::TextEdit])]（変わるファイルだけ）
        #   draft.texts    #=> { file => 当てたあとのテキスト }
        #   draft.reading  #=> 当てたあとの中身で読み直した ProfileReading（検証用。ファイルは書かない）
        #
        # 確かめる順: baseVersions が今の版と違えば VersionConflict、宛先にできない Address（Targets）・その宛先でできない op・
        # 注記を書けない場所・値の型の違い（Values）・変更のあるファイルの baseVersions がなければ InvalidChange。
        # そのあと、ファイルごとに並びの順に 1 つずつ当てる。当てる直前の中身で並びの位置などを確かめ（StateCheck。InvalidChange）、
        # 値の部分だけで書き換えられなければ NotLocal。並びの位置は前の変更を当てたあとの中身で数えるので、
        # 位置の誤り（InvalidChange）が前の変更の NotLocal より後に分かることがある。
        #
        # 書き換えは protocol.md の 6.3 と 12.3（Storage::YamlDocument。set はもうある値の値の部分だけを置き換え、
        # まだない場所は position_map / data/qmk_settings.yaml / 各ファイルの項目の順の場所に足す。remove は行か並びの要素を消し、
        # insert / move は並びの要素の行を足す・動かす。注記は set_note / remove_note）。同じファイルへの変更は 1 つずつ当てて読み直し、
        # 2 つ以上なら最後に Storage::TextEdit.diff で元のテキストに対する書き換えにまとめる
        class Draft
          FileEdit = Data.define(:file, :base_version, :create, :edits) do
            def initialize(file:, base_version:, create:, edits:) = super(file:, base_version:, create:, edits: edits.dup.freeze)

            # protocol.md の 6.1 の files の 1 件の形
            def to_protocol = { file: file, baseVersion: base_version, create: create, edits: edits.map(&:to_protocol) }
          end
          Result = Data.define(:files, :texts, :reading) do
            def initialize(files:, texts:, reading:) = super(files: files.dup.freeze, texts: texts.dup.freeze, reading: reading)
          end
          # 宛先と書く値を決めた Change（index は changes の中の位置）
          Resolved = Data.define(:target, :change, :value, :index)

          def initialize(reading, settings_catalog)
            @reading = reading
            @targets = Targets.new(reading, settings_catalog)
            @values = Values.new(reading)
          end

          def apply(base_versions, changes)
            check_conflicts!(base_versions)
            resolved = changes.each_with_index.map { |change, i| resolve(change, i) }
            require_base_versions!(base_versions, resolved)
            texts = {}
            files = resolved.group_by { |r| r.target.file }.filter_map do |file, list|
              edit_file(file, list, texts)
            end
            Result.new(files: files, texts: texts, reading: texts.empty? ? @reading : @reading.with_files(texts))
          end

          private

          def check_conflicts!(base_versions)
            conflicts = base_versions.each_with_object({}) do |(file, version), h|
              current = @reading.files[file]
              h[file] = current unless current == version
            end
            raise VersionConflict, conflicts unless conflicts.empty?
          end

          def require_base_versions!(base_versions, resolved)
            missing = resolved.map { |r| r.target.file }.uniq.reject { |file| base_versions.key?(file) }
            return if missing.empty?

            raise InvalidChange.new('baseVersions', "変更のあるファイルの版が baseVersions にありません: #{missing.join(', ')}")
          end

          def resolve(change, index)
            target = @targets.fetch(change.file, change.path)
            unless target&.ops&.include?(change.op)
              raise InvalidChange.new("changes[#{index}].address", unknown_target(change, target))
            end
            if change.note? && !target.note
              raise InvalidChange.new("changes[#{index}].field", "注記を書けない場所です: #{change.file} の #{change.path.join('.')}")
            end

            Resolved.new(target: target, change: change, value: @values.for(target, change, index), index: index)
          end

          def unknown_target(change, target)
            where = "#{change.file} の #{change.path.join('.')}"
            return "変更の宛先を指せません: #{where}" unless target

            "#{where} には #{change.op} の変更はできません（できるもの: #{target.ops.join(', ')}）"
          end

          def edit_file(file, list, texts)
            original = @reading.text(file)
            create = original.nil?
            text = original || ''
            per_change = list.map do |resolved|
              edits = edits_for(text, resolved)
              text = Storage::TextEdit.apply(text, edits)
              edits
            end
            return nil if text == (original || '')

            texts[file] = text
            edits = per_change.size == 1 ? per_change.first : Storage::TextEdit.diff(original || '', text)
            FileEdit.new(file: file, base_version: @reading.files[file], create: create, edits: edits)
          end

          def edits_for(text, resolved)
            target = resolved.target
            change = resolved.change
            StateCheck.new(data_of(text)).call(target, change, resolved.index) if target.check || change.note?
            doc = Storage::YamlDocument.parse(text)
            path = target.path
            case change.op
            when :set then change.note? ? doc.set_note(path, resolved.value) : doc.insert(path, resolved.value, order: target.order)
            when :remove then change.note? ? doc.remove_note(path) : doc.remove(path)
            when :insert then doc.insert_item(path, change.index, resolved.value)
            when :move then doc.move_item(path, change.from, change.to)
            end
          rescue Storage::EditNotLocal => e
            raise NotLocal.new(address: { file: target.file, path: target.path }, reason: e.reason, message: e.message)
          end

          def data_of(text)
            Storage::YamlFile.parse(text)
          rescue Storage::YamlFile::Unreadable
            nil
          end
        end
      end
    end
  end
end
