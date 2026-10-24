# frozen_string_literal: true

require_relative 'use_case'

module Cornix
  module Application
    # キーボードの状態をスナップショット（種類 backup。tmp/snapshots/<日時>-backup/layout.vil）に保存する → BackupResult
    class DeviceBackup < UseCase
      def call
        image = env.open_device { |session| reader(session).read }
        BackupResult.new(path: env.snapshot_store.save(image, kind: 'backup'))
      end
    end
  end
end
