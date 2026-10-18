# frozen_string_literal: true

require_relative '../command'
require_relative '../config_messages'

module Cornix
  module Interface
    module Cli
      module Commands
        # cornix compile [-o FILE]: config/ を検証してから .vil を書く（旧 bin/subcommands/compile.rb）。
        # FILE の既定は tmp/build/layout.vil（status / apply / device diff がそのまま使う）
        class Compile < Command
          include ConfigMessages

          command 'compile', 'config/ の YAML を検証して .vil を書く（既定は tmp/build/layout.vil。-o はカレントからの相対パスも可）',
                  args: '[-o FILE]'

          def run(args)
            _, opts = parse!(args) { |p, o| p.on('-o FILE', '出力先') { |f| o[:output] = File.expand_path(f) } }
            result = compile_config(output: opts[:output]) or return FAILURE

            out.line("\n✓ Compilation completed: #{result.path}")
            SUCCESS
          end
        end
      end
    end
  end
end
