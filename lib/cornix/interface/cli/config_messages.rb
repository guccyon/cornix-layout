# frozen_string_literal: true

module Cornix
  module Interface
    module Cli
      # compile / validate / rename（と compile してから使う status / apply）が共通で使う表示（旧 CliHelpers.ensure_config_exists と旧 ModelValidator の表示）。
      # --json のときは compile_quietly で compile し、結果は各コマンドが JSON にする
      module ConfigMessages
        DECOMPILE_FIRST = "Run 'cornix decompile' first to create config files"

        private

        # config/ がないときの表示（旧 CliHelpers.ensure_config_exists。--json なら { "error" }）→ FAILURE
        def config_not_found(error, hint: false)
          if json?
            emit(Application::Serialize.error(["#{error.dir} not found", (DECOMPILE_FIRST if hint)].compact.join('. ')))
            return Command::FAILURE
          end

          out.line("Error: #{error.dir} not found")
          out.line(DECOMPILE_FIRST) if hint
          Command::FAILURE
        end

        # 検証してから compile する（表示つき）。→ CompileResult、検証エラーや config/ がなければ nil
        def compile_config(output: nil)
          out.line('🔍 Validating configuration...')
          result = use_case(:compile).call(output: output)
          print_report(result.report)
          unless result.compiled?
            out.line("\n❌ Validation failed. Fix errors before compiling.")
            return
          end

          out.line("✓ Validation passed\n\n")
          out.line('🔨 Compiling...')
          out.line("✓ Compiled: #{result.path}")
          result
        rescue Application::ConfigNotFound => e
          config_not_found(e, hint: true)
          nil
        end

        # --json のとき: 表示せずに検証して compile する → CompileResult（検証に失敗したら compiled? が偽）。
        # config/ がなければエラーの JSON を出して nil
        def compile_quietly(output: nil)
          use_case(:compile).call(output: output)
        rescue Application::ConfigNotFound => e
          config_not_found(e, hint: true)
          nil
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
          print_unused(report.unused_files)
        end

        # 未使用のファイル（index のないもの。compile に含めない）の一覧。なければ何も出さない
        def print_unused(files)
          return if files.empty?

          out.line("ℹ  Unused files (no index, not compiled): #{files.size}")
          files.each { |file| out.line("    #{file}") }
        end
      end
    end
  end
end
