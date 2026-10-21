# キーボード直接操作と MCP サーバー

接続中の Cornix に Vial プロトコル（raw HID）で直接読み書きする機能。Vial Web / GUI を使わずに
`layout.vil` を差分だけ反映できる。CLI（`cornix device`、およびそのショートカットの `cornix pull` / `status` / `apply` / `restore`）と MCP サーバー（`cornix mcp`）の入口がある。
`status` / `apply` は compile してから、その出力 `tmp/build/layout.vil` を対象にする。

## 構成

```
lib/cornix/interface/cli/commands/device.rb, mcp.rb   CLI 入口
lib/cornix/interface/mcp/
  server.rb / protocol.rb   MCP（stdio, JSON-RPC 2.0）。応答は JSON.generate(ascii_only: true)
  tool_catalog.rb / tools.rb ツールの定義と処理（ユースケースを呼ぶだけ）
lib/cornix/application/
  device_info / device_read / device_backup / device_diff / device_apply / device_restore / list_snapshots
  Environment#open_device   Device::Session を開く（device_opener で差し替え可能）
lib/cornix/device/
  hid_bridge.rb      ext/cornix_hid を子プロセスで起動して 32 バイトのレポートを送受信
  protocol.rb        VIA/Vial コマンド。書き込みは全て範囲検査してから送信
  session.rb         Protocol とキーボードの形（定義・マトリクス・枠数・設定）
  reader.rb          全状態を Image::DeviceImage に読む（キーのない位置は nil）
  planner.rb         ImageDiff + マクロのバイト数 + ChangePolicy で Planning::Plan を作る
  change_policy.rb   boot 系キーコードの拒否（KeycodeCatalog#dangerous?）・RMK 未対応の警告
  writer.rb          token の確認 → バックアップ（pre-apply / pre-restore のスナップショット）→ 1 件ずつ書き込み → 読み直して検証（verification.rb）
  change_describer.rb 変更を人が読む文字列にする（キーコードは VialNotation の表記）
lib/cornix/planning/  ImageDiff / Change / Plan（データだけ。I/O なし）
lib/cornix/storage/snapshot_store.rb tmp/snapshots/<YYYYmmdd-HHMMSS>-<種類>/layout.vil（下の「スナップショット」）
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
| backup / list_backups | なし | スナップショット（種類 backup）の保存と、スナップショットの一覧（kind で絞り込み） |
| apply_layout | あり | 既定 dry run（差分 + confirm_token）。dry_run: false は confirm_token 必須 |
| restore_backup | あり | 最新の pre-apply（または指定したスナップショット）へ戻す。apply_layout と同じ二段階 |

confirm_token は差分内容のハッシュ（`Planning::Plan#token`）。dry run の後でキーボードやファイルが変わると一致せず書き込みを拒否する。
CLI の apply / restore は 1 回の接続の中で計画 → 確認（y/N、`--yes` で省略）→ 書き込みを行う（`confirm:` コールバック）。

ツールの名前（backup / list_backups / restore_backup）は、登録済みのクライアントを壊さないように前の版のまま残している。

## スナップショット

キーボードの状態と compile の出力は `Storage::SnapshotStore` が `<tmp>/snapshots/<YYYYmmdd-HHMMSS>-<種類>/layout.vil` に残す（issue #25）。
上書きしない（同じ秒・同じ種類なら `-2`, `-3` … を付ける）。中身は layout.vil だけ（人が読む形の YAML は持たない。必要なら `cornix decompile` に渡す）。

| 種類 | 保存するところ |
|---|---|
| read | `UseCase#read_device`（DeviceRead と、DeviceDiff / DeviceApply / DeviceRestore の `plan_for`）。pull / init もここを通る |
| build | `Compile`（`-o` で出力先を変えても残す） |
| backup | `DeviceBackup`（`cornix device backup`、MCP の backup。read は残さない） |
| pre-apply / pre-restore | `DeviceApply` の書き込みの直前（Writer の backup）。restore は `snapshot_kind: 'pre-restore'` で呼ぶ |
| legacy | 前の版の `<tmp>/device_backups/<YYYYmmdd-HHMMSS>.vil`。書かず、一覧と resolve にだけ使う |

