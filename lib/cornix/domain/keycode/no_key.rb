# frozen_string_literal: true

require_relative '../keycode'

module Cornix
  module Domain
    module Keycode
      # KC_NO（何もしない）
      class NoKey < Data.define
        include Value
      end

      # KC_TRNS（下のレイヤーの割り当てを使う）
      class Transparent < Data.define
        include Value
      end

      NO_KEY = NoKey.new
      TRANSPARENT = Transparent.new
    end
  end
end
