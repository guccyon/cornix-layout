# frozen_string_literal: true

require_relative '../macro_step'

module Cornix
  module Domain
    module MacroStep
      # 押して離す（keys を順に）
      class Tap < Data.define(:keys)
        include KeyAction

        def initialize(keys:) = super(keys: check_keys!(keys))
        def kind = :tap
      end
    end
  end
end
