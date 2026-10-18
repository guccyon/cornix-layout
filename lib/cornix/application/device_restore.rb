# frozen_string_literal: true

require_relative 'use_case'

module Cornix
  module Application
    # バックアップからキーボードを戻す（旧 cornix device restore / MCP restore_backup）。
    #
    # path_or_name はバックアップのパス・ファイル名（拡張子は省略可）。省略時は最新のバックアップ。
    # dry_run: true なら DeviceDiff と同じ PlanResult、偽なら DeviceApply と同じ ApplyOutcome を返す
    # （expected_token と confirm の扱いも DeviceApply と同じ）。
    # 書き込む前には現在の状態もバックアップするので、続けてもう一度 restore すると復元前に戻る
    class DeviceRestore < UseCase
      def call(path_or_name = nil, dry_run: false, expected_token: nil, confirm: nil)
        source = env.backup_store.resolve(path_or_name)
        return DeviceDiff.new(env).call(vil_path: source) if dry_run

        DeviceApply.new(env).call(vil_path: source, expected_token: expected_token, confirm: confirm)
      end
    end
  end
end
