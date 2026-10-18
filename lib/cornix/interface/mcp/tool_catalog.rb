# frozen_string_literal: true

module Cornix
  module Interface
    module Mcp
      # サーバーの説明（instructions）とツールの定義（名前・説明・inputSchema。旧 Device::McpServer と同じ）
      module ToolCatalog
        INSTRUCTIONS = <<~TEXT
          Bluetooth/USB で接続中の Cornix キーボードを Vial プロトコルで直接読み書きします（Vial Web は不要）。
          書き込みは apply_layout と restore_backup だけです。まず dry_run: true（既定）で差分と confirm_token を取得して
          ユーザーに見せ、ユーザーの明示的な同意を得てから dry_run: false と confirm_token を付けて呼んでください。
          反映前には自動でバックアップを取り、反映後は読み戻して検証します。restore_backup で直前の状態に戻せます。
          キーボードが接続されていない場合、各ツールはエラー（isError）を返し、何も書き込みません。
          bootloader 移行・EEPROM リセット・全消去などの危険な操作はこのサーバーにはありません。
        TEXT

        DRY_RUN = { type: 'boolean', description: 'true なら差分の確認のみ（既定 true）' }.freeze
        CONFIRM_TOKEN = { type: 'string', description: 'dry run で返された確認トークン（dry_run: false のとき必須）' }.freeze

        module_function

        def names = tools(default_vil: '').map { |t| t[:name] }

        # tools/list の tools。default_vil は apply_layout の vil_path の説明に入れる既定のファイル
        def tools(default_vil:)
          [
            {
              name: 'keyboard_info',
              description: '接続中のキーボードの情報（プロトコル、UID、レイヤー数、マクロ・タップダンス・コンボの枠数、ロック状態）を返す。読み取りのみ。',
              inputSchema: { type: 'object', properties: {} }
            },
            {
              name: 'read_keymap',
              description: 'キーボードの現在のキーマップ・エンコーダ・マクロ・タップダンス・コンボ・設定を layout.vil 形式で返す。save_path を指定するとファイルに保存する。読み取りのみ。',
              inputSchema: {
                type: 'object',
                properties: { save_path: { type: 'string', description: '保存先の .vil ファイルパス（省略時は内容を返す）' } }
              }
            },
            {
              name: 'backup',
              description: 'キーボードの現在の状態を tmp/device_backups/ に日時付きの .vil として保存し、パスを返す。読み取りのみ。',
              inputSchema: { type: 'object', properties: {} }
            },
            {
              name: 'list_backups',
              description: 'tmp/device_backups/ にあるバックアップの一覧を新しい順に返す。',
              inputSchema: { type: 'object', properties: {} }
            },
            {
              name: 'restore_backup',
              description: <<~DESC.strip,
                バックアップからキーボードを復元する（直前の apply_layout / restore_backup の前の状態に戻す）。
                backup_path を省略すると最後に取ったバックアップを使う。dry_run と confirm_token の扱いは apply_layout と同じ。
                復元の前にも現在の状態をバックアップするので、続けてもう一度 restore_backup すると復元前に戻る。
              DESC
              inputSchema: {
                type: 'object',
                properties: {
                  backup_path: { type: 'string', description: 'バックアップの .vil ファイル（省略時は最新のバックアップ）' },
                  dry_run: DRY_RUN, confirm_token: CONFIRM_TOKEN
                }
              }
            },
            {
              name: 'apply_layout',
              description: <<~DESC.strip,
                layout.vil（cornix compile の出力やバックアップ）をキーボードに反映する。
                dry_run: true（既定）では書き込まずに差分・警告・confirm_token を返す。
                dry_run: false で書き込むには、dry run で得た confirm_token が必要（差分が変わっていたら拒否）。
                書き込み前に自動でバックアップを取り、書き込み後に読み戻して残った差分を返す。
                dry_run: false はユーザーが差分を確認して同意したときだけ使うこと。
              DESC
              inputSchema: {
                type: 'object',
                properties: {
                  vil_path: { type: 'string', description: "反映する .vil ファイル（省略時は #{default_vil}）" },
                  dry_run: DRY_RUN, confirm_token: CONFIRM_TOKEN
                }
              }
            }
          ]
        end
      end
    end
  end
end
