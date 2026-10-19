# キーコードの表記

設定ファイル（`config/*.yaml`）に書くキーコードの文字列と、その解析・書き出しの仕組み。
文字列 ⇄ `Domain::Keycode` の変換は `Mapping::KeycodeNotation` だけが行う（.vil の表記は `Mapping::VialNotation`）。
値の型は [domain-model.md](domain-model.md) の「Keycode」を参照。

## 修飾キー表現（VS Code 風）

`Cmd + Q` のような表記を修飾キー付きのキーコードにする。利用者向けの説明は [README.ja.md](../README.ja.md) の「修飾キー表現」。

### 実装の場所

- 解析: `Mapping::KeycodeNotation::Parser`（`lib/cornix/mapping/keycode_notation/parser.rb`）
  - 解釈の順: 文字列全体が別名・QMK 名 → ワンショット名（`OS_LSFT` など。`Modifiers::ONE_SHOT_BITS`）→ 参照 → `M3` → `0xHHHH` → 修飾キー式（`修飾名 +` で始まる）→ 関数形式
  - 別名を先に見るので、`+`（`LSFT(KC_EQUAL)`）や `LCtrl` のような別名は修飾キー式より優先される
- 修飾名・修飾関数・MOD_ 定数の表: `Mapping::KeycodeNotation::Modifiers`（`keycode_notation/modifiers.rb`）
  - `EXPRESSION`（`Cmd` / `Command` / `Option` / `RCtrl` ...）、`FUNCTIONS`（`LCTL`, `C_S`, `SGUI`, `MEH`, `HYPR` ... → ビット）、
    `FUNCTION_ALIASES`（`LCS` → `C_S`, `LSG` → `SGUI` など）、`MOD_TAP_BITS`、`ONE_SHOT_BITS`、`CONSTANTS`
- 値: `Domain::ModifierSet`（左右のどちらか一方 + ctrl / shift / alt / gui の 5bit）と `Domain::Keycode::Modified(mods, base)`
- 16bit 値: `Mapping::KeycodeCodec`（`mods.bits << 8 | base`）
- 書き出し: `Mapping::KeycodeNotation::Formatter`

### 規則

- 修飾キー式は ModifierSet で組み立てる（文字列で `LCS(...)` などを作らない）。そのため
  - 修飾キーの順序は値に影響しない
  - 左右の混在（`Shift + RCmd + A`）は `UnknownKeycode`（「左右の修飾キーは混在できません」）。QMK の 5bit では表せない
  - 修飾できるのは基本キーだけ（`Cmd + LT(1, Space)` はエラー）
- .vil には `VialNotation` が Vial の名前で書く（`C_S`, `SGUI`, `LCA`, `LSA`, `MEH`, `LCG`, `LAG`, `LCAG`, `HYPR`, `RCG` ...）。
  Vial に名前のない組み合わせ（`LCSG`, `LSAG`, 右側の多く）は `0x0B17` のような 16bit 値で書く。
  旧実装は `LCS(...)` / `LCSG(...)` など Vial が読めない名前を書き、右 Ctrl+Shift+Alt を MEH にしていた（直した）
- decompile（`Formatter`）の正規形: 別名があれば別名（`LSFT(KC_1)` → `!`）、なければ修飾キー式。
  順序は `Ctrl, Option, Shift, Command`、右側は `RCtrl, ROption, RShift, RCommand`（`EXPRESSION_ORDER` / `EXPRESSION_FORMAT`）
- ModTap は `正規名_T(キー)`（`LGUI_T(Lang2)`）、正規名がなければ `MT(MOD_..., キー)`
- 不変条件 `parse(format(k)) == k` は全 16bit 値で spec が検査する（`spec/mapping/keycode_notation_spec.rb`）

## マクロ・タップダンスの参照

キーの割り当てからマクロ・タップダンスを指す書き方。利用者向けの説明は [README.ja.md](../README.ja.md) の「マクロ・タップダンスの参照」。

| 書き方 | マクロ | タップダンス | 値 |
|---|---|---|---|
| 名前 | `Macro('Bracket Pair')` | `TapDance('Tab Escape')` | `Domain::Keycode::MacroCall(index)` / `TapDanceCall(index)` |
| 番号 | `Macro(0)` | `TapDance(2)` | 同上 |
| QMK 形式 | `M0` | `TD(2)` | 同上 |

- 3 つの書き方は解析の時点で同じ値（番号）になる。名前は値に残らない
- `Combo(...)` は .vil のキーに割り当てられないので `UnknownKeycode`（旧実装は受け付けていたが値にできなかった）
- マクロの `sequence` の中では名前参照を使わない（旧実装と同じ）

### 流れ

1. `Storage::ConfigLoader` が macros/ と tap_dance/ を先に読み、`name` → `index` の `Mapping::References` を作る
2. `KeycodeNotation#parse(text, references:)` が `Macro('名前')` を番号にする。見つからなければ
   「マクロ「名前」が見つかりません」の UnknownKeycode（構造検証のエラー）
