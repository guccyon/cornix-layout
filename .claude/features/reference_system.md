# マクロ・タップダンスの参照

キーの割り当てからマクロ・タップダンスを指す書き方。利用者向けの説明は [README.ja.md](../../README.ja.md) の「マクロ・タップダンスの参照」。

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

## 名前付きショートカット（`Shortcut('名前')`）

nape_pro-layout の `Shortcut('名前')` に倣ったもの。利用者向けの説明は [README.ja.md](../../README.ja.md) の「名前付きショートカット」。

- 定義は `config/shortcuts.yaml`（任意）の `shortcuts: { 名前: キーコードの表記 }`。`Domain::ShortcutLibrary`（名前 → Keycode）として
  `Profile#shortcuts` が持つ。デバイス（layout.vil）にはないので、`ProfileMapper#to_profile` は previous のものを引き継ぐ
- `ConfigLoader` は macros / tap_dance の名前で References を作って shortcuts.yaml を読み（値に Macro('名前') は書ける。
  `Shortcut(...)` は問題にする）、ショートカットを加えた References でレイヤー・タップダンス・コンボを読む
- `Parser` は `Shortcut('名前')` を定義の Keycode そのものにする（MacroCall のような参照の値は作らない）。
  なければ「ショートカット「名前」は shortcuts.yaml に定義されていません」。番号の引数は不可
- shortcuts.yaml の定義のうち解釈できないものは問題を記録して除く（正しい定義への参照まで「定義されていません」にしない）。
  値の中のどこかに `Shortcut(` があれば「書けません」の問題にする
- `Formatter` は値が定義の **ちょうど 1 つ** と一致すれば `Shortcut('名前')` で書く（複数一致・references にショートカットがなければ
  ふつうの正規形。NoKey / Trans は対象外）。`ConfigWriter` は shortcuts.yaml の値を、既存のファイル（`.yml` ならそこに書く）と
  同じキーコードなら元の書き方のまま書く（整数の値は 16 進の書き方が読み込みで失われるので正規形にする）。YAML のコメントは残らない
- この書き戻し（`ConfigRepository#save` と `ProfileMapper#to_profile` の previous）は、今は利用者の操作からは使われない
  （decompile は previous を渡さない）。設定を書き戻す機能（pull など）を作るときのための仕組み
- nape_pro-layout との違い: cornix には割り当ての注記（Assignment）がないので、どの位置が `Shortcut(...)` で書かれていたかは
  Profile に残らない。書き出すときは値の一致だけで決める
- マクロの `sequence` の中では使えない（マクロの名前参照と同じ）

### 同梱のショートカット（`data/shortcuts/`）

cornixhub（https://cornixhub.com/shortcuts）で共有されているショートカットを同梱し、shortcuts.yaml に書かなくても使えるようにしたもの。

- `data/shortcuts/<アプリ>.yaml` は「アプリ → カテゴリ → ラベル: キーコードの表記」の入れ子。`Mapping::ShortcutCatalog` が
  キーを `:` でつないだ名前（`Spotify:再生:次のクリップ`）にして読む。キーに `:` は使えない（cornixhub のラベルには `:` がない。
  `/` と `・` はあるので区切りには使わない）。カテゴリを省くと Windows の「検索」（Win + S と Ctrl + F）などが衝突するので 3 段にした
- 表記は正規形で書く（`spec/mapping/shortcut_catalog_spec.rb` が検査する）。同梱データの誤りは `ConfigError`
- `ConfigLoader` は shortcuts.yaml を読んだあと、References の `preset_shortcuts` に同梱の定義を渡す。
  `References#shortcut` は利用者の定義を先に引くので、shortcuts.yaml に同じ名前を書けば上書きできる
- `Profile#shortcuts` は利用者の定義だけ。`Formatter`（`References#shortcut_name`）も利用者の定義だけを使う
  （同梱の定義も使うと、decompile で Command + B が `Shortcut('Xcode:一般:ビルド')` のように書かれてしまう）
- 1 つのキーコードで表せないもの（連続して押す・押したまま操作する 6 件）は入れていない
- `ShortcutCatalog` は `Application::Environment#shortcut_catalog` から `ConfigRepository` に渡す。マクロの keys など References::NONE の場面では
  `Shortcut(...)` は「ここでは使えません」（`References#shortcuts_available?`）
- データは cornixhub のページの JS から取り出したもの（2026-10-19）。英語版はなく、ラベルは日本語。アプリ名はサイトの英語表記
  （note は「メモ」と訳されているので note のまま）、訳のないカテゴリ window は「ウィンドウ」にした

## rename での書き換え

`Storage::ConfigEditor#replace_references(function, old_name, new_name)` が config/ のすべての YAML の
`Macro('旧名')` / `Macro("旧名")` をテキストで置き換える（関数の引数やコンボの出力の中にあっても書き換わる。ほかの書き方は保つ）。
番号・QMK 形式の参照は名前に依存しないので触らない。置き換え後に compile 結果が変わらないことを `Application::RenameFiles` が確かめる。

## テスト

- `spec/mapping/keycode_notation_spec.rb`（参照・Shortcut の解析・書き出し）
- `spec/domain/shortcut_library_spec.rb`, `spec/storage/config_repository_spec.rb`（shortcuts.yaml の読み書き・同梱のショートカット）
- `spec/mapping/shortcut_catalog_spec.rb`（data/shortcuts/ の読み込みと検査）
- `spec/domain/profile_diagnostics_spec.rb`（参照先の存在）
- `spec/storage/config_editor_spec.rb`, `spec/application/rename_spec.rb`（書き換え）
