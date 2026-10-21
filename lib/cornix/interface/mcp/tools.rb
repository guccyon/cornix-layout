# frozen_string_literal: true

require 'json'

module Cornix
  module Interface
    module Mcp
      # tools/call の実行。ユースケースを呼び、結果を MCP のツール結果（content / isError）にする。
      # Cornix::Error などの失敗は isError: true のツール結果にする（JSON-RPC のエラーにはしない）
      class Tools
        # use_cases: Interface::UseCases.build の表（name => ->(env) { ユースケース }）
        def initialize(env, use_cases)
          @env = env
          @use_cases = use_cases
        end

        # → { content: [{ type: 'text', text: }], isError: true? }
        def call(name, args)
          args ||= {}
          text =
            case name
            when 'keyboard_info' then JSON.pretty_generate(use(:device_info).call.to_h)
            when 'read_keymap' then read_keymap(args)
            when 'backup' then "バックアップを保存しました: #{use(:device_backup).call.path}"
            when 'list_backups' then list_backups(args)
            when 'apply_layout' then apply_layout(args)
            when 'restore_backup' then restore_backup(args)
            else
              return tool_error("不明なツール: #{name}")
            end
          { content: [{ type: 'text', text: text }] }
        rescue Cornix::Error, ArgumentError, SystemCallError => e
          tool_error(e.message)
        end

        private

        def use(name) = @use_cases.fetch(name).call(@env)

        def read_keymap(args)
          return use(:device_read).call.vil unless args['save_path']

          path = File.expand_path(args['save_path'])
          use(:device_read).call(output: path)
          "保存しました: #{path}"
        end

        # 1 行に 1 件、「日時  種類  パス」を新しい順に
        def list_backups(args)
          list = use(:list_snapshots).call(kind: args['kind'])
          return 'スナップショットはありません' if list.empty?

          list.snapshots.map { |s| "#{s.time.strftime('%Y-%m-%d %H:%M:%S')}  #{s.kind}  #{s.path}" }.join("\n")
        end

        def apply_layout(args)
          path = File.expand_path(args['vil_path'] || @env.layout_path)
          return format_diff(use(:device_diff).call(vil_path: path)) if dry_run?(args)

          format_apply(use(:device_apply).call(vil_path: path, expected_token: token!(args)))
        end

        def restore_backup(args)
          source = args['backup_path'] # 名前でも指定できるので、パスに広げない（相対パスはカレントから）
          return format_diff(use(:device_restore).call(source, dry_run: true)) if dry_run?(args)

          format_apply(use(:device_restore).call(source, expected_token: token!(args)))
        end

        def dry_run?(args) = args.fetch('dry_run', true)

        def token!(args)
          token = args['confirm_token'].to_s
          raise ArgumentError, 'dry_run: false には dry run で得た confirm_token が必要です' if token.empty?

          token
        end

        def format_diff(plan)
          lines = ["対象: #{plan.source}"]
          if plan.empty?
            lines << 'キーボードとの差分はありません。'
          else
            lines << "差分 #{plan.changes.size} 件:"
            lines.concat(plan.changes.map { |change| "  - #{change}" })
            lines << "confirm_token: #{plan.token}"
            lines << '反映するには、ユーザーの同意を得てから dry_run: false と上の confirm_token を付けて呼んでください。'
          end
          unless plan.warnings.empty?
            lines << '警告:'
            lines.concat(plan.warnings.map { |w| "  - #{w}" })
          end
          lines.join("\n")
        end

        def format_apply(outcome)
          return 'キーボードとの差分はなかったため、何も書き込んでいません。' unless outcome.written?

          lines = ["#{outcome.applied} 件を書き込みました。", "反映前のバックアップ: #{outcome.backup}"]
          if outcome.success?
            lines << '読み戻して検証し、すべて一致しました。'
          else
            lines << "読み戻し後も #{outcome.remaining.size} 件が一致しません（ファームウェアが未対応の可能性）:"
            lines.concat(outcome.remaining.map { |change| "  - #{change}" })
          end
          lines.join("\n")
        end

        def tool_error(message)
          { content: [{ type: 'text', text: "エラー: #{message}" }], isError: true }
        end
      end
    end
  end
end
