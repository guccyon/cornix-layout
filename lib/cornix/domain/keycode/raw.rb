# frozen_string_literal: true

require_relative '../keycode'
require_relative '../checks'

module Cornix
  module Domain
    module Keycode
      # 解釈できない 16bit 値。値を落とさずに往復させるために保持する
      class Raw < Data.define(:code)
        include Value
        RANGE = (0x0000..0xFFFF)

        def initialize(code:)
          Checks.integer!(code, RANGE, 'キーコードの値')
          super
        end
      end
    end
  end
end
