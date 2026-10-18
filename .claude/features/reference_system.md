# マクロ・タップダンスの参照

キーの割り当てからマクロ・タップダンスを指す書き方。利用者向けの説明は README の「マクロ・タップダンスの参照方法」。

| 書き方 | マクロ | タップダンス | 値 |
|---|---|---|---|
| 名前 | `Macro('Bracket Pair')` | `TapDance('Tab Escape')` | `Domain::Keycode::MacroCall(index)` / `TapDanceCall(index)` |
| 番号 | `Macro(0)` | `TapDance(2)` | 同上 |
| QMK 形式 | `M0` | `TD(2)` | 同上 |

- 3 つの書き方は解析の時点で同じ値（番号）になる。名前は値に残らない
- `Combo(...)` は .vil のキーに割り当てられないので `UnknownKeycode`（旧実装は受け付けていたが値にできなかった）
- マクロの `sequence` の中では名前参照を使わない（旧実装と同じ）

## 流れ

1. `Storage::ConfigLoader` が macros/ と tap_dance/ を先に読み、`name` → `index` の `Mapping::References` を作る
2. `KeycodeNotation#parse(text, references:)` が `Macro('名前')` を番号にする。見つからなければ
   「マクロ「名前」が見つかりません」の UnknownKeycode（構造検証のエラー）
3. 番号・QMK 形式の参照先がない場合は `Profile#diagnostics` が「マクロ M40 が定義されていません」を返す
4. decompile: `Profile#references`（名前 → 番号）から References を作り、`Formatter` が `Macro('名前')` / `TapDance('名前')` を書く。
   名前のない番号は `M2` / `TD(4)`。`'` を含む名前は `"..."` で囲む

## rename での書き換え

`Storage::ConfigEditor#replace_references(function, old_name, new_name)` が config/ のすべての YAML の
`Macro('旧名')` / `Macro("旧名")` をテキストで置き換える（関数の引数やコンボの出力の中にあっても書き換わる。ほかの書き方は保つ）。
番号・QMK 形式の参照は名前に依存しないので触らない。置き換え後に compile 結果が変わらないことを `Application::RenameFiles` が確かめる。

## テスト

- `spec/mapping/keycode_notation_spec.rb`（参照の解析・書き出し）
- `spec/domain/profile_diagnostics_spec.rb`（参照先の存在）
- `spec/storage/config_editor_spec.rb`, `spec/application/rename_spec.rb`（書き換え）
