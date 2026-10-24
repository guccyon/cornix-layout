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

      # キーボードの状態を読み、スナップショット（read）に残す → Image::DeviceImage。
      # progress（省略可）は ->(phase, done, total) で、読む間は phase :read で呼ぶ（Device::Reader の単位）
      def read_device(session, progress: nil)
        image = reader(session).read(progress: progress && ->(done, total) { progress.call(:read, done, total) })
        env.snapshot_store.save(image, kind: 'read')
        image
      end

      def planner(session)
        policy = Device::ChangePolicy.new(catalog: env.catalog, describer: env.describer)
        Device::Planner.new(session, macro_codec: env.macro_codec, policy: policy)
      end

      def writer(session)
        Device::Writer.new(session, reader: reader(session), macro_codec: env.macro_codec, describer: env.describer)
      end

      def describe(changes) = changes.map { |change| env.describer.format_change(change) }

      # 目標の .vil を読み、現在のデバイスとの差分の Plan を作る → [現在の DeviceImage, Plan]
      def plan_for(session, target, progress: nil)
        current = read_device(session, progress: progress)
        [current, planner(session).plan(current: current, target: target)]
      end

      # 書き込み先のキーボード（キーボード定義の名前と、読んだ状態の uid）
      def keyboard(session, current)
        PlanResult::Keyboard.new(name: session.definition['name'].to_s, uid: current.meta['uid'])
      end

      # 省略時の目標（compile の出力）。まだ compile していなければ案内つきの ConfigError
      def compiled_vil
        path = env.layout_path
        return path if File.file?(path)

        raise ConfigError.new('がありません。先に cornix compile（または cornix status / apply）を実行してください', path: path)
      end

      def plan_result(source, plan, keyboard: nil)
        PlanResult.new(source: source, plan: plan, changes: describe(plan.changes), warnings: plan.warnings, keyboard: keyboard)
      end
    end
  end
end
