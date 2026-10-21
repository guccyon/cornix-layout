# frozen_string_literal: true

require 'fileutils'
require_relative 'use_case'

module Cornix
  module Application
    # キーボードの状態を layout.vil 形式で読む（読み取りのみ）。output を渡すとそこへ保存する → ReadResult。
    # 読んだ状態はスナップショット（read）にも残す
    class DeviceRead < UseCase
      def call(output: nil)
        image = env.open_device { |session| read_device(session) }
        vil = env.vil_file.dump(image)
        if output
          FileUtils.mkdir_p(File.dirname(output))
          File.write(output, vil)
        end
        ReadResult.new(image: image, vil: vil, path: output)
      end
    end
  end
end
