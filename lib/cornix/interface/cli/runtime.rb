# frozen_string_literal: true

require_relative 'output'

module Cornix
  module Interface
    module Cli
      # コマンドの実行に必要なもの（Environment、ユースケース、入出力）をまとめて持つ。
      # Environment は必要になったときに初めて作る（help や使い方の表示では作らない）
      class Runtime
        attr_reader :input

        # factories: { env: -> { Environment }, use_cases: { name => ->(env) { ... } }, mcp_server: ->(env) { ... } }
        def initialize(factories:, out:, input:)
          @factories = factories
          @out = out
          @input = input
        end

        def env = @env ||= @factories.fetch(:env).call

        # ユースケースのインスタンス（#call を持つもの）
        def use_case(name)
          factory = @factories.fetch(:use_cases)[name] or raise ArgumentError, "ユースケースがありません: #{name}"
          factory.call(env)
        end

        def mcp_server = @factories.fetch(:mcp_server).call(env)

        def output = @output ||= Output.new(@out)
      end
    end
  end
end
