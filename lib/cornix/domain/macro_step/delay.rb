# frozen_string_literal: true

require_relative '../macro_step'

module Cornix
  module Domain
    module MacroStep
      # 待つ（ミリ秒）。Vial のバイト列は 2 バイト（(ms % 255) + 1, (ms / 255) + 1）なので 0〜65024
      class Delay < Data.define(:ms)
        include Value
        RANGE = (0..((254 * 255) + 254))

        def initialize(ms:) = super(ms: Checks.integer!(ms, RANGE, 'delay のミリ秒'))
        def kind = :delay
      end
    end
  end
end
