# frozen_string_literal: true

module Cornix
  module Application
    module Editor
      class ItemEdits
        # 設定ディレクトリへの変更（ファイルの作成・書き換え・削除・改名）をメモリの上で積んだもの。ファイルは書かない。
        #
        #   changeset = Changeset.new(reading)
        #   changeset.write('macros/03_old.yml', text)          # 書き換え（なければ作る）
        #   changeset.create('macros/05_new.yml', text)
        #   changeset.delete('macros/04_unused.yml')
        #   changeset.rename('macros/03_old.yml', 'macros/03_new.yml')
        #   changeset.text('macros/03_old.yml')                 # 積んだあとの中身（消したファイルは nil）
        #   changeset.to_protocol    #=> protocol.md の 12.5 の files（積んだ順。変わらないファイルは入れない）
        #   changeset.reading(env)   #=> 積んだあとの中身で読み直した ProfileReading（検証と compile の照合用）
        #
        # ファイルはいつも元の名前（reading で読んだときの名前）で指す。改名は最後に 1 回だけ積む
        class Changeset
          Entry = Struct.new(:file, :original, :text, :create, :delete, :rename_to, :batches)

          def initialize(reading)
            @reading = reading
            @entries = {}
          end

          # 今の中身（積んだ変更を当てたもの。なければ nil）
          def text(file) = @entries.key?(file) ? @entries[file].text : @reading.text(file)

          def exist?(file) = !text(file).nil? || renamed_to?(file)

          # edits はその書き換え（前の中身での位置の TextEdit の並び）。分かっていれば渡す。
          # ファイルへの書き換えが 1 回だけなら、それをそのまま返す（2 回以上か edits がなければ元の中身との差分）
          def write(file, text, edits = nil)
            entry = entry(file)
            return if text == entry.text

            entry.text = text
            entry.batches << edits
            entry.create = true if entry.original.nil?
          end

          def create(file, text) = write(file, text)

          def delete(file)
            entry = entry(file)
            entry.text = nil
            entry.delete = true
          end

          def rename(file, to)
            return if to == file

            entry(file).rename_to = to
          end

          # 中身が変わる（作る・消す・改名を含む）ファイルの元の名前
          def touched = @entries.values.select { |e| changed?(e) }.map(&:file)

          # 作るファイル（元はなかったもの）
          def created = @entries.values.select { |e| changed?(e) && e.create }.map(&:file)

          def empty? = touched.empty?

          def to_protocol
            @entries.values.select { |e| changed?(e) }.map do |entry|
              h = { file: entry.file, baseVersion: @reading.files[entry.file], create: entry.create == true,
                    edits: edits(entry).map(&:to_protocol) }
              h[:delete] = true if entry.delete
              h[:renameTo] = entry.rename_to if entry.rename_to
              h
            end
          end

          # 積んだあとの中身で読み直した ProfileReading（ディスクは読まない）
          def reading(env)
            return @reading if empty?

            files = @reading.files.keys.each_with_object({}) do |file, h|
              text = @reading.text(file)
              h[file] = text.b unless text.nil?
            end
            @entries.each_value do |entry|
              files.delete(entry.file)
              next if entry.text.nil?

              files[entry.rename_to || entry.file] = entry.text.b
            end
            ProfileReading.new(env, source: Storage::FileSource::Memory.new(env.config_dir, files))
          end

          private

          def entry(file)
            @entries[file] ||= begin
              original = @reading.text(file)
              Entry.new(file: file, original: original, text: original, create: false, delete: false, rename_to: nil, batches: [])
            end
          end

          def renamed_to?(file) = @entries.values.any? { |e| e.rename_to == file }

          def changed?(entry) = entry.delete || entry.rename_to || entry.text != entry.original

          def edits(entry)
            return [] if entry.delete
            return [Storage::TextEdit.new(range: Storage::TextRange.at(0, 0), new_text: entry.text)] if entry.create
            return entry.batches.first if entry.batches.size == 1 && entry.batches.first

            Storage::TextEdit.diff(entry.original, entry.text)
          end
        end
      end
    end
  end
end
