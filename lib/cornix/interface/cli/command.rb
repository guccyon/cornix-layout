# frozen_string_literal: true

require 'optparse'
require_relative 'usage_error'

module Cornix
  module Interface
    module Cli
      # コマンドの基底。サブクラスは command（名前・説明・引数の書式）と #run(args) を定義する。
      # オプションは #parse! で OptionParser を組み立てて解釈する（コマンドごと・サブアクションごと）
      class Command
        SUCCESS = 0
        FAILURE = 1
        HAS_CHANGES = 2 # status で差分がある

        class << self
          attr_reader :command_name, :summary, :arguments

          # command 'device', 'キーボードを読み書きする', args: '<action> [...]'
          def command(name, summary, args: '')
            @command_name = name
            @summary = summary
            @arguments = args
          end

          # cornix help <コマンド> で表示する説明（既定は「使い方: ...」と summary）
          def help
            "#{summary}\n\n使い方: cornix #{[command_name, arguments].reject(&:empty?).join(' ')}"
          end
        end

        # → 終了コード
        def call(runtime, args)
          @runtime = runtime
          run(args.dup)
        end

        def run(_args) = raise(NotImplementedError)

        private

        attr_reader :runtime

        def out = runtime.output
        def use_case(name) = runtime.use_case(name)

        # OptionParser でオプションを解釈し、残りの位置引数を返す。位置引数が max_args を超えたら UsageError
        #   positional = parse!(args, max_args: 1) { |p, opts| p.on('--yes') { opts[:yes] = true } }
        def parse!(args, max_args: 0, banner: nil)
          opts = {}
          parser = OptionParser.new
          parser.banner = banner if banner
          yield parser, opts if block_given?
          positional = parser.permute(args)
          if positional.size > max_args
            raise UsageError, "#{self.class.command_name} への余分な引数: #{positional.drop(max_args).join(' ')}"
          end

          [positional, opts]
        rescue OptionParser::ParseError => e
          raise UsageError, e.message
        end

        # 問い合わせて y / yes なら真
        def confirm?(question)
          out.prompt(question)
          %w[y yes].include?(runtime.input.gets.to_s.strip.downcase)
        end
      end
    end
  end
end
