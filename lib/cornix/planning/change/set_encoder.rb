# frozen_string_literal: true

module Cornix
  module Planning
    module Change
      # エンコーダ 1 方向の回転（clockwise: true = 時計回り / false = 反時計回り）
      class SetEncoder < Data.define(:layer, :index, :clockwise, :from, :to)
        include Value

        def keycodes = [to]
      end
    end
  end
end
