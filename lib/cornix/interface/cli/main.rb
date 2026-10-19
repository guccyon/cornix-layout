# frozen_string_literal: true

require_relative 'usage_error'
require_relative 'global_options'
require_relative 'runtime'
require_relative 'command'
require_relative 'commands/compile'
require_relative 'commands/decompile'
require_relative 'commands/validate'
require_relative 'commands/rename'
require_relative 'commands/cleanup'
require_relative 'commands/device'
require_relative 'commands/pull'
require_relative 'commands/status'
require_relative 'commands/apply'
require_relative 'commands/restore'
require_relative 'commands/mcp'
require_relative 'commands/init'
require_relative '../use_cases'

module Cornix
  module Interface
    module Cli
      # cornix コマンドの入口。コマンド名で COMMANDS からコマンドを選び、実行して終了コードを返す。
      #
      #   exit Cornix::Interface::Cli::Main.new.run(ARGV)
      #
      # Environment・ユースケース・MCP サーバーは手続き（factory）で作る。テストでは差し替える:
      #   Main.new(env_factory: ->(_workspace) { Application::Environment.new(root: dir, device_opener: opener) },
      #            out: StringIO.new, err: StringIO.new, input: StringIO.new("y\n"))
      #
      # 設定ディレクトリは共通のオプション（GlobalOptions）と Workspace.resolve で決め、env_factory に渡す。
      # workspace_factory: ->(config:, profile:, root:) { Application::Workspace }（テストで差し替える）
      class Main
        # コマンドを足すときは Commands::Xxx < Command を作り、ここに並べる（並び順が help の順）
        COMMANDS = [
          Commands::Init, Commands::Compile, Commands::Decompile, Commands::Validate, Commands::Pull, Commands::Status,
          Commands::Apply, Commands::Restore, Commands::Rename, Commands::Cleanup, Commands::Device, Commands::Mcp
        ].to_h { |c| [c.command_name, c] }.freeze

        DEFAULT_ENV = ->(workspace) { Application::Environment.for(workspace) }
        DEFAULT_WORKSPACE = ->(**opts) { Application::Workspace.resolve(**opts) }
        DEFAULT_MCP_SERVER = ->(env) { Interface::Mcp::Server.new(env) }
        HELP_NAMES = %w[help -h --help].freeze
        VERSION_NAMES = %w[version -v --version].freeze
        VERSION_HELP = "使い方: cornix version（--version / -v でも）\n\nこのツールのバージョンを表示する"
        # 既定（<root>/config）以外の設定ディレクトリを使うとき、最初にどの設定かを表示するコマンド
        SHOW_CONFIG = %w[compile decompile validate pull status apply restore rename cleanup].freeze

        def initialize(env_factory: DEFAULT_ENV, use_cases: {}, mcp_factory: DEFAULT_MCP_SERVER, commands: COMMANDS,
                       workspace_factory: DEFAULT_WORKSPACE, out: $stdout, err: $stderr, input: $stdin)
          @commands = commands
          @workspace_factory = workspace_factory
          @factories = { env: env_factory, use_cases: UseCases.build(use_cases), mcp_server: mcp_factory }.freeze
          @out = out
          @err = err
          @input = input
        end

        # → 終了コード（0 = 成功、1 = エラー、2 = status で差分あり）
        def run(argv)
          global, args = GlobalOptions.extract(argv)
          name = args.shift
          return help(args.first) if name.nil? || HELP_NAMES.include?(name)
          return version if VERSION_NAMES.include?(name)

          command_class = @commands[name] or raise UsageError, "知らないコマンドです: #{name}"
          runtime = runtime(global)
          show_config(runtime) if SHOW_CONFIG.include?(name) && !(args & HELP_NAMES).any?
          command_class.new.call(runtime, args)
        rescue UsageError => e
          @err.puts("エラー: #{e.message}")
          @err.puts('使い方は cornix help で表示できます')
          Command::FAILURE
        rescue Cornix::Error, SystemCallError => e
          @err.puts("エラー: #{e.message}")
          Command::FAILURE
        end

        private

        def runtime(global)
          workspace = -> { @workspace_factory.call(config: global[:config], profile: global[:profile], root: global[:root]) }
          Runtime.new(factories: @factories.merge(workspace: workspace), out: @out, input: @input, global_options: global)
        end

        def show_config(runtime)
          workspace = runtime.env.workspace
          runtime.output.line("設定: #{workspace.description}") unless workspace.nil? || workspace.default?
        end

        def help(name)
          if VERSION_NAMES.include?(name)
            @out.puts(VERSION_HELP)
          elsif name
            command_class = @commands[name] or raise UsageError, "知らないコマンドです: #{name}"
            @out.puts(command_class.help)
          else
            @out.puts(overview)
          end
          Command::SUCCESS
        end

        def version
          @out.puts("cornix #{Cornix::VERSION}")
          Command::SUCCESS
        end

        def overview
          width = [*@commands.keys, 'help', 'version'].map(&:size).max
          lines = @commands.map { |name, c| "  #{name.ljust(width)}  #{c.summary}" }
          <<~TEXT
            Cornix Keyboard Layout Manager

            使い方: cornix <コマンド> [引数]

            コマンド:
            #{lines.join("\n")}
              #{'help'.ljust(width)}  使い方を表示する（cornix help <コマンド> で詳しく）
              #{'version'.ljust(width)}  バージョンを表示する（--version / -v でも）

            終了コード: 0 = 成功、1 = エラー、2 = 差分あり（status）

            #{GlobalOptions::HELP.chomp}
          TEXT
        end
      end
    end
  end
end
