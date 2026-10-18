# frozen_string_literal: true

require_relative 'usage_error'

module Cornix
  module Interface
    module Cli
      # どのコマンドにも付けられるオプション（設定ディレクトリの場所）を引数から取り出す。
      # コマンド名の前でも後でもよい（cornix --profile alice compile / cornix compile --profile alice）。
      # -- より後ろは取り出さない
      #
      #   opts, rest = GlobalOptions.extract(%w[device diff --config ~/my-config my.vil])
      #   # => [{ config: '~/my-config' }, ['device', 'diff', 'my.vil']]
      module GlobalOptions
        FLAGS = { '--config' => :config, '--profile' => :profile, '--root' => :root }.freeze

        HELP = <<~TEXT
          共通のオプション（どのコマンドにも付けられる）:
            --config DIR    設定ディレクトリを直接指定する
            --profile NAME  profiles/NAME の設定を使う
            --root DIR      tmp/ と profiles/ を置く場所（既定: .cornix.yml の場所か、このリポジトリ）

          設定ディレクトリの決まり方（上ほど優先）: --config、環境変数 CORNIX_CONFIG、--profile、
          カレントから親へたどって見つかる .cornix.yml（profile: NAME か config: PATH）、
          このリポジトリの config/（何も指定しないとき。今までどおり）
        TEXT

        module_function

        def extract(args)
          opts = {}
          rest = []
          list = args.dup
          until list.empty?
            arg = list.shift
            if arg == '--'
              rest.push(arg, *list)
              break
            end
            name, value = arg.split('=', 2)
            key = FLAGS[name]
            unless key
              rest << arg
              next
            end
            value ||= list.shift
            raise UsageError, "#{name} には値が必要です" if value.nil? || value.empty? || value.start_with?('-')

            opts[key] = value
          end
          [opts, rest]
        end
      end
    end
  end
end
