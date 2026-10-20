# キーコードの網羅（cornixhub の Vial キー一覧・QMK・vial-qmk）

- 基準: cornixhub.com/vial-keys の 231 キー（`spec/fixtures/cornixhub_vial_keys.txt` にすべて書けることを spec で検査）。
  cornixhub の一覧は Vial GUI ではなく QMK の名前を載せている（QK_LOCK や OU_AUTO は Vial GUI の表にない）
- 値の出典の優先順: vial-gui の keycodes_v6.py（Vial 名）> vial-qmk の quantum/keycodes.h > QMK の data/constants/keycodes/*.hjson。
  QMK の hjson は版ごとの差分で、`!reset!` はそのファイル群（magic / midi など接尾辞ごと）を空にし、`!delete!` は値を消す
- Vial GUI に名前のない値は keycodes.yaml で `vial: false`。設定ファイルでは name で書けるが、.vil には 0xHHHH で書く
  （Vial GUI が名前を知らないため）。`KeycodeCatalog#name` が設定ファイル用、`#vial_name` が .vil 用。
  引数付き（レイヤー操作・LTn・Mn）を名前で書く範囲は VialNotation の NAMED_LAYERS / NAMED_LAYER_TAPS / NAMED_MACROS が決める
- マクロは 0x7700〜0x777F（M0〜M127、vial-qmk の QK_MACRO_MAX）。0x7780〜0x77BF は QK_CONNECTION（OU_AUTO など）。
  旧 Vial 表（spec/fixtures/vial_keycodes_v6.yaml）は M255 まで名前を持っていたが、Vial GUI 本体は macro_count 個しか名前を作らない
- RMK 0.8 の `from_via_keycode`（rmk/src/host/via/keycode_convert.rs）は Magic・RGB・DB_TOGG・QK_LOCK・QK_LEAD・DT_*・OU_*・
  マクロ M32 以降などを KeyAction::No にする。表に載せるのは書けるようにするためで、実機で効くとは限らない
- 含めていないもの: MIDI（MI_*、Vial GUI にはある）、Bluetooth の BT_*（QMK のみ）、LED Matrix（LM_*）、Unicode（UC_*）
- 別名を足すと decompile の書き出しが変わる（先頭の別名が正規形）。compile の結果は変わらない
- ワンショットの OS_LSFT などは QMK では #define（OSM(MOD_LSFT)）なので、表ではなく `Modifiers::ONE_SHOT_BITS` で受け付ける。
  書き出しは従来どおり OSM(MOD_LSFT)
- Magic は cornixhub の一覧外の CL_TOGG / BS_TOGG も vial: false で足した（EC_* とそろえる）
- 日本語配列の別名は QMK 名と読み違えないようにした: macOS のかな / 英数は `MacKana` / `MacEisu`（KC_LANG1 / KC_LANG2）、
  JIS の ¥ キーは `JisYen`（`"¥"` は LALT(KC_Y)、`KC_KANA` は 0x88 で別の値）
- dangerous_keycodes.yaml から DB_TOGG（0x7C02）を外した（デバッグ出力の切り替えで危険ではない）
- 2026-10-19 に Cornix を接続した Vial（vial.rocks）で確認: QK_REPEAT_KEY / QK_ALT_REPEAT_KEY（repeat_key）、QK_LAYER_LOCK（layer_lock）、
  USER08 以降（customKeycodes は 8 個）は非表示。data/unsupported_keycodes.yaml で validate などが警告する（#17）。
  Caps Word、PDF(n)、FN_MO13/23、Dynamic Macro は表示される。vial.rocks は vial-gui 0.7.5 で LAG / LAG_T / GUI Toggle を知らない（#18）
- .vil の表記の基準は Vial Web（vial.rocks）の中身の vial-gui 0.7.5（e42622c）。0.7.5 の `Keycode.deserialize` は
  知らない名前を AnyKeycode で解釈し、失敗すると黙って 0（KC_NO）にするので、Load saved layout でキーが消える。
  0.7.5 より後の LAG(kc) / LAG_T(kc) / MAGIC_TOGGLE_GUI、Vial GUI が枠の数だけ作る名前の外（USER08〜（Cornix の customKeycodes は 8 個）、MO(10)〜 / LT10〜、
  M32〜。TD は 0〜255 常にある）は 16 進で書く。TO(10) は AnyKeycode が ON_PRESS を足して別の値に読むので特に危ない
- 確認方法: spec/fixtures/expected/vial_gui_codes.py（先頭に手順）で vial-gui v0.7.5 の `Keycode.serialize` を Cornix の枠で
  全 16bit 値に適用し、vial_gui_0_7_5_codes.tsv.gz に保存する。vial_notation_spec が format_code と全値で一致を検査する
- 実機書き込み前の差分表示・警告（Environment#describer）は .vil の表記だが、16 進になる値だけ設定ファイルの表記にする
- `+` / `-` を含む別名（`Vol+` / `Vol-`、PR #54）: 修飾キー式は `名前 +` を繰り返し読むので、`Ctrl + Vol+` の `Vol+` を
  修飾名 `Vol` と読んでいた。`Parser#modifier_expression` は残りが別名・QMK 名そのものならそこで止める。
  不変条件 `parse(format(k)) == k` の spec（全 16bit 値）がこの種の衝突を見つけるので、記号の別名を正規名にしたら必ず回す
- 記号の別名と異体字セレクタ: `▶︎`（U+FE0E）/ `▶️`（U+FE0F）は目に見えないので、`Parser#lookup` はセレクタを除いても引き直す。
  別名の表にはセレクタなしの形（`▶▶`）があれば足りる。セレクタ付きを載せるときは YAML で `"︎"` とエスケープして書く
- `MediaPlay`（再生だけ）は QMK / Vial にない。`KC_MPLY` は再生 / 一時停止
