# frozen_string_literal: true

module Cornix
  module Interface
    module Cli
      # compile / validate / rename が共通で使う表示（旧 CliHelpers.ensure_config_exists と旧 ModelValidator の表示）
      module ConfigMessages
        DECOMPILE_FIRST = "Run 'cornix decompile' first to create config files"

        private

        # config/ がないときの表示（旧 CliHelpers.ensure_config_exists）→ FAILURE
        def config_not_found(error, hint: false)
          out.line("Error: #{error.dir} not found")
          out.line(DECOMPILE_FIRST) if hint
          Command::FAILURE
        end

        # 検証の結果（旧 ModelValidator#report_results と同じ形）
        def print_report(report)
          if report.valid?
            out.line('✓ All validations passed')
            report.warnings.each { |w| out.line("⚠  Warning: #{w}") }
          else
            out.line('✗ Validation failed:')
            report.errors.each { |e| out.line("  Error: #{e}") }
            report.warnings.each { |w| out.line("  Warning: #{w}") }
          end
        end
      end
    end
  end
end
