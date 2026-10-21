# frozen_string_literal: true

module Cornix
  module Interface
    module Cli
      # decompile と pull が共通で使う DecompileResult の表示（--json なら JSON）
      module DecompileReport
        private

        # → 終了コード。config_exists は config/ にすでに設定があったときの案内
        def report_decompile(result, config_exists:)
          case result.status
          when :input_missing
            out.line("Error: #{result.input} not found")
            Command::FAILURE
          when :config_exists
            out.line(config_exists)
            Command::FAILURE
          else
            report_decompiled(result)
          end
        end

        # --json: DecompileResult#to_h（と config）。書かなかったら FAILURE
        def json_decompile(result)
          emit(with_config(result.to_h))
          result.decompiled? ? Command::SUCCESS : Command::FAILURE
        end

        def report_decompiled(result)
          out.line("Decompiling: #{result.input}")
          out.line("Output to: #{result.output_dir}")
          out.line
          out.line("✓ Wrote #{result.files.size} files")
          out.line("\n✓ Decompilation completed: #{result.output_dir}")
          out.line("✓ Lock file created: #{result.lock}")
          Command::SUCCESS
        end
      end
    end
  end
end
