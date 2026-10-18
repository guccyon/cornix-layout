# frozen_string_literal: true

require_relative 'use_case'

module Cornix
  module Application
    # 接続中のキーボードの情報（読み取りのみ）→ InfoResult
    class DeviceInfo < UseCase
      def call = env.open_device { |session| InfoResult.new(info: session.info) }
    end
  end
end
