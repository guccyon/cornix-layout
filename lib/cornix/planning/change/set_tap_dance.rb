# frozen_string_literal: true

module Cornix
  module Planning
    module Change
      # タップダンス 1 件（from / to は Image::TapDanceRecord）
      class SetTapDance < Data.define(:index, :from, :to)
        include Value

        def keycodes = [to.on_tap, to.on_hold, to.on_double_tap, to.on_tap_hold]
      end
    end
  end
end
