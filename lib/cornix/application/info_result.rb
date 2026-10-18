# frozen_string_literal: true

module Cornix
  module Application
    # DeviceInfo の結果。info は Device::Session#info（旧 Device::Keyboard#info と同じ項目）
    class InfoResult < Data.define(:info)
      def to_h = info
    end
  end
end
