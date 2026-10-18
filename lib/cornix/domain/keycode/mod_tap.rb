# frozen_string_literal: true

require_relative '../keycode'
require_relative '../checks'
require_relative '../modifier_set'
require_relative 'basic'

module Cornix
  module Domain
    module Keycode
      # タップで基本キー、ホールドで修飾キー（QMK の MT / *_T、0x2000〜0x3FFF）
      class ModTap < Data.define(:mods, :base)
        include Value

        def initialize(mods:, base:)
          Checks.instance!(mods, ModifierSet, '修飾キー')
          Checks.instance!(base, Basic, 'タップのキー')
          super
        end
      end
    end
  end
end
