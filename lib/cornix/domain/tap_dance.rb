# frozen_string_literal: true

require_relative 'checks'
require_relative 'keycode'
require_relative 'keycode/tap_dance_call'

module Cornix
  module Domain
    # タップダンス 1 件。index は TD(0)〜TD(255) の番号。使わない動作は Keycode::NO_KEY。
    # notes は動作（:on_tap など）=> 注記（デバイスには書かない）。
    # 番号がデバイスの件数に収まるか、番号・名前の重複がないかは Profile#diagnostics で検査する
    class TapDance < Data.define(:index, :name, :description, :on_tap, :on_hold, :on_double_tap, :on_tap_hold,
                                 :tapping_term, :notes)
      ACTIONS = %i[on_tap on_hold on_double_tap on_tap_hold].freeze
      TAPPING_TERM_RANGE = (0..0xFFFF)

      def initialize(index:, name:, on_tap:, on_hold:, on_double_tap:, on_tap_hold:, tapping_term:, description: nil,
                     notes: {})
        super(
          index: Checks.integer!(index, Keycode::TapDanceCall::RANGE, 'タップダンスの番号'),
          name: Checks.name!(name, 'タップダンスの名前'),
          description: Checks.text(description, 'タップダンスの説明'),
          on_tap: Keycode.check!(on_tap, 'on_tap'),
          on_hold: Keycode.check!(on_hold, 'on_hold'),
          on_double_tap: Keycode.check!(on_double_tap, 'on_double_tap'),
          on_tap_hold: Keycode.check!(on_tap_hold, 'on_tap_hold'),
          tapping_term: Checks.integer!(tapping_term, TAPPING_TERM_RANGE, 'tapping_term（ミリ秒）'),
          notes: Checks.notes!(notes, ACTIONS, 'タップダンスの注記')
        )
      end

      # { on_tap: Keycode, on_hold: ..., on_double_tap: ..., on_tap_hold: ... }
      def actions = ACTIONS.to_h { |a| [a, public_send(a)] }

      # 動作の注記。なければ nil
      def note(action) = notes[action]

      def to_s = "TapDance(#{index}: #{name})"
    end
  end
end
