# frozen_string_literal: true

require_relative '../keycode'
require_relative '../checks'
require_relative '../modifier_set'
require_relative 'basic'

module Cornix
  module Domain
    module Keycode
      # 修飾キーを押しながらの基本キー（QMK の LSFT(kc) など、0x0100〜0x1FFF）
      class Modified < Data.define(:mods, :base)
        include Value

        def initialize(mods:, base:)
          Checks.instance!(mods, ModifierSet, '修飾キー')
          Checks.instance!(base, Basic, '修飾されるキー')
          super
        end
      end

    end
  end
end
