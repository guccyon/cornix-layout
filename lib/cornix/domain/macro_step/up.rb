# frozen_string_literal: true

require_relative '../macro_step'

module Cornix
  module Domain
    module MacroStep
      # 離す（keys を順に）
      class Up < Data.define(:keys)
        include KeyAction

        def initialize(keys:) = super(keys: check_keys!(keys))
        def kind = :up
      end
    end
  end
end
