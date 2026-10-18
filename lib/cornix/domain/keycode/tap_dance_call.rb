# frozen_string_literal: true

require_relative '../keycode'
require_relative '../checks'

module Cornix
  module Domain
    module Keycode
      # タップダンス（TD(0)〜TD(255)）。名前（TapDance('名前')）との対応は Profile が持つ
      class TapDanceCall < Data.define(:index)
        include Value
        RANGE = (0..255)

        def initialize(index:)
          Checks.integer!(index, RANGE, 'タップダンス番号')
          super
        end
      end
    end
  end
end
