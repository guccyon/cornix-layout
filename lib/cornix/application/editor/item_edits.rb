# frozen_string_literal: true

require_relative 'profile_reading'
require_relative 'diagnostics'
require_relative 'plan_edits'
require_relative 'item_edits/edit'
require_relative 'item_edits/unverified'
require_relative 'item_edits/create'
require_relative 'item_edits/delete'
require_relative 'item_edits/rename'
require_relative 'item_edits/rename_position'

module Cornix
  module Application
    module Editor
      # 項目の追加・削除・名前の変更・位置の名前の変更を、ファイルの作成・削除・改名と書き換えにする
      # （protocol.md の 12.5 の profile/planItemEdit）。ファイルは書かない。
      #
      #   ItemEdits.new(workbench).call('p1', base_versions: { 'macros/03_old.yml' => 'sha256:…' },
      #                                       edit: ItemEdits::Edit.new(op: 'rename', kind: 'macro', name: 'Old', to: 'New'))
      #   #=> { files: [{ file:, baseVersion:, create:, edits:, delete?: true, renameTo?: }],
      #   #     references: [{ file:, path: }], diagnostics: [Diagnostic] }
      #
      # 設定ディレクトリをいま読み、操作（Create / Delete / Rename / RenamePosition）をメモリの上で当てる。
      # files は中身が変わるファイル（作る・消す・改名も）だけで、操作の対象のファイルが先、参照を置き換えたファイルはその後
      # （設定ファイルの読んだ順）。edits は今のファイルでの位置（作るファイルは 0 行 0 列に中身すべて）。
      # diagnostics は当てたあとの中身の検証の結果（ValidateDraft と同じ）。
      #
      # 確かめる順（失敗はすべて PlanEdits と同じ例外。Interface が -32060 / -32602 / -32061 にする）:
      # 1. 操作の宛先と名前（InvalidChange）・局所的に書き換えられるか（NotLocal）。
      #    どちらかで失敗したときは、先に baseVersions のすべてのファイルを今の版と比べ、違えば VersionConflict
      #    （画面が古い中身を見ていたせいで名前が見つからないときなどに、版の食い違いとして知らせる）
      # 2. 書き換えるファイルだけ baseVersions を今の版と比べる（VersionConflict）。今あるファイルが baseVersions になければ
      #    InvalidChange（field "baseVersions"）。新しく作るファイルは書かなくてよい（書くなら null）
      # 3. 名前の変更・位置の名前の変更は、前後の compile の結果（16bit 値）を比べ、違えば Unverified（-32061 の reason "verify"）
      class ItemEdits
        OPERATIONS = { 'create' => Create, 'delete' => Delete, 'rename' => Rename, 'renamePosition' => RenamePosition }.freeze

        def initialize(workbench)
          @workbench = workbench
        end

        def call(id, base_versions:, edit:)
          env = @workbench.fetch(id).env
          reading = ProfileReading.read(env)
          outcome = plan(reading, env, base_versions, edit)
          changeset = outcome.changeset
          check_conflicts!(reading, base_versions.slice(*changeset.touched))
          require_base_versions!(base_versions, changeset)
          after = changeset.reading(env)
          verify!(env, reading, after, outcome.verify) if outcome.verify && !changeset.empty?
          { files: changeset.to_protocol, references: outcome.references,
            diagnostics: Diagnostics.new(after, env.capabilities).call }
        end

        private

        def plan(reading, env, base_versions, edit)
          OPERATIONS.fetch(edit.op).new(reading, env).call(edit)
        rescue PlanEdits::InvalidChange, PlanEdits::NotLocal
          check_conflicts!(reading, base_versions)
          raise
        end

        def check_conflicts!(reading, base_versions)
          conflicts = base_versions.each_with_object({}) do |(file, version), h|
            current = reading.files[file]
            h[file] = current unless current == version
          end
          raise PlanEdits::VersionConflict, conflicts unless conflicts.empty?
        end

        def require_base_versions!(base_versions, changeset)
          missing = (changeset.touched - changeset.created).reject { |file| base_versions.key?(file) }
          return if missing.empty?

          raise PlanEdits::InvalidChange.new('baseVersions', "書き換えるファイルの版が baseVersions にありません: #{missing.join(', ')}")
        end

        def verify!(env, before, after, address)
          expected = env.mapper.to_image(before.profile)
          actual = begin
            after.ok? ? env.mapper.to_image(after.profile) : nil
          rescue Cornix::Error
            nil
          end
          raise Unverified.new(address: address) unless actual == expected
        end
      end
    end
  end
end
