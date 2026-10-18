# キーコードの網羅（cornixhub の Vial キー一覧・QMK・vial-qmk）

- 基準: cornixhub.com/vial-keys の 231 キー（`spec/fixtures/cornixhub_vial_keys.txt` にすべて書けることを spec で検査）。
  cornixhub の一覧は Vial GUI ではなく QMK の名前を載せている（QK_LOCK や OU_AUTO は Vial GUI の表にない）
- 値の出典の優先順: vial-gui の keycodes_v6.py（Vial 名）> vial-qmk の quantum/keycodes.h > QMK の data/constants/keycodes/*.hjson。
  QMK の hjson は版ごとの差分で、`!reset!` はそのファイル群（magic / midi など接尾辞ごと）を空にし、`!delete!` は値を消す
- Vial GUI に名前のない値は keycodes.yaml で `vial: false`。設定ファイルでは name で書けるが、.vil には 0xHHHH で書く
  （Vial GUI が名前を知らないため）。`KeycodeCatalog#name` が設定ファイル用、`#vial_name` が .vil 用
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
