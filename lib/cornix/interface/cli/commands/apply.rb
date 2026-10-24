# frozen_string_literal: true

require_relative '../command'
require_relative '../config_messages'
require_relative '../device_report'

module Cornix
  module Interface
    module Cli
      module Commands
        # cornix apply [--yes]: config/ を compile（tmp/build/layout.vil）して、差分を確認してキーボードへ書き込む。
        # = cornix compile && cornix device apply
        class Apply < Command
          include ConfigMessages
          include DeviceReport

          command 'apply', 'config/ を compile して、差分を確認してキーボードへ書き込む（--yes で確認を省略）',
                  args: '[--yes]'

          def run(args)
            _, opts = parse!(args) { |p, o| yes_option(p, o) }
            return json(opts[:yes]) if json?

            result = compile_config or return FAILURE

            out.line
            run_apply(restore: false, yes: opts[:yes]) do |confirm|
              use_case(:device_apply).call(vil_path: result.path, confirm: confirm)
            end
          end

          private

          # { 'config', 'compile' => CompileResult#to_h, 'apply' => ApplyOutcome#to_h（検証に失敗したら nil） }。
          # --yes がなければ compile もせずに止める
          def json(yes)
            check_json_yes!(yes)
            result = compile_quietly or return FAILURE
            unless result.compiled?
              emit(with_config('compile' => result.to_h, 'apply' => nil))
              return FAILURE
            end

            wrap = ->(h) { with_config('compile' => result.to_h, 'apply' => h) }
            run_apply(restore: false, yes: yes, wrap: wrap) do |confirm|
              use_case(:device_apply).call(vil_path: result.path, confirm: confirm)
            end
          end
        end
      end
    end
  end
end
