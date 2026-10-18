# frozen_string_literal: true

require_relative '../keycode'
require_relative '../checks'

module Cornix
  module Domain
    module Keycode
      # 名前付きの特殊キー（QK_BOOT、USER00、KC_ASTG など）。名前はカタログから引く
      class Quantum < Data.define(:code)
        include Value
        RANGE = (0x0100..0xFFFF)

        def initialize(code:)
          Checks.integer!(code, RANGE, '特殊キーの値')
          super
        end
      end
    end
  end
end