- read と build は保存のたびに種類ごとに新しい `KEEP`（50）件だけ残す。ほかの種類は消さない（書き込みの前の状態は消さない）
- `resolve(nil)`（restore の既定）は最新の pre-apply、なければ legacy の最新。続けて restore しても同じ pre-apply を指すので、
  restore の取り消しは pre-restore を名前で渡す（前の版の「続けて restore すると復元前に戻る」から変えた）
- `<tmp>/build/layout.vil`（compile の出力）と `<tmp>/layout.vil`（pull の読み出し）は今までどおり書く。status / apply / MCP の apply_layout と
  decompile の既定の入力がそこを読むため、また Round-trip check などで利用者が置いたファイルを読み出しで上書きしないため

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
- apply は反映前に必ずバックアップ（pre-apply のスナップショット）を取り、反映後に読み戻して差分が残っていないか確認する。
- 実機を使うテストはない。開発中も実機には書き込まない（必要なら利用者の同意を得る）。

## アンロック（S/D 長押しなど）について

Vial アプリはマクロ保存時と QK_BOOT 割り当て時にアンロックを要求するが、これはアプリ側の動作。
RMK 0.8 のファームウェアでロック状態を見ているのはマトリクステスター（0x02 0x03）だけで、マクロ書き込みは検査しない。
そのため本機能ではアンロック操作は不要。

## ファームウェア（RMK 0.8 系）の挙動

Cornix の Vial 応答は vial-qmk ではなく RMK（Rust 製ファームウェア）のもの。キーボード定義の customKeycodes
（BT0..CLR_PEER）が RMK の vial.json と一致し、設定クエリが 9 項目（0x19 なし）・ロック機能ありなので
RMK v0.8.0〜v0.8.3（この範囲の Vial 処理は同一コード）と判断した。
参照コード: `rmk/src/host/via/mod.rs`, `rmk/src/host/via/vial.rs`, `rmk/src/host/via/keycode_convert.rs`（tag rmk-v0.8.3）。

vial-qmk と違う危険な挙動と、それに対する本ツールの扱い:

- `0x0B` bootloader 移行、`0x0A` EEPROM リセットがロックなしで即実行される → ブリッジで送信禁止
- `0x13` キーマップ一括書き込みは size をキー数として扱い 32 バイトを超えて読むのでパニックする → 使わない
- `0x05` / エンコーダ / マクロは範囲検査がなく、範囲外でパニックする → Ruby 側で全て検査
- マクロ書き込み `0x0F` はオフセット 0 でバッファ全体をクリアする → Vial GUI と同じく先頭から全体を書く
- `QK_BOOT`(0x7C00) / `QK_REBOOT`(0x7C01) はキーに書き込めてしまう（vial-qmk のようなロック時のファイアウォールがない）→ 書き込み禁止
- マクロ書き込みもロック不要（上の「アンロックについて」）

## 実装の補足

- `ext/cornix_hid/main.swift`: IOKit で raw HID（VID 0xE118, usage page 0xFF60/0x61）を開く行プロトコルのブリッジ。
  許可リストは `tmp/cornix-hid --self-test` でデバイスなしに確認できる
- キーコード表は `data/keycodes.yaml`（旧 `lib/cornix/device/via_keycodes.yaml` を引き継いだもの。vial-gui の keycodes.py / keycodes_v6.py から
  AST 解析で抽出した表）。実機キーマップ 560 キーで
  encode / decode とも layout.vil と一致することを確認済み。旧表は `spec/fixtures/vial_keycodes_v6.yaml` に残し、
  全 16bit 値で旧実装と同じ文字列になることを spec で確かめている。16bit 値 ⇄ キーコードは `Mapping::KeycodeCodec`、.vil の文字列は `Mapping::VialNotation`
- 書き込み禁止のキーコードは `data/dangerous_keycodes.yaml`（`KeycodeCatalog#dangerous?`）、設定の幅は `data/qmk_settings.yaml`
  （`QmkSettingCatalog`）。`Device::Protocol` はこれらを注入して使う
- キーボード定義は xz 圧縮。macOS 標準の `compression_tool -decode -a lzma` で展開している
- MCP サーバーは LANG 未設定だと `Encoding.default_external` が US-ASCII になるので、`cornix mcp` で UTF-8 にしている
  （応答の `ascii_only` は上の「構成」）
- BLE 越しで 1 往復約 40ms。全状態の読み出し（定義・キーマップ・エンコーダ・TD/コンボ 64 件・マクロ・設定）で約 10 秒
