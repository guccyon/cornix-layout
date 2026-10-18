# frozen_string_literal: true

require_relative '../keycode'
require_relative '../checks'

module Cornix
  module Domain
    module Keycode
      # 基本キー（HID の usage 0x04〜0xFF）。名前はカタログから引く。
      class Basic < Data.define(:code)
        include Value
        RANGE = (0x02..0xFF)

        def initialize(code:)
          Checks.integer!(code, RANGE, '基本キーの値')
          super
        end
      end
    end
  end
end
