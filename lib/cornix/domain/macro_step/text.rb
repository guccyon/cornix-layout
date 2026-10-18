# frozen_string_literal: true

require_relative '../macro_step'

module Cornix
  module Domain
    module MacroStep
      # 文字列をそのまま入力する。1 文字 = 1 バイトで送るので ASCII のみ。
      # NUL（マクロの終端）と 0x01（命令の接頭辞）は使えない
      class Text < Data.define(:content)
        include Value
        FORBIDDEN = ["\x00", "\x01"].freeze

        def initialize(content:)
          raise InvalidValue, "text は文字列です: #{content.inspect}" unless content.is_a?(String)
          raise InvalidValue, 'text が空です' if content.empty?
          raise InvalidValue, "text は ASCII のみです: #{content.inspect}" unless content.ascii_only?
          raise InvalidValue, "text に NUL や制御コード 1 は使えません: #{content.inspect}" if FORBIDDEN.any? { |c| content.include?(c) }

          super(content: content.dup.freeze)
        end

        def kind = :text
      end
    end
  end
end
