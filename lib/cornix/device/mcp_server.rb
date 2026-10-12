# frozen_string_literal: true

require 'json'
require_relative 'keyboard'

module Cornix
  module Device
    # Cornix キーボードを直接操作する MCP サーバー（stdio, JSON-RPC 2.0, 改行区切り）
    #
    # 書き込みは apply_layout だけで、必ず dry run で差分と確認トークンを受け取り、
    # ユーザーの確認を得たうえでそのトークンを付けて呼ぶ二段階方式にしている。
    class McpServer
      PROTOCOL_VERSION = '2025-06-18'
      SERVER_INFO = { name: 'cornix-device', version: '0.1.0' }.freeze
      DEFAULT_VIL = File.join(HidBridge::ROOT, 'layout.vil')

      INSTRUCTIONS = <<~TEXT
        Bluetooth/USB で接続中の Cornix キーボードを Vial プロトコルで直接読み書きします（Vial Web は不要）。
        書き込みは apply_layout と restore_backup だけです。まず dry_run: true（既定）で差分と confirm_token を取得して
        ユーザーに見せ、ユーザーの明示的な同意を得てから dry_run: false と confirm_token を付けて呼んでください。
        反映前には自動でバックアップを取り、反映後は読み戻して検証します。restore_backup で直前の状態に戻せます。
        キーボードが接続されていない場合、各ツールはエラー（isError）を返し、何も書き込みません。
        bootloader 移行・EEPROM リセット・全消去などの危険な操作はこのサーバーにはありません。
      TEXT

      TOOLS = [
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
              dry_run: { type: 'boolean', description: 'true なら差分の確認のみ（既定 true）' },
              confirm_token: { type: 'string', description: 'dry run で返された確認トークン（dry_run: false のとき必須）' }
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
              vil_path: { type: 'string', description: "反映する .vil ファイル（省略時は #{DEFAULT_VIL}）" },
              dry_run: { type: 'boolean', description: 'true なら差分の確認のみ（既定 true）' },
              confirm_token: { type: 'string', description: 'dry run で返された確認トークン（dry_run: false のとき必須）' }
            }
          }
        }
      ].freeze

      def initialize(input: $stdin, output: $stdout, keyboard_opener: Keyboard.method(:open))
        @input = input
        @output = output
        @open_keyboard = keyboard_opener
      end

      def run
        # LANG 未設定（US-ASCII ロケール）でも日本語を含む JSON を正しく読めるよう、入力は UTF-8 として扱う
        @input.set_encoding(Encoding::UTF_8) if @input.respond_to?(:set_encoding)
        @input.each_line do |line|
          next if line.strip.empty?

          message = begin
            JSON.parse(line)
          rescue JSON::ParserError
            write(jsonrpc: '2.0', id: nil, error: { code: -32_700, message: 'Parse error' })
            next
          end
          response = handle(message)
          write(response) if response
        end
      end

      def handle(message)
        id = message['id']
        method = message['method']
        return nil if id.nil? # 通知には応答しない

        result =
          case method
          when 'initialize'
            { protocolVersion: message.dig('params', 'protocolVersion') || PROTOCOL_VERSION,
              capabilities: { tools: {} }, serverInfo: SERVER_INFO, instructions: INSTRUCTIONS }
          when 'ping' then {}
          when 'tools/list' then { tools: TOOLS }
          when 'tools/call' then call_tool(message.dig('params', 'name'), message.dig('params', 'arguments') || {})
          else
            return { jsonrpc: '2.0', id: id, error: { code: -32_601, message: "Method not found: #{method}" } }
          end
        { jsonrpc: '2.0', id: id, result: result }
      end

      private

      # 非 ASCII 文字は \uXXXX にエスケープし、クライアント側のロケールに関係なく読めるようにする
      def write(obj)
        @output.puts(JSON.generate(obj, ascii_only: true))
        @output.flush
      end

      def call_tool(name, args)
        text =
          case name
          when 'keyboard_info' then with_keyboard { |kb| JSON.pretty_generate(kb.info) }
          when 'read_keymap' then read_keymap(args)
          when 'backup' then with_keyboard { |kb| "バックアップを保存しました: #{kb.backup}" }
          when 'list_backups' then list_backups
          when 'apply_layout' then apply_layout(args)
          when 'restore_backup'
            apply_layout(args.merge('vil_path' => args['backup_path'] || Keyboard.latest_backup))
          else
            return tool_error("不明なツール: #{name}")
          end
        { content: [{ type: 'text', text: text }] }
      rescue DeviceError, ArgumentError, Errno::ENOENT, JSON::ParserError => e
        tool_error(e.message)
      end

      def tool_error(message)
        { content: [{ type: 'text', text: "エラー: #{message}" }], isError: true }
      end

      def with_keyboard(&block)
        result = nil
        @open_keyboard.call { |kb| result = block.call(kb) }
        result
      end

      def read_keymap(args)
        with_keyboard do |kb|
          json = JSON.pretty_generate(kb.snapshot)
          if args['save_path']
            File.write(File.expand_path(args['save_path']), json)
            "保存しました: #{File.expand_path(args['save_path'])}"
          else
            json
          end
        end
      end

      def list_backups
        files = Keyboard.backups
        files.empty? ? 'バックアップはありません' : files.join("\n")
      end

      def apply_layout(args)
        path = File.expand_path(args['vil_path'] || DEFAULT_VIL)
        target = JSON.parse(File.read(path, encoding: Encoding::UTF_8))
        dry_run = args.fetch('dry_run', true)

        with_keyboard do |kb|
          if dry_run
            format_diff(kb, kb.diff(target), path)
          else
            token = args['confirm_token'].to_s
            raise ArgumentError, 'dry_run: false には dry run で得た confirm_token が必要です' if token.empty?

            format_apply(kb, kb.apply(target, expected_token: token))
          end
        end
      end

      def format_diff(keyboard, result, path)
        lines = ["対象: #{path}"]
        if result[:changes].empty?
          lines << 'キーボードとの差分はありません。'
        else
          lines << "差分 #{result[:changes].size} 件:"
          lines.concat(result[:changes].map { |ch| "  - #{keyboard.format_change(ch)}" })
          lines << "confirm_token: #{result[:token]}"
          lines << '反映するには、ユーザーの同意を得てから dry_run: false と上の confirm_token を付けて呼んでください。'
        end
        unless result[:warnings].empty?
          lines << '警告:'
          lines.concat(result[:warnings].map { |w| "  - #{w}" })
        end
        lines.join("\n")
      end

      def format_apply(keyboard, result)
        return 'キーボードとの差分はなかったため、何も書き込んでいません。' if result[:applied].zero?

        lines = ["#{result[:applied]} 件を書き込みました。", "反映前のバックアップ: #{result[:backup]}"]
        if result[:remaining].empty?
          lines << '読み戻して検証し、すべて一致しました。'
        else
          lines << "読み戻し後も #{result[:remaining].size} 件が一致しません（ファームウェアが未対応の可能性）:"
          lines.concat(result[:remaining].map { |ch| "  - #{keyboard.format_change(ch)}" })
        end
        lines.join("\n")
      end
    end
  end
end