3. 番号・QMK 形式の参照先がない場合は `Profile#diagnostics` が「マクロ M40 が定義されていません」を返す
4. decompile: `Profile#references`（名前 → 番号）から References を作り、`Formatter` が `Macro('名前')` / `TapDance('名前')` を書く。
   名前のない番号は `M2` / `TD(4)`。`'` を含む名前は `"..."` で囲む

## 名前付きショートカット（`Shortcut('名前')`）

nape_pro-layout の `Shortcut('名前')` に倣ったもの。利用者向けの説明は [README.ja.md](../README.ja.md) の「名前付きショートカット」。

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
- nape_pro-layout との違い: cornix の Domain はキーコードを `Assignment` で包まない（注記は別の `notes` に持つ）ので、
  どの位置が `Shortcut(...)` で書かれていたかは Profile に残らない。書き出すときは値の一致だけで決める
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
- 1 つのキーコードで表せないもの（連続して押す・押したまま操作するもの）は `ラベル: { macro: [...] }` で書く（macros/ の sequence と同じ形で、
  action は tap / down / up だけ）。`{ macro: ... }` だけの Hash はカテゴリではなく定義として読む。#13 で見送った 6 件のうち 5 件を入れた
  （Unity:シーン:フライスルー の「マウスボタン 2 を押したまま W」は、RMK のマクロでマウスボタンの Down / Up が効くか実機で確かめてから）
- 複数の手順の定義は `Shortcut('名前')` では使えない（スロットを自動で割り当てると数の管理が利用者から見えなくなるため、#14 で見送った）。
  使われたら References の `preset_macros` を見て「macros/ に preset: で書いてください」と案内する

### プリセットのマクロ（macros/ の `preset:`）

- macros/ のファイルに `sequence` の代わりに `preset: 'アプリ:カテゴリ:ラベル'` を書くと、同梱の定義の手順のマクロになる（#14）。
  番号は利用者が `index` で決める。`sequence` と `preset` はどちらか一方
- 複数の手順の定義はその手順、1 シーケンスの定義は押して離す手順（修飾キー付きは Down 修飾キー → Tap キー → Up 修飾キーを逆順。
  右側の修飾キーは右側のまま）。`Mapping::ShortcutCatalog#preset` が作る
- `name` を省くと preset の名前（`Schema::Header` も同じ規則で References の名前を作るので `Macro('アプリ:カテゴリ:ラベル')` で参照できる）
- `Domain::Macro#preset` に名前を持ち、`Schema::MacroFile.write` は sequence の代わりに preset を書く。デバイスにはないので、
  decompile では preset は戻らず、ふつうの sequence になる。逆引きはしない（#13 と同じ方針。同じ手順の別のショートカットに化けるため）
- preset は同梱の定義だけを引く（shortcuts.yaml で同じ名前を上書きしても効かない。shortcuts.yaml の値はマクロの手順にならないこともあるため）
- 知らない名前は「プリセット「名前」は同梱のショートカットにありません（候補: ...）」（DidYouMean で 3 件まで）
- `ShortcutCatalog` は `Application::Environment#shortcut_catalog` から `ConfigRepository` に渡す。マクロの keys など References::NONE の場面では
  `Shortcut(...)` は「ここでは使えません」（`References#shortcuts_available?`）
- データは cornixhub のページの JS から取り出したもの（2026-10-19）。英語版はなく、ラベルは日本語。アプリ名はサイトの英語表記
  （note は「メモ」と訳されているので note のまま）、訳のないカテゴリ window は「ウィンドウ」にした

## 割り当ての注記（`{ key:, note: }`）

レイヤーのキー・エンコーダの操作、タップダンスの動作、コンボの `output_key` には `{ key: <表記>, note: <注記> }` の形でも書ける。
注記は設定ファイルにだけあり、compile の結果は変わらない。持ち方は [domain-model.md](domain-model.md) の「注記」を参照。

## rename での書き換え

`Storage::ConfigEditor#replace_references(function, old_name, new_name)` が config/ のすべての YAML の
`Macro('旧名')` / `Macro("旧名")` をテキストで置き換える（関数の引数やコンボの出力の中にあっても書き換わる。ほかの書き方は保つ）。
番号・QMK 形式の参照は名前に依存しないので触らない。置き換え後に compile 結果が変わらないことを `Application::RenameFiles` が確かめる
（詳細は [rename.md](rename.md)）。

## テスト

- `spec/mapping/keycode_notation_spec.rb`（表記ごとの値、エラーメッセージ、往復、参照・Shortcut の解析・書き出し）
- `spec/mapping/keycode_notation_config_spec.rb`（test_config / authors_config の全キーコードが旧コードと同じ値。
  `spec/fixtures/expected/config_keycodes.yaml`）
- `spec/domain/shortcut_library_spec.rb`, `spec/storage/config_repository_spec.rb`（shortcuts.yaml の読み書き・同梱のショートカット）
- `spec/mapping/shortcut_catalog_spec.rb`（data/shortcuts/ の読み込みと検査）
- `spec/domain/profile_diagnostics_spec.rb`（参照先の存在）
- `spec/storage/config_editor_spec.rb`, `spec/application/rename_spec.rb`（書き換え）
