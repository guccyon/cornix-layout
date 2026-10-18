# QMK Settings の順序と差分検出

## QSID の対応（boolean 3 種に注意）

QSID・名前・幅は `data/qmk_settings.yaml`（`Mapping::QmkSettingCatalog`）にある。

- `permissive_hold` => 22
- `hold_on_other_key_press` => 23
- `chordal_hold` => 26

（過去に chordal=22 / permissive=23 / hold_on=26 と取り違えていた。3 つとも boolean で
値が同じ(true→1)だと出力数値が一致してしまい気づきにくいので注意。）
`bin/diff_layouts` は `QmkSettingCatalog#fetch` で QSID を引き、`keyboard.permissive_hold (22)` の形で差分を表示する。

## layout.vil の settings のキー順序（数値昇順）

`layout.vil` の `settings` は QSID（文字列）をキーに持ち、**数値昇順**で書く（例: `2, 6, 7, 18, 19, 22, 23, 26, 27`）。

- `Domain::QmkSettings` は values を QSID でソートして持ち、`Storage::VilFile::Encoder` も
  `sort_by { |qsid, _| qsid.to_i }` で書く。`JSON.pretty_generate` は Hash の挿入順を保つので、この順がそのまま出力順になる。
- グループ順（keyboard → vial）のまま書くと `vial.combo_timing_window`(=2) が末尾に来てしまい、Vial の出力と一致しない。
- config 側（`config/settings/qmk_settings.yaml`）は名前の形（`keyboard:` / `vial:` の入れ子）で書く。
  旧 decompile が書いた QSID の番号の形（`'7': 180`）も読める（`Storage::Schema::SettingsFile`）。

## diff_layouts の settings 比較の落とし穴

Ruby の `Hash#==` は**キー順序を無視**する（`{a:1,b:2} == {b:2,a:1}` は true）。
そのため settings を `==` で比べると、キー順序だけが異なる差分を「一致」と誤判定する。

- 対策: `bin/diff_layouts` は `orig.settings.to_a == comp.settings.to_a` で順序込みで比べ、
  総合判定も `orig == comp && settings_match` にしている（`Image::DeviceImage#==` も settings は Hash 比較）。
- FILES DIFFER のときは settings 専用の詳細差分（キー集合/順序 + 各キーの値）を出す。

配列（layout/macro 等）は `==` が順序依存なので問題ないが、Hash（settings）だけこの盲点がある。

関連: [[vial_qmk_settings_restore_issue]]
