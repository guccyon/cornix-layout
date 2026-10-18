# frozen_string_literal: true

require_relative '../macro_step'

module Cornix
  module Domain
    module MacroStep
      # 押したままにする（keys を順に）
      class Down < Data.define(:keys)
        include KeyAction

        def initialize(keys:) = super(keys: check_keys!(keys))
        def kind = :down
      end
    end
  end
end
