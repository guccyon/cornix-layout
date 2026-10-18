# frozen_string_literal: true

require_relative 'usage_error'
require_relative 'runtime'
require_relative 'command'
require_relative 'commands/device'
require_relative 'commands/mcp'
require_relative '../use_cases'

module Cornix
  module Interface
    module Cli
      # cornix コマンドの入口。コマンド名で COMMANDS からコマンドを選び、実行して終了コードを返す。
      #
      #   exit Cornix::Interface::Cli::Main.new.run(ARGV)
      #
      # Environment・ユースケース・MCP サーバーは手続き（factory）で作る。テストでは差し替える:
      #   Main.new(env_factory: -> { Application::Environment.new(root: dir, device_opener: opener) },
      #            out: StringIO.new, err: StringIO.new, input: StringIO.new("y\n"))
      class Main
        # コマンドを足すときは Commands::Xxx < Command を作り、ここに並べる（並び順が help の順）。
        # compile / decompile / validate / rename / cleanup は別タスクで追加する
        COMMANDS = [
          Commands::Device, Commands::Mcp
        ].to_h { |c| [c.command_name, c] }.freeze

        DEFAULT_ENV = -> { Application::Environment.new }
        DEFAULT_MCP_SERVER = ->(env) { Interface::Mcp::Server.new(env) }
        HELP_NAMES = %w[help -h --help].freeze

        def initialize(env_factory: DEFAULT_ENV, use_cases: {}, mcp_factory: DEFAULT_MCP_SERVER, commands: COMMANDS,
                       out: $stdout, err: $stderr, input: $stdin)
          @commands = commands
          @factories = { env: env_factory, use_cases: UseCases.build(use_cases), mcp_server: mcp_factory }.freeze
          @out = out
          @err = err
          @input = input
        end

        # → 終了コード（0 = 成功、1 = エラー）
        def run(argv)
          args = argv.dup
          name = args.shift
          return help(args.first) if name.nil? || HELP_NAMES.include?(name)

          command_class = @commands[name] or raise UsageError, "知らないコマンドです: #{name}"
          command_class.new.call(Runtime.new(factories: @factories, out: @out, input: @input), args)
        rescue UsageError => e
          @err.puts("エラー: #{e.message}")
          @err.puts('使い方は cornix help で表示できます')
          Command::FAILURE
        rescue Cornix::Error, SystemCallError => e
          @err.puts("エラー: #{e.message}")
          Command::FAILURE
        end

        private

        def help(name)
          if name
            command_class = @commands[name] or raise UsageError, "知らないコマンドです: #{name}"
            @out.puts(command_class.help)
          else
            @out.puts(overview)
          end
          Command::SUCCESS
        end

        def overview
          width = [*@commands.keys, 'help'].map(&:size).max
          lines = @commands.map { |name, c| "  #{name.ljust(width)}  #{c.summary}" }
          <<~TEXT
            Cornix Keyboard Layout Manager

            使い方: cornix <コマンド> [引数]

            コマンド:
            #{lines.join("\n")}
              #{'help'.ljust(width)}  使い方を表示する（cornix help <コマンド> で詳しく）
          TEXT
        end
      end
    end
  end
end
