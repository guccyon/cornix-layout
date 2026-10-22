# frozen_string_literal: true

require_relative '../handler'

module Cornix
  module Interface
    module EditorServer
      module Handlers
        # device のサーバー（cornix serve --device）のハンドラの基底（protocol.md の 14.）。
        # サブクラスは rpc 'device/…', servers: [:device] と #run(params, context) を書く。
        # 中身は context.device（Application::Editor::DeviceOperations）で、失敗を 14.7 の code にする:
        #
        #   ProfileNotFound → -32050 / UnknownBackup → -32602（field "backup"）/ CompileFailed → -32075（diagnostics）
        #   DeviceUnavailable → -32070（reason）/ PlanChanged → -32071 / WriteIncomplete → -32072（applied・backup）
        #   PlanRejected → -32073（keycodes）/ ほかの PlanError（レイヤー数・マクロのバッファなど）→ -32073（keycodes は空）
        #   ほかの DeviceError → -32603
        class DeviceHandler < Handler
          # DeviceUnavailable#reason → 約束の reason
          REASONS = { platform: 'platform', bridge: 'bridge', not_connected: 'notConnected', timeout: 'timeout' }.freeze

          def call(params, context)
            run(params, context)
          rescue Application::Editor::DeviceOperations::CompileFailed => e
            raise RpcError.new(ErrorCodes::COMPILE_FAILED, e.message, { diagnostics: e.diagnostics })
          rescue Application::Editor::DeviceOperations::UnknownBackup => e
            raise RpcError.new(ErrorCodes::INVALID_PARAMS, e.message, { field: 'backup' })
          rescue Cornix::DeviceUnavailable => e
            raise RpcError.new(ErrorCodes::DEVICE_UNAVAILABLE, e.message, { reason: REASONS.fetch(e.reason) })
          rescue Cornix::WriteIncomplete => e
            raise RpcError.new(ErrorCodes::WRITE_INCOMPLETE, e.message, { applied: e.applied, backup: e.backup })
          rescue Cornix::PlanChanged
            raise RpcError.new(ErrorCodes::PLAN_CHANGED, '比べたあとでファイルか実機が変わりました。もう一度比べてください')
          rescue Cornix::PlanRejected => e
            raise RpcError.new(ErrorCodes::PLAN_REJECTED, e.message, { keycodes: e.keycodes })
          rescue Cornix::PlanError => e
            raise RpcError.new(ErrorCodes::PLAN_REJECTED, e.message, { keycodes: [] })
          end

          def run(_params, _context) = raise(NotImplementedError)

          private

          def dir(params) = param(params, 'dir', String)

          def token(params) = param(params, 'token', String)

          def backup(params) = param(params, 'backup', String)

          # 進み具合を device/progress に流す（読む間は取り消しを拾う）
          def progress(context) = ->(phase, done, total) { context.progress(phase, done, total) }

          # 書き込みのメソッド: --allow-writes なしで起動したサーバーは断る（ADR 019）
          def writable!(context)
            return if context.allow_writes?

            raise RpcError.new(ErrorCodes::WRITES_NOT_ALLOWED,
                               '書き込みが許可されていません（設定 cornix.device.allowWrites が無効。--allow-writes なしで起動）')
          end
        end
      end
    end
  end
end
