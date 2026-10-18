# frozen_string_literal: true

module Cornix
  module Planning
    module Change
      # キーマップの 1 キー（layer, row, col はマトリクスの物理座標）
      class SetKeycode < Data.define(:layer, :row, :col, :from, :to)
        include Value

        def keycodes = [to]
      end
    end
  end
end
