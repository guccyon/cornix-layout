# frozen_string_literal: true

require_relative 'decompile'

module Cornix
  module Interface
    module Cli
      module Commands
        # cornix pull: キーボードの状態を tmp/layout.vil に読み出し、config/ の YAML にする。
        # = cornix device read -o tmp/layout.vil && cornix decompile（config/ にすでに設定があれば decompile と同じく止まる）
        class Pull < Decompile
          command 'pull', 'キーボードの状態を tmp/layout.vil に読み出して config/ の YAML にする'

          def run(args)
            parse!(args)
            path = use_case(:device_read).call(output: runtime.env.decompile_input).path
            out.line("✓ キーボードの状態を保存しました: #{path}")
            decompile(path)
          end
        end
      end
    end
  end
end
