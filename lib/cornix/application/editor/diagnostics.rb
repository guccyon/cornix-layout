# frozen_string_literal: true

module Cornix
  module Application
    module Editor
      # 読んだプロファイル（ProfileReading）の検証の結果を protocol.md の Diagnostic の Hash にする。
      #
      #   Diagnostics.new(reading, capabilities).call
      #   #=> [{ severity: "error", message:, source: "structure", address: { file:, path: }, range: }, ...]
      #
      # 構造検証（読めなかったとき）: Storage::Problem ごと。位置（location）を道筋にして Address にし、注記付きの形の .key は外す。
      #   位置がなければ file だけ、ファイルもなければ（どのファイルとも言えない問題）どちらも省く。
      #   shortcuts.yaml の問題は位置の文字列から道筋を正しく戻せないことがある（名前に . [ ] を含む）ので file だけにする
      # 意味検証（読めたとき）: Profile#diagnostics のモデル内のパスを ConfigRepository#address で Address にする。
      #   ファイル全体（道筋が空）なら file だけ、一覧全体（macros など）なら file に "macros/"
      # 未使用のファイル（index のないもの。issue #85）の構造の問題: 読めたかどうかに関係なく、構造検証と同じ形の warning にする
      #   （開けなくしない。未使用の項目を拡張で扱うのは #105）
      # range は Address の値の部分（YamlDocument#range）。分からなければ省く
      class Diagnostics
        def initialize(reading, capabilities)
          @reading = reading
          @capabilities = capabilities
        end

        def call
          found =
            if @reading.ok?
              @reading.profile.diagnostics(@capabilities).map { |diagnostic| semantic(diagnostic) }
            else
              @reading.problems.map { |problem| structure(problem) }
            end
          found + @reading.unused.flat_map(&:problems).map { |problem| structure(problem, 'warning', UNUSED_NOTE) }
        end

        UNUSED_NOTE = Validate::UNUSED_NOTE

        private

        def structure(problem, severity = 'error', note = '')
          base = { severity: severity, message: problem.message + note, source: 'structure' }
          file = problem.file
          return base if file.nil?

          path = problem.path
          return base.merge(file: file) if path.empty? || shortcuts?(file)

          located(base, file, strip_note_key(file, path))
        end

        def semantic(diagnostic)
          base = { severity: diagnostic.severity.to_s, message: diagnostic.message, source: 'semantic' }
          file, path = @reading.repository.address(diagnostic.path)
          if file.nil?
            located = @reading.repository.locate(diagnostic).path
            return located.end_with?('/') ? base.merge(file: located) : base
          end
          return base.merge(file: file) if path.empty?

          located(base, file, path)
        end

        def located(base, file, path)
          range = @reading.document(file)&.range(path)
          base.merge(address: { file: file, path: path }, range: range&.to_protocol).compact
        end

        def shortcuts?(file) = File.basename(file, '.*') == Storage::ConfigFiles::SHORTCUTS && File.dirname(file) == '.'

        # 注記付きの形（{ key:, note: }）の key を指す道筋なら、割り当ての場所まで（Address に .key を付けない）
        def strip_note_key(file, path)
          return path unless path.last == 'key' && path.size > 1

          parent = path[0...-1].reduce(@reading.data(file)) do |node, key|
            case node
            when Hash then node.fetch(key) { node[key.to_s] }
            when Array then key.is_a?(Integer) ? node[key] : nil
            end
          end
          assignment = parent.is_a?(Hash) && parent.key?('key') &&
                       (parent.keys - Storage::Schema::KeycodeField::ASSIGNMENT_KEYS).empty?
          assignment ? path[0...-1] : path
        end
      end
    end
  end
end
