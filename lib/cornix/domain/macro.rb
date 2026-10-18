# frozen_string_literal: true

require_relative 'checks'
require_relative 'macro_step'
require_relative 'keycode/macro_call'

module Cornix
  module Domain
    # マクロ 1 件。index は M0〜M255 の番号、steps は 1 つ以上の MacroStep。
    # 番号がデバイスの件数に収まるか、番号・名前の重複がないかは Profile#diagnostics で検査する
    class Macro < Data.define(:index, :name, :description, :steps)
      def initialize(index:, name:, steps:, description: nil)
        super(
          index: Checks.integer!(index, Keycode::MacroCall::RANGE, 'マクロの番号'),
          name: Checks.name!(name, 'マクロの名前'),
          description: Checks.text(description, 'マクロの説明'),
          steps: check_steps!(steps)
        )
      end

      def to_s = "Macro(#{index}: #{name})"

      private

      def check_steps!(steps)
        list = Checks.list!(steps, 'マクロの steps') { |s, i| MacroStep.check!(s, "マクロの steps[#{i}]") }
        raise InvalidValue, 'マクロの steps が空です' if list.empty?

        list
      end
    end
  end
end
