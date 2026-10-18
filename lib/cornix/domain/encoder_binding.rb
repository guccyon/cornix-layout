# frozen_string_literal: true

require_relative 'checks'
require_relative 'keycode'

module Cornix
  module Domain
    # エンコーダ 1 つ分の割り当て（プッシュ・反時計回り・時計回り）。使わない操作は Keycode::NO_KEY。
    # notes は操作（:push / :ccw / :cw）=> 注記（デバイスには書かない）
    class EncoderBinding < Data.define(:push, :ccw, :cw, :notes)
      ACTIONS = %i[push ccw cw].freeze

      def initialize(push:, ccw:, cw:, notes: {})
        super(
          push: Keycode.check!(push, 'エンコーダのプッシュ'),
          ccw: Keycode.check!(ccw, 'エンコーダの反時計回り'),
          cw: Keycode.check!(cw, 'エンコーダの時計回り'),
          notes: Checks.notes!(notes, ACTIONS, 'エンコーダの注記')
        )
      end

      # { push: Keycode, ccw: ..., cw: ... }
      def actions = ACTIONS.to_h { |a| [a, public_send(a)] }

      # 操作の注記。なければ nil
      def note(action) = notes[action]
    end
  end
end
