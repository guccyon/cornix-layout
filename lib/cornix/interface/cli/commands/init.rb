# frozen_string_literal: true

require_relative '../command'

module Cornix
  module Interface
    module Cli
      module Commands
        # cornix init [DIR] [--from FILE] [--no-pull]: DIR（既定: --root かカレント）に設定ディレクトリを作る。
        # 作る場所は --profile NAME なら profiles/NAME、--config なら DIR、どちらもなければ profiles/default。
        # デバイスにつながれば（--from FILE ならその .vil から）decompile と同じ内容の設定を書く
        class Init < Command
          command 'init', '設定ディレクトリを作り、デバイス（か --from の .vil）から設定を書く',
                  args: '[DIR] [--profile NAME | --config DIR] [--from FILE] [--no-pull]'

          def self.help
            <<~TEXT.chomp
              #{super}

              DIR          .cornix.yml・tmp/・profiles/ を置く場所（既定: --root かカレントディレクトリ）
              --from FILE  デバイスの代わりに Vial で保存した layout.vil から設定を書く
              --no-pull    デバイスを読まずに空の設定ディレクトリだけを作る

              作る場所は --profile NAME なら profiles/NAME、--config DIR なら DIR、どちらもなければ
              profiles/#{Application::Init::DEFAULT_PROFILE}。作る場所が既定（このリポジトリの config/）でなければ、
              次からその設定が使われるように .cornix.yml を作る（すでにあれば変えない）。
            TEXT
          end

          def run(args)
            (dir,), opts = parse!(args, max_args: 1) do |p, o|
              p.on('--from FILE') { |f| o[:from] = f }
              p.on('--no-pull') { o[:no_pull] = true }
            end
            from = opts[:from] && File.expand_path(opts[:from])
            report(use_case_for(dir).call(from: from, pull: !opts[:no_pull]))
            SUCCESS
          end

          private

          # 場所は共通のオプションだけで決める（環境変数 CORNIX_CONFIG や既存の .cornix.yml は init の場所を決めない）。
          # どちらも指定がなければ profiles/default に作る（config/ は読むほうだけ後方互換で残す）
          def use_case_for(dir)
            global = runtime.global_options
            profile = global[:profile] || (Application::Init::DEFAULT_PROFILE unless global[:config])
            base = File.expand_path(dir || global[:root] || Dir.pwd)
            # DIR を渡したときは、--config の相対パスも DIR からとする
            ws = Application::Workspace.resolve(cwd: dir ? base : Dir.pwd, root: base, default_root: base, env: {},
                                                config: global[:config], profile: profile)
            runtime.use_case_for(:init, ws)
          end

          def report(result)
            out.line("設定ディレクトリを作りました: #{result.config_dir}")
            out.line('作ったもの:')
            out.items(result.created)
            case result.imported_from
            when :device then out.line("デバイスから読んだ設定を書きました（#{result.files.size} ファイル）")
            when nil
              out.line("デバイスにつながりませんでした: #{result.device_error}") if result.device_error
            else out.line("#{result.imported_from} から設定を書きました（#{result.files.size} ファイル）")
            end
            return if result.notes.empty?

            out.line('メモ:')
            out.items(result.notes)
          end
        end
      end
    end
  end
end
