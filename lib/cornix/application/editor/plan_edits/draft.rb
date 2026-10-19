# frozen_string_literal: true

require_relative 'errors'
require_relative 'targets'

module Cornix
  module Application
    module Editor
      class PlanEdits
        # 画面での変更 1 つ（protocol.md の Change）。path は JSON の道筋（文字列か整数）、value は文字列・整数・真偽値
        Change = Data.define(:file, :path, :value)

        # 未保存の変更（Change の並び）を、いま読んだ設定ファイルに当てた結果（profile/validate と profile/planEdits の共通の部分）。
        #
        #   draft = Draft.new(reading, settings_catalog).apply(base_versions, changes)
        #   draft.files    #=> [Draft::FileEdit(file:, base_version:, create:, edits: [Storage::TextEdit])]（変わるファイルだけ）
        #   draft.texts    #=> { file => 当てたあとのテキスト }
        #   draft.reading  #=> 当てたあとの中身で読み直した ProfileReading（検証用。ファイルは書かない）
        #
        # 確かめる順: baseVersions が今の版と違えば VersionConflict、宛先にできない Address・値の型の違い・
        # 変更のあるファイルの baseVersions がなければ InvalidChange、値の部分だけで書き換えられなければ NotLocal。
        #
        # 書き換えは protocol.md の 6.3（Storage::YamlDocument#insert。もうある値は値の部分だけを置き換え、
        # まだない場所は position_map / data/qmk_settings.yaml の順の場所に足す）。同じファイルへの変更は 1 つずつ当てて読み直し、
        # 2 つ以上なら最後に Storage::TextEdit.diff で元のテキストに対する書き換えにまとめる。
        # QMK 設定の値は data/qmk_settings.yaml の型に直す（真偽値の設定は true / false か 0 / 1。
        # ファイルが 0 / 1 で書いていれば 0 / 1 で書き、同じ値なら書き換えない）
        class Draft
          FileEdit = Data.define(:file, :base_version, :create, :edits) do
            def to_h = { file: file, baseVersion: base_version, create: create, edits: edits.map(&:to_protocol) }
          end
          Result = Data.define(:files, :texts, :reading)

          INTEGER_TEXT = /\A[01]\z/

          def initialize(reading, settings_catalog)
            @reading = reading
            @targets = Targets.new(reading, settings_catalog)
          end

          def apply(base_versions, changes)
            check_versions!(base_versions)
            resolved = changes.each_with_index.map { |change, i| resolve(change, i) }
            check_base_versions!(base_versions, resolved)
            texts = {}
            files = resolved.group_by { |target, _| target.file }.filter_map do |file, list|
              edit_file(file, list, texts)
            end
            Result.new(files: files, texts: texts, reading: texts.empty? ? @reading : @reading.with_files(texts))
          end

          private

          def check_versions!(base_versions)
            conflicts = base_versions.each_with_object({}) do |(file, version), h|
              current = @reading.files[file]
              h[file] = current unless current == version
            end
            raise VersionConflict, conflicts unless conflicts.empty?
          end

          def check_base_versions!(base_versions, resolved)
            missing = resolved.map { |target, _| target.file }.uniq.reject { |file| base_versions.key?(file) }
            return if missing.empty?

            raise InvalidChange.new('baseVersions', "変更のあるファイルの版が baseVersions にありません: #{missing.join(', ')}")
          end

          # [宛先, 書く値]
          def resolve(change, index)
            target = @targets.fetch(change.file, change.path)
            unless target
              raise InvalidChange.new("changes[#{index}].address",
                                      "変更の宛先を指せません: #{change.file} の #{change.path.join('.')}")
            end

            [target, value_for(target, change.value, index)]
          end

          def value_for(target, value, index)
            return setting_value(target, value, index) if target.setting?
            return value if value.is_a?(String)

            raise InvalidChange.new("changes[#{index}].value", 'キーの値は表記の文字列にしてください')
          end

          def setting_value(target, value, index)
            definition = target.setting
            if definition.boolean?
              flag = { true => true, false => false, 1 => true, 0 => false }.fetch(value) do
                raise InvalidChange.new("changes[#{index}].value", "#{definition.name} の値は true か false にしてください")
              end
              return written_as_integer?(target) ? (flag ? 1 : 0) : flag
            end
            return value if value.is_a?(Integer)

            raise InvalidChange.new("changes[#{index}].value", "#{definition.name} の値は整数にしてください")
          end

          # 真偽値の設定を、ファイルが 0 / 1 で書いているか
          def written_as_integer?(target)
            node_text = @reading.document(target.file)&.scalar(target.path)
            !node_text.nil? && INTEGER_TEXT.match?(node_text)
          end

          def edit_file(file, list, texts)
            original = @reading.text(file)
            create = original.nil?
            text = original || ''
            per_change = list.map do |target, value|
              edits = edits_for(text, target, value)
              text = Storage::TextEdit.apply(text, edits)
              edits
            end
            return nil if text == (original || '')

            texts[file] = text
            edits = per_change.size == 1 ? per_change.first : Storage::TextEdit.diff(original || '', text)
            FileEdit.new(file: file, base_version: @reading.files[file], create: create, edits: edits)
          end

          def edits_for(text, target, value)
            Storage::YamlDocument.parse(text).insert(target.path, value, order: target.order)
          rescue Storage::EditNotLocal => e
            raise NotLocal.new(address: { file: target.file, path: target.path }, reason: e.reason, message: e.message)
          end
        end
      end
    end
  end
end
