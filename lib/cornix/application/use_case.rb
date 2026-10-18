# frozen_string_literal: true

module Cornix
  module Application
    # ユースケースの基底（デバイスの読み出し・計画・書き込みの部品を Environment から組み立てる）
    class UseCase
      attr_reader :env

      def initialize(env)
        @env = env
      end

      private

      def reader(session) = Device::Reader.new(session, macro_codec: env.macro_codec)

      def planner(session)
        policy = Device::ChangePolicy.new(catalog: env.catalog, describer: env.describer)
        Device::Planner.new(session, macro_codec: env.macro_codec, policy: policy)
      end

      def writer(session)
        Device::Writer.new(session, reader: reader(session), macro_codec: env.macro_codec, describer: env.describer)
      end

      def describe(changes) = changes.map { |change| env.describer.format_change(change) }

      # 目標の .vil を読み、現在のデバイスとの差分の Plan を作る → [現在の DeviceImage, Plan]
      def plan_for(session, target)
        current = reader(session).read
        [current, planner(session).plan(current: current, target: target)]
      end

      def plan_result(source, plan)
        PlanResult.new(source: source, plan: plan, changes: describe(plan.changes), warnings: plan.warnings)
      end
    end
  end
end
