# キーボード直接操作と MCP サーバー

接続中の Cornix に Vial プロトコル（raw HID）で直接読み書きする機能。Vial Web / GUI を使わずに
`layout.vil` を差分だけ反映できる。CLI（`cornix device`、およびそのショートカットの `cornix pull` / `status` / `apply` / `restore`）と MCP サーバー（`cornix mcp`）、
VS Code 拡張の device のサーバー（`cornix serve --device`。下の「VS Code 拡張から」）の入口がある。
`status` / `apply` は compile してから、その出力 `tmp/build/layout.vil` を対象にする。

## 構成

```
lib/cornix/interface/cli/commands/device.rb, mcp.rb   CLI 入口
lib/cornix/interface/mcp/
  server.rb / protocol.rb   MCP（stdio, JSON-RPC 2.0）。応答は JSON.generate(ascii_only: true)
  tool_catalog.rb / tools.rb ツールの定義と処理（ユースケースを呼ぶだけ）
lib/cornix/interface/editor_server/handlers/device_*.rb   cornix serve --device の device/* のメソッド
lib/cornix/application/editor/device_operations.rb, device_changes.rb   その中身（比べる・反映・戻す、変更を位置に直す）
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

結果の `content` は人が読む要約と、結果の `#to_h`（`Application::Serialize`。CLI の `--json` と同じ変換）の JSON の 2 つ。
`keyboard_info` と、`save_path` なしの `read_keymap` は中身がそのまま JSON なので 1 つだけ返す。

ツールの名前（backup / list_backups / restore_backup）は、登録済みのクライアントを壊さないように前の版のまま残している。

## VS Code 拡張から

VS Code 拡張 v0.4 の反映（編集フォームの節「デバイス転送」。プレビュー → 確定）は、`cornix serve --device [--allow-writes]` を子プロセスとして起動し、
編集のサーバー（`cornix serve`）と同じ枠の JSON-RPC の `device/compare`（プレビュー）と `device/apply`（確定）で話す
（約束は [vscode-extension/protocol.md](vscode-extension/protocol.md) の 14、決めたことは ADR 018・019・020）。
サーバーは `device/backups`・`device/compareBackup`・`device/restore` も持つが、拡張からは使わない（戻すのは CLI の `cornix restore` / `cornix device restore`）。
編集のサーバーとは別のプロセスなので、実機を読む約 10 秒の間も候補や検証は止まらない。

- 中身は CLI・MCP と同じユースケース（`Compile` → `DeviceDiff` / `DeviceApply`（`expected_token`）/ `DeviceRestore` / `ListSnapshots`）を
  `Application::Editor::DeviceOperations` から呼ぶ。マトリクスの座標を位置（レイヤー・位置の名前）に直すのは `Application::Editor::DeviceChanges`（`Domain::PositionMap`）
- 比べるのは保存済みのファイルを compile したもの（未保存の変更は見ない）。`device/apply` はサーバーが計画し直し、`device/compare` の token と違えば何も書かない（MCP の confirm_token と同じ）
- 書き込みの止めは二重（ADR 019）:
  1. 拡張: 設定 `cornix.device.allowWrites`（既定 `false`）が `true` のときだけ `--allow-writes` を付けて起動する。書くのは毎回、違い・件数・書き込み先のキーボード名を見せるプレビューで「確定」を押したときだけ（検証のエラーがあるときは押せない）
  2. サーバー: `--allow-writes` なしで起動したものは `device/apply`・`device/restore` を `-32074`（WritesNotAllowed）で断り、実機を読みもしない
- バックアップ・1 件ずつの書き込み・読み直しの検証・boot 系キーコードの拒否は、下の「安全設計」のまま（CLI・MCP と同じ `Device::Writer` / `ChangePolicy`）
- 進み具合は `Device::Reader` / `Writer` の progress のコールバックから `device/progress` の通知にする。取り消し（`$/cancelRequest`）は読む間だけ受け付け、
  スレッドを使わず、進み具合を送るたびに標準入力を待たずに読んで拾う。書き始めたら取り消せない
- 実機の失敗は型で分かれ（下の「未接続・切断時」）、エラーの code になる（`-32070` DeviceUnavailable・`-32072` WriteIncomplete など）。拡張はその理由と直し方を出す
- テストは偽の実機だけ: Ruby は `spec/device/fake_cornix_device.rb`（FakeRmkDevice の上に、.vil の状態・使えない理由・途中で切れる・書いても変わらない、を足したもの）と
  適合テストのデータ `spec/fixtures/protocol/device/`、拡張は偽の device のサーバー `editors/vscode/test/fake-device-server/`。統合テストも本物のブリッジは起動しない

## スナップショット

キーボードの状態と compile の出力は `Storage::SnapshotStore` が `<tmp>/snapshots/<YYYYmmdd-HHMMSS>-<種類>/layout.vil` に残す（issue #25）。
上書きしない（同じ秒にほかのスナップショットがあれば、種類によらず作った順に `-2`, `-3` … を付ける。一覧は日時とこの番号で並べるので、apply の read → pre-apply のように同じ秒に続けて作っても作った順になる）。中身は layout.vil だけ（人が読む形の YAML は持たない。必要なら `cornix decompile` に渡す）。

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
- 使えないときの例外は `Cornix::DeviceUnavailable`（`DeviceError` の子）で、`reason` が理由（`:platform` macOS でない・`:bridge` ブリッジをビルド・起動できない・
  `:not_connected` 見つからない／開けない・`:timeout` 応答がない／ブリッジが終わった）。書き込みの途中の失敗は `Cornix::WriteIncomplete`（`applied`・`backup`）。
  VS Code 拡張の device のサーバー（`cornix serve --device`）がこれでエラーの code を分ける（docs/vscode-extension/protocol.md の 14.7）
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

## 番号の抜けのあるプロファイル（2026-10-22 に実機で確認、#83）

レイヤー 0・1・3・4、マクロ 0・2、タップダンス 0・2、コンボ 0・2 だけを定義したプロファイル（ほかは compile が空のデータで埋める）を書いて確かめた。

- `cornix device apply` で書き、`cornix device read` で読み直すと 16bit 値はすべて一致した。抜けた番号（レイヤー 2、M1、TD(1)、コンボ 1）は空のまま残り、
  後ろの番号（M2、TD(2)、コンボ 2）はずれない。マクロは NUL 区切りのバッファを丸ごと書くが、空のマクロは NUL 1 つで番号を保つ
- Vial（Web）で読み込んでも同じで、Vial で保存した .vil も 16bit 値で一致した（レイヤー 2 は空、M1 は空、M2 は元の中身）
- そのあと元のプロファイルを apply すると、抜けた番号に中身が入り、元の状態と一致した
- そのため番号の抜けは許し、警告しない。compile の出力（空のデータで埋める）も変えない
- 読み直しで 1 度だけ、タップダンス 22 が `["0x2", KC_NO, KC_NO, KC_NO, 0]` と読めた（apply の直後の検証では一致、続けて 2 回読み直すと正しい値）。
  BLE 越しの読み出しで応答を取り違えたとみられる。差分が出たら読み直してから判断する

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
