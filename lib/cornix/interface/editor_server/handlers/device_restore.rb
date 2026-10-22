# frozen_string_literal: true

require_relative 'device_handler'

module Cornix
  module Interface
    module EditorServer
      module Handlers
        # device/restore: バックアップの状態に戻す（device/apply と同じ流れ。protocol.md の 14.5）。
        # --allow-writes なしでは -32074（プロファイル・バックアップが分からなければ先に -32050・-32602）
        class DeviceRestore < DeviceHandler
          rpc 'device/restore', servers: [:device]

          def run(params, context)
            target = dir(params)
            name = backup(params)
            expected = token(params)
            context.device.check!(target, backup: name)
            writable!(context)
            context.device.restore(target, name, token: expected, progress: progress(context))
          end
        end
      end
    end
  end
end
