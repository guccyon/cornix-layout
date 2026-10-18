# frozen_string_literal: true

module Cornix
  module Planning
    module Change
      # コンボ 1 件（from / to は Image::ComboRecord）
      class SetCombo < Data.define(:index, :from, :to)
        include Value

        def keycodes = [*to.keys, to.output]
      end
    end
  end
end
