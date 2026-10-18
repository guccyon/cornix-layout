# frozen_string_literal: true

require_relative '../command'

module Cornix
  module Interface
    module Cli
      module Commands
        # cornix cleanup [-f]: config/ と compile の出力を消す（旧 bin/subcommands/cleanup.rb）。
        # config/.decompile.lock があれば -f が必要で、そのときも y/N で確認する
        class Cleanup < Command
          command 'cleanup', '生成したファイル（config/ と tmp/build/layout.vil）を消す（-f でロックがあっても確認して消す）',
                  args: '[-f|--force]'

          CONFIRM = 'Are you sure you want to continue? [y/N]: '

          def run(args)
            _, opts = parse!(args) { |p, o| p.on('-f', '--force', 'ロックがあっても（確認してから）消す') { o[:force] = true } }
            result = use_case(:cleanup).call(force: opts[:force] == true, confirm: method(:confirm_force))
            case result.status
            when :nothing then out.line('✓ Nothing to clean up')
            when :protected then return protected(result.lock)
            when :cancelled then out.line('✓ Cleanup cancelled')
            else cleaned(result.deleted)
            end
            SUCCESS
          end

          private

          def protected(lock)
            out.line('⚠️  Protected: config/ directory has an active lock file')
            out.line
            out.line('Lock file details:')
            out.line("  Created: #{lock['decompiled_at']}")
            out.line("  Source: #{lock['source_file']}")
            out.line("  Checksum: #{lock['checksum'].to_s[0..15]}...")
            out.line
            out.line('To force cleanup (deletes lock file too):')
            out.line('  cornix cleanup -f')
            FAILURE
          end

          def confirm_force(lock)
            out.line('⚠️  WARNING: This will delete all config files and the lock file')
            out.line
            out.line('Lock file details:')
            out.line("  Created: #{lock['decompiled_at']}")
            out.line("  Source: #{lock['source_file']}")
            out.line
            confirm?(CONFIRM)
          end

          def cleaned(deleted)
            out.line('✓ Cleanup completed')
            out.line
            out.line('Deleted:')
            out.items(deleted)
            out.line
            out.line("You can now run 'cornix decompile' to generate fresh config files")
          end
        end
      end
    end
  end
end
