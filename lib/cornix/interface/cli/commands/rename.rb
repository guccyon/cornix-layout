# frozen_string_literal: true

require_relative '../command'
require_relative '../config_messages'

module Cornix
  module Interface
    module Cli
      module Commands
        # cornix rename: 既定の名前（"Macro 3" など）の設定ファイルに、Claude の提案から名前を付ける
        # （旧 lib/cornix/rename_command.rb）。提案を 1 件ずつ Y/n/e(dit) で選び、Application::RenameFiles で
        # まとめて変える（名前参照の書き換え、compile 結果が変わらないことの確認、失敗したら元に戻す）
        class Rename < Command
          include ConfigMessages

          command 'rename', '設定ファイルに意味のある名前を付ける（Claude の提案を確認しながら）'

          SPINNER = %w[⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏].freeze
          RULE = '─' * 70

          def run(args)
            parse!(args)
            out.line('🔍 Cornix Config Renamer')
            out.line
            return FAILURE unless check_configuration

            plans = suggest
            return finish_early('✓ All files already have meaningful names or Claude skill failed') if plans.empty?

            out.line
            out.line('📋 Step 3: Review rename suggestions')
            out.line('=' * 70)
            selected = select_plans(plans)
            return finish_early("\n✓ No files selected for rename") if selected.empty?

            apply(selected)
          end

          private

          def renamer = @renamer ||= use_case(:rename_files)
          def suggester = @suggester ||= use_case(:suggest_renames)
          def gets = runtime.input.gets

          # Step 1（旧実装はここで compile して基準の layout.vil を保存した。いまは RenameFiles が変更の前後で比べる）
          def check_configuration
            out.line('📦 Step 1: Checking current configuration...')
            report = use_case(:validate).call
            unless report.valid?
              print_report(report)
              out.line("\n❌ Fix the configuration before renaming.")
              return false
            end
            out.line('  ✓ Configuration is valid')
            true
          rescue Application::ConfigNotFound
            out.line('❌ Error: config/ directory not found')
            out.line
            out.line(DECOMPILE_FIRST)
            false
          end

          # ---- Step 2: 提案 ----

          def suggest
            out.line
            out.line('🤖 Step 2: Analyzing files with Claude AI...')
            out.line('  Analyzing files with Claude AI...')
            return claude_missing unless suggester.available?

            out.line('  ✓ Claude CLI detected, analyzing files...')
            result = with_spinner('Running Claude analysis') { suggester.call }
            if result.status == :unparsed
              out.line
              out.line('  ⚠️  Could not extract JSON from Claude output')
              out.line("  Output saved to: #{result.log_path}")
              out.line('  Falling back to manual mode...')
              return manual_plans
            end

            elapsed = result.elapsed.to_f.round(1)
            out.line(result.success ? "  ✓ Analysis completed (#{elapsed}s)" : "  ✗ Analysis failed after #{elapsed}s")
            loaded_plans(result)
          end

          def claude_missing
            out.line
            out.line('  ❌ Error: Claude CLI not found')
            out.line
            out.line("  The 'claude' command is required for automatic rename analysis.")
            out.line('  Please install Claude Code from: https://claude.ai/download')
            out.line
            []
          end

          def manual_plans
            out.line
            out.line("  Please manually create rename plan at: #{suggester.plans_path}")
            out.line
            out.line('  JSON format should be:')
            out.line(<<~JSON.gsub(/^/, '  ').chomp)
              [
                {
                  "old_path": "config/macros/00_macro.yml",
                  "new_basename": "00_brackets_pair.yml",
                  "content_updates": {
                    "name": "Brackets Pair",
                    "description": "Insert bracket pair []"
                  }
                }
              ]
            JSON
            out.line
            out.prompt('  Press Enter when ready (or Ctrl+C to cancel): ')
            return [] unless gets

            loaded_plans(suggester.load_plans)
          end

          def loaded_plans(result)
            case result.status
            when :missing
              out.line
              out.line("  ⚠️  Rename plan file not found: #{result.plans_path}")
              []
            when :invalid
              out.line
              out.line("  ❌ Error parsing rename plan file: #{result.error}")
              []
            else
              out.line("  ✓ Loaded #{result.plans.size} rename suggestion(s)")
              result.plans
            end
          end

          # 端末ならスピナーと経過秒数を表示しながらブロックを実行する
          def with_spinner(message)
            return yield unless out.tty?

            running = true
            io = out.io
            started = Time.now
            thread = Thread.new do
              i = 0
              while running
                io.print("\r  #{SPINNER[i % SPINNER.size]} #{message}... (#{(Time.now - started).to_i}s)")
                io.flush
                i += 1
                sleep 0.1
              end
              io.print("\r#{' ' * 80}\r")
              io.flush
            end
            begin
              yield
            ensure
              running = false
              thread.join
            end
          end

          # ---- Step 3: 選ぶ ----

          def select_plans(plans)
            selected = []
            plans.each_with_index do |plan, idx|
              show_plan(plan, idx)
              out.prompt('  Apply this rename? [Y/n/e(dit)]: ')
              input = gets
              unless input
                out.line('  ⊘ Interrupted')
                break
              end

              case input.chomp.downcase
              when '', 'y', 'yes'
                selected << plan
                out.line('  ✓ Added to rename queue')
              when 'e', 'edit'
                edited = edit_plan(plan)
                if edited
                  selected << edited
                  out.line('  ✓ Added edited plan to queue')
                end
              when 'n', 'no' then out.line('  ⊘ Skipped')
              else out.line('  ⊘ Invalid response, skipped')
              end
            end
            selected
          end

          def show_plan(plan, idx)
            out.line
            out.line(RULE)
            out.line("#{idx + 1}. #{plan.type.upcase}: #{plan.old_basename}")
            out.line
            out.line("  Current:  #{plan.old_basename}")
            out.line("  Proposed: #{plan.new_basename}")
            out.line
            out.line("  Name:        #{plan.name}")
            out.line("  Description: #{plan.description}")
            out.line
            out.line("  Reasoning:   #{plan.reasoning}")
            out.line("  Confidence:  #{plan.confidence}")
            out.line
          end

          def edit_plan(plan)
            out.line
            out.line('  Edit rename plan:')
            out.line
            basename = ask('  New basename', plan.new_basename) or return nil
            name = ask('  New name', plan.name) or return nil
            description = ask('  New description', plan.description) or return nil
            plan.with(new_basename: basename, content_updates: { 'name' => name, 'description' => description })
          end

          # 空なら current。入力が終わっていれば nil
          def ask(label, current)
            out.prompt("#{label} [#{current}]: ")
            input = gets or return nil
            value = input.chomp
            value.empty? ? current : value
          end

          # ---- Step 4〜6: 実行・検証・後片付け ----

          def apply(selected)
            out.line
            out.line('✏️  Step 4: Applying renames...')
            outcome = renamer.call(selected)
            return failed(outcome) unless outcome.success?

            out.line("  ✓ Renamed #{outcome.completed.size} file(s)")
            out.line("  ✓ Backup: #{File.basename(outcome.backup_path)}")
            refs = outcome.updated_references
            out.line(refs.empty? ? '  ✓ No name-based references to update' : "  ✓ Updated references in: #{refs.join(', ')}")
            out.line
            out.line('🔍 Step 5: Verifying changes...')
            out.line('  ✓ Layout structure preserved (compiled layout is identical)')
            out.line
            out.line('🧹 Step 6: Cleaning up temporary files...')
            cleanup_temp_files
            out.line
            ask_backup_cleanup
            out.line
            out.line('✅ Rename completed successfully!')
            out.line
            out.line('Summary:')
            out.line("  Renamed: #{selected.size} file(s)")
            out.line('  Verification: ✓ Layout structure preserved')
            SUCCESS
          end

          def failed(outcome)
            out.line
            out.line('❌ Rename failed:')
            outcome.errors.each { |e| out.line("  #{e}") }
            outcome.failed.each { |f| out.line("  #{f[:plan]&.fetch('old_path', nil)}: #{f[:error]}") if f.is_a?(Hash) && f[:error] }
            if outcome.rollback_completed
              out.line
              out.line('✓ Changes rolled back successfully')
            end
            cleanup_temp_files
            FAILURE
          end

          def finish_early(message)
            out.line(message)
            cleanup_temp_files
            SUCCESS
          end

          def cleanup_temp_files
            removed = suggester.cleanup
            out.line("  ✓ Removed: #{removed.join(', ')}") unless removed.empty?
          end

          def ask_backup_cleanup
            backups = renamer.backups
            return if backups.empty?

            out.line('📦 Backup directories found:')
            out.items(backups.map { |dir| File.basename(dir) })
            out.line
            unless confirm?('Would you like to delete these backup directories? [y/N]: ')
              out.line('  ℹ️  Backups preserved')
              return
            end

            backups.each do |dir|
              renamer.delete_backup(dir)
              out.line("  ✓ Deleted: #{File.basename(dir)}")
            end
          end
        end
      end
    end
  end
end
