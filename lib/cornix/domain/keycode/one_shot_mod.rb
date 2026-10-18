# frozen_string_literal: true

require_relative '../keycode'
require_relative '../checks'
require_relative '../modifier_set'
require_relative 'basic'

module Cornix
  module Domain
    module Keycode
      # 修飾キーのワンショット（QMK の OSM、0x52A0〜0x52BF）
      class OneShotMod < Data.define(:mods)
        include Value

        def initialize(mods:)
          Checks.instance!(mods, ModifierSet, '修飾キー')
          super
        end
      end
    end
  end
end
