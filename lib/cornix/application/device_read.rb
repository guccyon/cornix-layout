# frozen_string_literal: true

require_relative 'use_case'

module Cornix
  module Application
    # キーボードの状態を layout.vil 形式で読む（読み取りのみ）。output を渡すとそこへ保存する → ReadResult
    class DeviceRead < UseCase
      def call(output: nil)
        image = env.open_device { |session| reader(session).read }
        vil = env.vil_file.dump(image)
        File.write(output, vil) if output
        ReadResult.new(image: image, vil: vil, path: output)
      end
    end
  end
end
