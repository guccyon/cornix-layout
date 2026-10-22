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
require_relative 'item_edits/expand_preset'
require_relative 'item_edits/indexing'

module Cornix
  module Application
    module Editor
      # 項目の追加・削除・名前の変更・位置の名前の変更・preset の展開を、ファイルの作成・削除・改名と書き換えにする
      # （protocol.md の 12.5 と 13.1 の profile/planItemEdit）。ファイルは書かない。
      #
      #   ItemEdits.new(workbench).call('p1', base_versions: { 'macros/03_old.yml' => 'sha256:…' },
      #                                       edit: ItemEdits::Edit.new(op: 'rename', kind: 'macro', name: 'Old', to: 'New'))
      #   #=> { files: [{ file:, baseVersion:, create:, edits:, delete?: true, renameTo?: }],
      #   #     references: [{ file:, path: }], diagnostics: [Diagnostic] }
      #
      # 設定ディレクトリをいま読み、操作（Create / Delete / Rename / RenamePosition / ExpandPreset）をメモリの上で当てる。
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
      # 3. 名前の変更・位置の名前の変更・preset の展開は、前後の compile の結果（16bit 値）を比べ、違えば Unverified（-32061 の reason "verify"）
      #
      # v0.5（protocol.md の 15.3）: use / unuse / setIndex と create（shortcut）はファイルの書き換えではなく、
      # 未保存の変更に積む Change の並び（changes）を返す（files は []。plan_pending）
      class ItemEdits
        OPERATIONS = { 'create' => Create, 'delete' => Delete, 'rename' => Rename, 'renamePosition' => RenamePosition,
                       'expandPreset' => ExpandPreset, 'use' => Use, 'unuse' => Unuse, 'setIndex' => SetIndex }.freeze
        PENDING_OPS = %w[use unuse setIndex].freeze

        # 未保存の変更に積む操作か（v0.5。protocol.md の 15.3）
        def self.pending?(edit) = PENDING_OPS.include?(edit.op) || (edit.op == 'create' && edit.kind == 'shortcut')

        def initialize(workbench)
          @workbench = workbench
        end

        # changes は今の未保存の変更（PlanEdits::Change の並び）。未保存の変更に積む操作（pending?）だけが使う
        def call(id, base_versions:, edit:, changes: [])
          env = @workbench.fetch(id).env
          reading = ProfileReading.read(env)
          return plan_pending(env, reading, base_versions, edit, changes) if self.class.pending?(edit)

          outcome = plan(reading, env, base_versions, edit)
          changeset = outcome.changeset
          check_conflicts!(reading, base_versions.slice(*changeset.touched))
          require_base_versions!(base_versions, changeset)
          after = changeset.reading(env)
          verify!(env, reading, after, outcome.verify, edit.op) if outcome.verify && !changeset.empty?
          { files: changeset.to_protocol, references: outcome.references,
            diagnostics: Diagnostics.new(after, env.capabilities).call }
        end

        private

        # current は操作を決める中身（未保存の変更を当てたもの。省けば reading）。版の食い違いはいつもディスクの reading と比べる
        def plan(reading, env, base_versions, edit, current = reading)
          OPERATIONS.fetch(edit.op).new(current, env).call(edit)
        rescue PlanEdits::InvalidChange, PlanEdits::NotLocal
          check_conflicts!(reading, base_versions)
          raise
        end

        # v0.5（protocol.md の 15.3）: use / unuse / setIndex と create（shortcut）。今の未保存の変更（pending）を当てた状態で決め、
        # 未保存の変更に積む Change の並びを返す（files は []）。baseVersions を比べるのは返す Change の宛先のファイルだけ
        # （まだないファイル（shortcuts.yaml）は baseVersions になくてよい）。diagnostics は pending と返す Change を当てたあとの検証の結果。
        # setIndex は、書き換えの前後で参照の指す先（マクロ・タップダンスのファイル）が変わらないことを確かめ、違えば Unverified
        def plan_pending(env, reading, base_versions, edit, pending)
          current = draft(reading, env, pending)
          outcome = plan(reading, env, base_versions, edit, current)
          touched = outcome.changes.map(&:file).uniq
          check_conflicts!(reading, base_versions.slice(*touched))
          missing = touched.reject { |file| base_versions.key?(file) || reading.files[file].nil? }
          unless missing.empty?
            raise PlanEdits::InvalidChange.new('baseVersions', "書き換えるファイルの版が baseVersions にありません: #{missing.join(', ')}")
          end

          after = draft(reading, env, pending + outcome.changes)
          verify_targets!(current, after, outcome.verify, edit.op) if outcome.verify
          { files: [], changes: outcome.changes.map(&:to_protocol), references: outcome.references,
            diagnostics: Diagnostics.new(after, env.capabilities).call }
        end

        # reading に changes（PlanEdits::Change の並び）を当てて読み直したもの（profile/validate と同じ書き換え。ファイルは書かない）。
        # 版はここでは比べない（照合は返す Change の宛先だけ）
        def draft(reading, env, changes)
          return reading if changes.empty?

          versions = changes.map(&:file).uniq.to_h { |file| [file, reading.files[file]] }
          PlanEdits::Draft.new(reading, env.settings_catalog).apply(versions, changes).reading
        end

        # 番号の変更の前後で、どの欄も同じ項目（マクロ・タップダンスはそのファイル、ほかは 16bit の値そのもの）を指すか。
        # 前に定義のない番号を指していた欄（もとから壊れている参照）は比べない
        def verify_targets!(before, after, address, op)
          expected = targets(before)
          actual = after.complete? ? targets(after) : {}
          ok = expected.all? { |slot, target| target.nil? || actual[slot] == target }
          raise Unverified.new(address: address, op: op) unless ok
        end

        # { Address => 指す先 }（指す先は [:macro, ファイル] / [:tapDance, ファイル] か Keycode。定義のない番号なら nil）
        def targets(reading)
          profile = reading.profile
          files = { Domain::Keycode::MacroCall => item_files(reading, profile.macros, 'macros'),
                    Domain::Keycode::TapDanceCall => item_files(reading, profile.tap_dances, 'tap_dances') }
          Slots.new(reading).all.to_h do |slot|
            keycode = slot.keycode
            table = files[keycode.class]
            [slot.address, table ? table[keycode.index]&.then { |file| [keycode.class, file] } : keycode]
          end
        end

        # 番号 => ファイル（同じ番号が重なれば先のもの）
        def item_files(reading, items, collection)
          items.each_with_index.each_with_object({}) do |(item, i), h|
            h[item.index] ||= reading.repository.address("#{collection}[#{i}]").first
          end
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

        def verify!(env, before, after, address, op)
          expected = env.mapper.to_image(before.profile)
          actual = begin
            after.complete? ? env.mapper.to_image(after.profile) : nil
          rescue Cornix::Error
            nil
          end
          raise Unverified.new(address: address, op: op) unless actual == expected
        end
      end
    end
  end
end
