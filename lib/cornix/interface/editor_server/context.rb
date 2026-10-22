# frozen_string_literal: true

module Cornix
  module Interface
    module EditorServer
      # ハンドラに渡すもの。開いているプロファイル（workbench）、サーバーから拡張への通知、標準エラー出力へのログ
      #
      #   context.workbench                       #=> Application::Editor::Workbench（編集のサーバー）
      #   context.device                          #=> Application::Editor::DeviceOperations（device のサーバー。編集のサーバーでは nil）
      #   context.allow_writes?                   #=> --allow-writes を付けて起動したか（device のサーバー）
      #   context.notify('profile/didChange', { profileId: 'p1', ... })
      #   context.progress(:read, 12, 560)        # device/progress を送る（読む間は取り消しを拾う。Server の progress）
      #   context.log('...')                      # 出力パネル「Cornix」に出る（標準出力は JSON-RPC 専用）
      class Context
        attr_reader :workbench, :device

        def initialize(notifier:, logger:, workbench: nil, device: nil, allow_writes: false, progress: nil)
          @workbench = workbench
          @device = device
          @allow_writes = allow_writes
          @notifier = notifier
          @logger = logger
          @progress = progress
        end

        def device? = !@device.nil?

        def allow_writes? = @allow_writes == true

        def notify(method, params) = @notifier.call(method, params)

        def progress(phase, done, total) = @progress&.call(phase, done, total)

        def log(message) = @logger.call(message)
      end
    end
  end
end
