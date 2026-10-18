# frozen_string_literal: true

require 'json'

module Cornix
  module Interface
    module Cli
      # 人が読む形の出力の部品（各コマンドが組み合わせて使う）
      class Output
        def initialize(io)
          @io = io
        end

        def line(text = '') = @io.puts(text)

        # 改行しない（y/N の問い合わせ）
        def prompt(text)
          @io.print(text)
          @io.flush if @io.respond_to?(:flush)
        end

        # 端末に出しているか（スピナーを出すかどうか）
        def tty? = @io.respond_to?(:tty?) && @io.tty?

        def io = @io

        def json(value) = @io.puts(JSON.pretty_generate(value))

        # "  - 項目" の一覧
        def items(list, prefix: '  - ') = list.each { |item| line("#{prefix}#{item}") }
      end
    end
  end
end
