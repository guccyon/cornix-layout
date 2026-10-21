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
          反映前には自動でスナップショット（pre-apply）を取り、反映後は読み戻して検証します。restore_backup で直前の apply の前の状態に戻せます。
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
              description: 'キーボードの現在の状態をスナップショット（種類 backup。tmp/snapshots/<日時>-backup/layout.vil）として保存し、パスを返す。読み取りのみ。',
              inputSchema: { type: 'object', properties: {} }
            },
            {
              name: 'list_backups',
              description: <<~DESC.strip,
                スナップショット（キーボードの状態と compile の出力の履歴。tmp/snapshots/）の一覧を新しい順に返す。1 行に「日時  種類  パス」。
                種類は read（キーボードを読んだとき）・build（compile の出力）・backup・pre-apply（apply の直前）・pre-restore（restore の直前）・legacy（前の版の tmp/device_backups/）。
              DESC
              inputSchema: {
                type: 'object',
                properties: {
                  kind: { type: 'string', enum: Application::ListSnapshots::KINDS,
                          description: '種類で絞り込む（省略時はすべて）' }
                }
              }
            },
            {
              name: 'restore_backup',
              description: <<~DESC.strip,
                スナップショットからキーボードを復元する。backup_path を省略すると最新の pre-apply（直前の apply_layout の前の状態）に戻す。
                dry_run と confirm_token の扱いは apply_layout と同じ。
                復元の前にも現在の状態を pre-restore のスナップショットに残すので、それを backup_path に指定すると復元前に戻る。
              DESC
              inputSchema: {
                type: 'object',
                properties: {
                  backup_path: { type: 'string', description: 'スナップショットの名前・パス、または .vil ファイル（省略時は最新の pre-apply）' },
                  dry_run: DRY_RUN, confirm_token: CONFIRM_TOKEN
                }
              }
            },
            {
              name: 'apply_layout',
              description: <<~DESC.strip,
                layout.vil（cornix compile の出力やスナップショット）をキーボードに反映する。
                dry_run: true（既定）では書き込まずに差分・警告・confirm_token を返す。
                dry_run: false で書き込むには、dry run で得た confirm_token が必要（差分が変わっていたら拒否）。
                書き込み前に自動でスナップショット（pre-apply）を取り、書き込み後に読み戻して残った差分を返す。
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
