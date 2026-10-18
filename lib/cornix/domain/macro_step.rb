# frozen_string_literal: true

require_relative 'checks'
require_relative 'keycode'

module Cornix
  module Domain
    # マクロの 1 命令。具体的な型は MacroStep::Tap / Down / Up / Delay / Text。
    # kind は Image::MacroAction の kind と同じ記号（:tap / :down / :up / :delay / :text）
    module MacroStep
      # すべての命令が include する目印
      module Value
        def macro_step? = true
      end

      def self.step?(value) = value.is_a?(Value)

      def self.check!(value, what = 'マクロの命令')
        return value if step?(value)

        raise InvalidValue, "#{what}が不正です: #{value.inspect}"
      end

      # キーを押す系の命令（Tap / Down / Up）の共通部分。keys は 1 つ以上の Keycode（16bit 値ならどれでもよい）
      module KeyAction
        include Value

        private

        def check_keys!(keys)
          list = Checks.list!(keys, "#{kind} のキー") { |k, i| Keycode.check!(k, "#{kind} のキー[#{i}]") }
          raise InvalidValue, "#{kind} のキーが空です" if list.empty?

          list
        end
      end
    end
  end
end
