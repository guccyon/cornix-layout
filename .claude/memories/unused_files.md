# 未使用のファイルとファイル名の番号（issue #85）

- 番号は `index:` だけで決まる。ファイル名の接頭辞は読まない（レイヤーの番号の一致の検査はやめた）。書くとき（decompile・拡張の追加）は今どおり接頭辞を付ける
- 未使用 = `index:` のキーがないか null（`Storage::Schema::Header.unused?`）。整数でない値は今どおりエラー。`enabled:` は使わない
- `ConfigLoader#load_all` → `Loaded(profile, unused)`。未使用のファイルは仮の index 0 を入れて同じ `Schema::*File` で読み、問題は `UnusedFile#problems`（InvalidConfig にしない。`InvalidConfig#unused` にも持たせる）
- `DiagnosticLocator#files` は未使用のファイルを除いて並べる。拡張の Address・項目の操作（Snapshot / Slots / Targets / Operation#find_item / RenamePosition）はみなこれを通るので、ここを直せばずれない。
  除き忘れると、未使用のファイルより後ろの項目が 1 つずつ別のファイルを指す（spec の 0_spare.yaml はそれを確かめるため 0_layer_0 と 1_layer_1 のあいだに並ぶ名前にしてある）
- 名前の参照は使っているものだけ。未使用の名前は `References#unused_macro?` で「未使用です」と案内するためだけに持つ
- 未使用のファイルの問題: validate は warning（message の末尾に「（未使用のファイルなので compile に含めません）」）、拡張は `source: "structure"` の warning で `status` は ok のまま
- RenamePosition は未使用のレイヤーのファイルも書き換える（残すと位置の名前の警告になる）
- `RenameFiles` の「番号の接頭辞が同じ」の事前検証はやめた（compile の前後の照合は残す。Claude への依頼文は接頭辞を保つよう頼むまま）
- 未使用の項目を拡張で開いて編集する・使う / 未使用にする・番号を変えるのは #105
