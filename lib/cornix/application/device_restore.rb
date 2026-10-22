# frozen_string_literal: true

require_relative 'use_case'

module Cornix
  module Application
    # スナップショットからキーボードを戻す（cornix restore / device restore / MCP restore_backup）。
    #
    # path_or_name はスナップショットの名前・パス（Storage::SnapshotStore#resolve）。省略時は最新の pre-apply
    # （直前の apply の前の状態。なければ前の版の tmp/device_backups/ の最新）。
    # dry_run: true なら DeviceDiff と同じ PlanResult、偽なら DeviceApply と同じ ApplyOutcome を返す
    # （expected_token と confirm の扱いも DeviceApply と同じ）。
    # 書き込む前には現在の状態を pre-restore のスナップショットに残すので、それを指定して restore すると復元前に戻る
    class DeviceRestore < UseCase
      def call(path_or_name = nil, dry_run: false, expected_token: nil, confirm: nil, progress: nil)
        source = env.snapshot_store.resolve(path_or_name)
        return DeviceDiff.new(env).call(vil_path: source, progress: progress) if dry_run

        DeviceApply.new(env).call(vil_path: source, expected_token: expected_token, confirm: confirm,
                                 snapshot_kind: 'pre-restore', progress: progress)
      end
    end
  end
end
