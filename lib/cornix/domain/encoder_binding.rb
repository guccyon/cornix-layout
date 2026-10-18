# frozen_string_literal: true

require_relative 'keycode'

module Cornix
  module Domain
    # エンコーダ 1 つ分の割り当て（プッシュ・反時計回り・時計回り）。使わない操作は Keycode::NO_KEY
    class EncoderBinding < Data.define(:push, :ccw, :cw)
      ACTIONS = %i[push ccw cw].freeze

      def initialize(push:, ccw:, cw:)
        super(
          push: Keycode.check!(push, 'エンコーダのプッシュ'),
          ccw: Keycode.check!(ccw, 'エンコーダの反時計回り'),
          cw: Keycode.check!(cw, 'エンコーダの時計回り')
        )
      end
    end
  end
end
