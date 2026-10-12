# キーボード直接操作と MCP サーバー

接続中の Cornix に Vial プロトコル（raw HID）で直接読み書きする機能。Vial Web / GUI を使わずに
`layout.vil` を差分だけ反映できる。CLI（`cornix device`）と MCP サーバー（`cornix mcp`）の 2 つの入口がある。

## 構成

```
bin/subcommands/device.rb, mcp.rb      CLI 入口
lib/cornix/device/
  mcp_server.rb   MCP (stdio, JSON-RPC 2.0) ツール定義と処理
  keyboard.rb     状態の読み出し（snapshot）、差分（diff）、反映（apply: バックアップ→差分書き込み→読み戻し検証）
  protocol.rb     VIA/Vial コマンド。書き込みは全て範囲検査してから送信
  keycodes.rb     キーコード文字列 <-> 16bit 値（Vial GUI 互換）。via_keycodes.yaml が表
  macro_codec.rb  マクロのバイト列 <-> layout.vil 表現
  hid_bridge.rb   ext/cornix_hid を子プロセスで起動して 32 バイトのレポートを送受信
ext/cornix_hid/main.swift   IOKit の raw HID ブリッジ。送信コマンドは許可リスト制（--self-test で確認）
spec/device/                FakeRmkDevice（RMK 0.8 の応答を模したデバイス）を使ったテスト
```

## MCP ツール

| ツール | 書き込み | 内容 |
|---|---|---|
| keyboard_info | なし | プロトコル、UID、レイヤー数、各種枠数、ロック状態 |
| read_keymap | なし | 現在の状態を layout.vil 形式で返す / 保存 |
| backup / list_backups | なし | tmp/device_backups/ への保存と一覧 |
| apply_layout | あり | 既定 dry run（差分 + confirm_token）。dry_run: false は confirm_token 必須 |

confirm_token は差分内容のハッシュ。dry run の後でキーボードやファイルが変わると一致せず書き込みを拒否する。

## 安全設計

- 危険コマンド（bootloader 移行 0x0B、EEPROM リセット 0x0A、全消去 0x06/0x10/0xFE0C、アンロック、一括書き込み 0x13）は
  ブリッジの許可リストで送信不可。
- 書き込みは 1 キーずつ（0x05）。layer/row/col、エンコーダ番号、TD/コンボ番号、マクロのオフセットとサイズを送信前に検査。
- QK_BOOT 等の boot 系キーコード（0x7C00〜0x7C0F）は差分計算の段階で拒否し、何も書き込まない。
- apply は反映前に必ずバックアップを取り、反映後に読み戻して差分が残っていないか確認する。

## アンロック（S/D 長押しなど）について

Vial アプリはマクロ保存時と QK_BOOT 割り当て時にアンロックを要求するが、これはアプリ側の動作。
RMK 0.8 のファームウェアでロック状態を見ているのはマトリクステスター（0x02 0x03）だけで、マクロ書き込みは検査しない。
そのため本機能ではアンロック操作は不要。

ファームウェアの詳細な挙動は [vial_device_protocol.md](../memories/vial_device_protocol.md) を参照。
