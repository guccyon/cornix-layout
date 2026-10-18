# frozen_string_literal: true

require_relative 'use_case'

module Cornix
  module Application
    # キーボードの状態を env.decompile_input（root/tmp/layout.vil）に読み出し、config/ にする → DecompileResult。
    # config/ にすでに設定があればキーボードを開かず、tmp/layout.vil も書き換えずに :config_exists を返す
    class Pull < UseCase
      def call
        input = env.decompile_input
        if Storage::ConfigFiles.populated?(env.config_dir)
          return DecompileResult.new(status: :config_exists, input: input, output_dir: env.config_dir)
        end

        DeviceRead.new(env).call(output: input)
        Decompile.new(env).call(input: input)
      end
    end
  end
end
