# frozen_string_literal: true

require_relative 'device_handler'

module Cornix
  module Interface
    module EditorServer
      module Handlers
        # device/compareBackup（読むだけ）: バックアップと実機の差分（protocol.md の 14.5）
        class DeviceCompareBackup < DeviceHandler
          rpc 'device/compareBackup', servers: [:device]

          def run(params, context)
            context.device.compare_backup(dir(params), backup(params), progress: progress(context))
          end
        end
      end
    end
  end
end
