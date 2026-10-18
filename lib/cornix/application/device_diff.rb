# frozen_string_literal: true

require_relative 'use_case'

module Cornix
  module Application
    # .vil（省略時は compile の出力 env.layout_path）とキーボードの差分を計画する（書き込みなし）→ PlanResult。
    # token は DeviceApply の expected_token に渡す確認トークン
    class DeviceDiff < UseCase
      def call(vil_path: nil)
        source = vil_path || env.layout_path
        target = env.vil_file.read(source)
        plan = env.open_device { |session| plan_for(session, target).last }
        plan_result(source, plan)
      end
    end
  end
end
