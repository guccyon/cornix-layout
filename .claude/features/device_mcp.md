# キーボード直接操作と MCP サーバー

接続中の Cornix に Vial プロトコル（raw HID）で直接読み書きする機能。Vial Web / GUI を使わずに
`layout.vil` を差分だけ反映できる。CLI（`cornix device`）と MCP サーバー（`cornix mcp`）の 2 つの入口がある。

## 構成

```
lib/cornix/interface/cli/commands/device.rb, mcp.rb   CLI 入口
lib/cornix/interface/mcp/
  server.rb / protocol.rb   MCP（stdio, JSON-RPC 2.0）。応答は JSON.generate(ascii_only: true)
  tool_catalog.rb / tools.rb ツールの定義と処理（ユースケースを呼ぶだけ）
lib/cornix/application/
  device_info / device_read / device_backup / device_diff / device_apply / device_restore / list_backups
  Environment#open_device   Device::Session を開く（device_opener で差し替え可能）
lib/cornix/device/
  hid_bridge.rb      ext/cornix_hid を子プロセスで起動して 32 バイトのレポートを送受信
  protocol.rb        VIA/Vial コマンド。書き込みは全て範囲検査してから送信
  session.rb         Protocol とキーボードの形（定義・マトリクス・枠数・設定）
  reader.rb          全状態を Image::DeviceImage に読む（キーのない位置は nil）
  planner.rb         ImageDiff + マクロのバイト数 + ChangePolicy で Planning::Plan を作る
  change_policy.rb   boot 系キーコードの拒否（KeycodeCatalog#dangerous?）・RMK 未対応の警告
  writer.rb          token の確認 → バックアップ → 1 件ずつ書き込み → 読み直して検証（verification.rb）
  change_describer.rb 変更を人が読む文字列にする（キーコードは VialNotation の表記）
lib/cornix/planning/  ImageDiff / Change / Plan（データだけ。I/O なし）
lib/cornix/storage/backup_store.rb   tmp/device_backups/<YYYYmmdd-HHMMSS>.vil
lib/cornix/mapping/macro_codec.rb    マクロのバイト列 ⇄ Image::MacroAction
ext/cornix_hid/main.swift            IOKit の raw HID ブリッジ。送信コマンドは許可リスト制（--self-test で確認）
spec/device/                         FakeRmkDevice（RMK 0.8 の応答を模したデバイス）を使ったテスト
```

目標は `Storage::VilFile` で読んだ layout.vil の DeviceImage、現在は `Device::Reader` が読んだ DeviceImage。
両者の差分（`Planning::ImageDiff`）だけを書く。

## MCP ツール

| ツール | 書き込み | 内容 |
|---|---|---|
| keyboard_info | なし | プロトコル、UID、レイヤー数、各種枠数、ロック状態 |
| read_keymap | なし | 現在の状態を layout.vil 形式で返す / 保存 |
| backup / list_backups | なし | tmp/device_backups/ への保存と一覧 |
| apply_layout | あり | 既定 dry run（差分 + confirm_token）。dry_run: false は confirm_token 必須 |
| restore_backup | あり | 最新（または指定）のバックアップへ戻す。apply_layout と同じ二段階 |

confirm_token は差分内容のハッシュ（`Planning::Plan#token`）。dry run の後でキーボードやファイルが変わると一致せず書き込みを拒否する。
CLI の apply / restore は 1 回の接続の中で計画 → 確認（y/N、`--yes` で省略）→ 書き込みを行う（`confirm:` コールバック）。

## 未接続・切断時

- ブリッジが起動時にデバイスを見つけられないと `ERROR ...` を返し、HidBridge が `Cornix::DeviceError` にする。
  CLI は標準エラー出力に `エラー: ...` を表示して終了コード 1、MCP はツール結果を isError: true で返す。何も書き込まない。
- 送信後 1 秒応答がないとブリッジが ERROR を返す（BLE 切断・スリープ）。apply 中なら、書き込み済み件数と
  反映前バックアップのパスを含む DeviceError になる。apply / restore は差分だけ書くので、再実行で続きから揃う。
- テストでは `CORNIX_HID_BRIDGE` でブリッジを差し替えられる（spec/device/hid_bridge_spec.rb）。
  ユースケースのテストは `Environment.new(device_opener: ...)` で FakeRmkDevice を渡す（spec/application/device_environment_context.rb）。

## 安全設計

- 危険コマンド（bootloader 移行 0x0B、EEPROM リセット 0x0A、全消去 0x06/0x10/0xFE0C、アンロック、一括書き込み 0x13）は
  ブリッジの許可リストで送信不可。
- 書き込みは 1 キーずつ（0x05）。layer/row/col、エンコーダ番号、TD/コンボ番号、マクロのオフセットとサイズを送信前に検査。
- QK_BOOT 等の boot 系キーコード（`data/dangerous_keycodes.yaml`、0x7C00〜0x7C0F）は計画の段階で拒否し、何も書き込まない。
- apply は反映前に必ずバックアップを取り、反映後に読み戻して差分が残っていないか確認する。
- 実機を使うテストはない。開発中も実機には書き込まない（必要なら利用者の同意を得る）。

## アンロック（S/D 長押しなど）について

Vial アプリはマクロ保存時と QK_BOOT 割り当て時にアンロックを要求するが、これはアプリ側の動作。
RMK 0.8 のファームウェアでロック状態を見ているのはマトリクステスター（0x02 0x03）だけで、マクロ書き込みは検査しない。
そのため本機能ではアンロック操作は不要。

ファームウェアの詳細な挙動は [vial_device_protocol.md](../memories/vial_device_protocol.md) を参照。
