# frozen_string_literal: true

require_relative 'device_handler'

module Cornix
  module Interface
    module EditorServer
      module Handlers
        # device/apply: compile し直して計画し直し、token が同じなら書き込む（protocol.md の 14.4）。
        # --allow-writes なしでは -32074（プロファイルが分からなければ先に -32050）
        class DeviceApply < DeviceHandler
          rpc 'device/apply', servers: [:device]

          def run(params, context)
            target = dir(params)
            expected = token(params)
            context.device.check!(target)
            writable!(context)
            context.device.apply(target, token: expected, progress: progress(context))
          end
        end
      end
    end
  end
end
