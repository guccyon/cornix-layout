# frozen_string_literal: true

require_relative 'device_handler'

module Cornix
  module Interface
    module EditorServer
      module Handlers
        # device/compare（読むだけ）: 保存済みのプロファイルを compile し、実機を読んで差分を返す（protocol.md の 14.3）
        class DeviceCompare < DeviceHandler
          rpc 'device/compare', servers: [:device]

          def run(params, context)
            context.device.compare(dir(params), progress: progress(context))
          end
        end
      end
    end
  end
end
