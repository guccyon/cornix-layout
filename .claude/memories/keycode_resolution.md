# キーコード解決の経路（compile 時）

2026-10-12 に修正した不具合からの知見。

- validate（semantic 検証）と compile（`to_qmk`）は別々のコードで値を解決している。
  validate が通っても `to_qmk` 側がエイリアスや参照を解決していないと、未変換の値や null が layout.vil に出る。
  新しい項目を追加するときは、検証と `to_qmk` の両方で同じ解決（エイリアス → 修飾キー表現 → 参照）をすること。
- コンボ: `Combo#to_qmk(keycode_converter:, reference_converter:)`。`trigger_keys` と `output_key` の両方をエイリアス解決する。
  `VialConfig#to_qmk` → `ComboCollection#to_qmk_array` に `keycode_converter` を渡す。
- エンコーダ: push は layout 配列側、ccw/cw は encoder_layout 側に書かれる。
  どちらも `EncoderMapping.resolve_keycode`（修飾キー表現・`TapDance('名前')` などの参照・エイリアス）を通す。
  `Layer#to_qmk` は `EncoderMapping#push_to_qmk` を使う。
- MCP サーバー: LANG 未設定だと Ruby の `Encoding.default_external` が US-ASCII になる。
  入力は UTF-8 として読み、出力は `JSON.generate(obj, ascii_only: true)` でクライアントのロケールに依存しないようにしている。
