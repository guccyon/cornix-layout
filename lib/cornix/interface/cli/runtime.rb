# frozen_string_literal: true

require_relative 'output'

module Cornix
  module Interface
    module Cli
      # コマンドの実行に必要なもの（Environment、ユースケース、入出力）をまとめて持つ。
      # Environment は必要になったときに初めて作る（help や使い方の表示では作らない）
      class Runtime
        attr_reader :input, :global_options

        # factories: { env: ->(workspace) { Environment }, workspace: -> { Workspace },
        #              use_cases: { name => ->(env) { ... } }, mcp_server: ->(env) { ... } }
        # global_options: 共通のオプション（{ config:, profile:, root: } のうち指定されたもの）
        def initialize(factories:, out:, input:, global_options: {})
          @factories = factories
          @out = out
          @input = input
          @global_options = global_options
        end

        # 使う設定ディレクトリと tmp/ の場所（Application::Workspace）。最初に使うときに決める
        # （.cornix.yml の誤りで、それを使わないコマンドまで止めないため）
        def workspace = @workspace ||= @factories.fetch(:workspace).call

        def env = @env ||= build_env(workspace)

        # 別の workspace の Environment でユースケースを作る（init が新しい設定ディレクトリに使う）
        def use_case_for(name, other_workspace)
          factory = @factories.fetch(:use_cases)[name] or raise ArgumentError, "ユースケースがありません: #{name}"
          factory.call(build_env(other_workspace))
        end

        # ユースケースのインスタンス（#call を持つもの）
        def use_case(name)
          factory = @factories.fetch(:use_cases)[name] or raise ArgumentError, "ユースケースがありません: #{name}"
          factory.call(env)
        end

        def mcp_server = @factories.fetch(:mcp_server).call(env)

        def output = @output ||= Output.new(@out)

        private

        def build_env(target) = @factories.fetch(:env).call(target)
      end
    end
  end
end
