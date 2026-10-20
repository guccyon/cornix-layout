# frozen_string_literal: true

module Cornix
  module Interface
    module EditorServer
      # ハンドラに渡すもの。開いているプロファイル（workbench）、サーバーから拡張への通知、標準エラー出力へのログ
      #
      #   context.workbench                       #=> Application::Editor::Workbench
      #   context.notify('profile/didChange', { profileId: 'p1', ... })
      #   context.log('...')                      # 出力パネル「Cornix」に出る（標準出力は JSON-RPC 専用）
      class Context
        attr_reader :workbench

        def initialize(workbench:, notifier:, logger:)
          @workbench = workbench
          @notifier = notifier
          @logger = logger
        end

        def notify(method, params) = @notifier.call(method, params)

        def log(message) = @logger.call(message)
      end
    end
  end
end
