# QMK Settings の順序と差分検出

## Vial QMK インデックスの正しい対応（boolean 3種に注意）

`Settings::VIAL_QMK_INDEX`（`lib/cornix/models/settings.rb`）の対応:

- `permissive_hold` => 22
- `hold_on_other_key_press` => 23
- `chordal_hold` => 26

（過去に chordal=22 / permissive=23 / hold_on=26 と取り違えていた。3つとも boolean で
値が同じ(true→1)だと出力数値が一致してしまい気づきにくいので注意。）
`bin/diff_layouts` は `VIAL_QMK_INDEX` を逆引きして human readable なキー名
（例 `keyboard.permissive_hold (22)`）で差分を表示する。


## Vial settings のキー順序（数値昇順）

`layout.vil` の `settings` は Vial QMK インデックス（整数）をキーに持つ。
出力時は**数値昇順**にソートする（例: `2, 6, 7, 18, 19, 22, 23, 26, 27`）。

- 実装: `Cornix::Models::Settings#to_qmk`（`lib/cornix/models/settings.rb`）で
  `hash.sort_by { |k, _| k.to_i }.to_h` を返す。
- 理由: `yaml_to_qmk_index` は `VIAL_QMK_INDEX` の定義順（keyboardグループ→vialグループ）で
  Hash を構築するため、そのままだと `vial.combo_timing_window`(=2) が末尾に来てしまう。
- `JSON.pretty_generate`（`lib/cornix/writers/vial_writer.rb`）は Hash の挿入順を保持するため、
  ソート順がそのまま出力順になる。
- `to_i` を使うことで、キーが文字列（from_qmk経由のJSON）でも整数（yaml変換後）でも
  正しく数値ソートできる。

## diff_layouts の settings 比較の落とし穴

Ruby の `Hash#==` は**キー順序を無視**する（`{a:1,b:2} == {b:2,a:1}` は true）。
そのため `bin/diff_layouts` で `orig['settings'] == comp['settings']` を使うと、
settings のキー順序だけが異なる差分を検出できず「一致」と誤判定する。

- 対策: 順序込みで比較するため `orig['settings'].to_a == comp['settings'].to_a` を使う。
- 総合判定 `orig_n == comp_n` も Hash 比較なので settings 順序差を見逃す。
  `&& settings_match` を併用して判定する。
- FILES DIFFER セクションには settings 専用の詳細差分ブロック（キー集合/順序 + 各キー値）を出力する。

配列（layout/macro等）は元々 `==` が順序依存なので問題ないが、Hash（settings）だけ
この盲点があることに注意。
