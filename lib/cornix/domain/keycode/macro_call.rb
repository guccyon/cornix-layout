# frozen_string_literal: true

require_relative '../keycode'
require_relative '../checks'

module Cornix
  module Domain
    module Keycode
      # マクロの実行（M0〜M127。vial-qmk の QK_MACRO の範囲）。名前（Macro('名前')）との対応は Profile が持つ
      class MacroCall < Data.define(:index)
        include Value
        RANGE = (0..127)

        def initialize(index:)
          Checks.integer!(index, RANGE, 'マクロ番号')
          super
        end
      end
    end
  end
end
