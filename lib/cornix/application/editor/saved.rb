# frozen_string_literal: true

require_relative 'snapshot'
require_relative 'file_changes'

module Cornix
  module Application
    module Editor
      # 拡張が書き換えを当てて保存した知らせ（protocol.md の 6.4 の profile/saved）を受けて読み直す。
      #
      #   result = Saved.new(workbench).call('p1', files: { 'layers/0_base.yml' => 'sha256:77c0…' })
      #   result.snapshot   #=> ProfileSnapshot（profile/open の result と同じ形）
      #   result.changed    #=> {}（知らされた版と読み直した版が同じ）か { file => 読み直した版 }（profile/didChange で知らせる）
      #
      # 設定ディレクトリを読み直し（Snapshot）、読み直した版を知っている版にする。
      # 知らされた版を知っている版に重ねたもの（保存した結果、こうなっているはずの版）と読み直した版を比べ、
      # 違うファイル（保存の直後にさらに外で変わった、知らされていないファイルが外で変わった）を changed にする。
      # files のうち設定ファイルでないもの（知っている版にも読み直した版にもないもの）は見ない
      class Saved
        Result = Data.define(:snapshot, :changed) do
          def changed? = !changed.empty?

          # profile/didChange の params
          def notification = { profileId: snapshot[:profileId], files: changed, snapshot: snapshot }
        end

        def initialize(workbench)
          @workbench = workbench
        end

        def call(id, files:)
          known = @workbench.versions(id).dup
          snapshot = Snapshot.new(@workbench).call(id)
          relevant = files.select { |file, _| known.key?(file) || snapshot[:files].key?(file) }
          Result.new(snapshot: snapshot, changed: FileChanges.diff(known.merge(relevant), snapshot[:files]))
        end
      end
    end
  end
end
