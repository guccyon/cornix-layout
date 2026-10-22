# frozen_string_literal: true

require_relative 'use_case'

module Cornix
  module Application
    # .vil（省略時は compile の出力 env.layout_path）とキーボードの差分を計画する（書き込みなし）→ PlanResult。
    # token は DeviceApply の expected_token に渡す確認トークン。
    # progress（省略可）は ->(phase, done, total)。読む間 phase :read で呼ぶ
    class DeviceDiff < UseCase
      def call(vil_path: nil, progress: nil)
        source = vil_path || compiled_vil
        target = env.vil_file.read(source)
        env.open_device do |session|
          current, plan = plan_for(session, target, progress: progress)
          plan_result(source, plan, keyboard: keyboard(session, current))
        end
      end
    end
  end
end
