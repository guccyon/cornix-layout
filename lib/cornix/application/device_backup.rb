# frozen_string_literal: true

require_relative 'use_case'

module Cornix
  module Application
    # キーボードの状態をバックアップの置き場（tmp/device_backups/）に保存する → BackupResult
    class DeviceBackup < UseCase
      def call
        image = env.open_device { |session| reader(session).read }
        BackupResult.new(path: env.backup_store.save(image))
      end
    end
  end
end
