# frozen_string_literal: true

require_relative 'device_handler'

module Cornix
  module Interface
    module EditorServer
      module Handlers
        # device/backups: 戻す先のバックアップの一覧（新しい順。実機は読まない。protocol.md の 14.5）
        class DeviceBackups < DeviceHandler
          rpc 'device/backups', servers: [:device]

          def run(params, context) = context.device.backups(dir(params))
        end
      end
    end
  end
end
