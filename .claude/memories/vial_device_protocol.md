# キーボード直接操作（cornix device / cornix mcp）の知見

## ファームウェアは RMK 0.8 系
- Cornix の Vial 応答は vial-qmk ではなく RMK（Rust 製ファームウェア）。キーボード定義の customKeycodes
  （BT0..CLR_PEER）が RMK の vial.json と一致し、設定クエリが 9 項目（0x19 なし）・ロック機能ありなので
  RMK v0.8.0〜v0.8.3（この範囲の Vial 処理は同一コード）と判断した。
- 参照コード: `rmk/src/host/via/mod.rs`, `rmk/src/host/via/vial.rs`, `rmk/src/host/via/keycode_convert.rs`（tag rmk-v0.8.3）

## RMK 0.8 の危険な挙動（vial-qmk と違う点）
- `0x0B` bootloader 移行、`0x0A` EEPROM リセットがロックなしで即実行される → ブリッジで送信禁止。
- `0x13` キーマップ一括書き込みは size をキー数として扱い 32 バイトを超えて読むのでパニックする → 使わない。
- `0x05` / エンコーダ / マクロは範囲検査がなく、範囲外でパニックする → Ruby 側で全て検査。
- マクロ書き込み `0x0F` はオフセット 0 でバッファ全体をクリアする。Vial GUI と同じく先頭から全体を書く。
- `QK_BOOT`(0x7C00) / `QK_REBOOT`(0x7C01) はキーに書き込めてしまう（vial-qmk のようなロック時のファイアウォールがない）→ 書き込み禁止。
- マクロ書き込みもロック不要（Vial GUI はアンロックを求めるが、ファームウェアは検査しない）。

## 実装
- `ext/cornix_hid/main.swift`: IOKit で raw HID (VID 0xE118, usage page 0xFF60/0x61) を開く行プロトコルのブリッジ。
  許可リストは `tmp/cornix-hid --self-test` でデバイスなしに確認できる。
- キーコード表は `data/keycodes.yaml`（旧 `lib/cornix/device/via_keycodes.yaml` を引き継いだもの）。vial-gui の
  keycodes.py / keycodes_v6.py から AST 解析で抽出した表で、実機キーマップ 560 キーで encode/decode とも layout.vil と
  一致することを確認済み。16bit 値 ⇄ キーコードは `Mapping::KeycodeCodec`、.vil の文字列は `Mapping::VialNotation`。
  旧表は `spec/fixtures/vial_keycodes_v6.yaml` に残し、全 16bit 値で旧実装と同じ文字列になることを spec で確かめている。
- 書き込み禁止のキーコードは `data/dangerous_keycodes.yaml`（`KeycodeCatalog#dangerous?`）、設定の幅は `data/qmk_settings.yaml`
  （`QmkSettingCatalog`）。`Device::Protocol` はこれらを注入して使う。
- キーボード定義は xz 圧縮。macOS 標準の `compression_tool -decode -a lzma` で展開している。
- MCP サーバーは LANG 未設定だと `Encoding.default_external` が US-ASCII になるので、`cornix mcp` で UTF-8 にし、
  応答は `JSON.generate(obj, ascii_only: true)`（`Interface::Mcp::Protocol`）でクライアントのロケールに依存しないようにしている。
- BLE 越しで 1 往復約 40ms。全状態の読み出し（定義・キーマップ・エンコーダ・TD/コンボ 64 件・マクロ・設定）で約 10 秒。
