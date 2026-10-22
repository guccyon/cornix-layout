# 検証

`cornix validate` と `cornix compile`（先に検証する）が使う。利用者向けの説明は [README.ja.md](../README.ja.md) の「設定ファイルの検証」。

## 2 段階

1. **構造検証**（読み込み時、`Storage::ConfigRepository#load` → `ConfigLoader`）
   - YAML: `Storage::YamlFile`（safe_load。YAML エイリアスとキーの重複はエラー）
   - ファイルごとの形式: `Storage::Schema::*File`（必須・未知の項目、型、番号の範囲、マクロの action など）。
     YAML の型の落とし穴は `Schema::Pitfalls` が書き直し方つきで説明する
   - キーコード: `Schema::KeycodeField` → `KeycodeNotation#parse`（参照は References で解決）
   - 値オブジェクトの生成時の `Cornix::InvalidValue`（`Domain::Checks`）
   - 問題は止まらずに `Storage::Problems` に集め、最後に `Storage::InvalidConfig(problems)` を 1 回送出する。
     表示は `ファイル: キーの位置: 内容`（`Storage::Problem#to_s`）
   - 番号は `index:` だけで決まる。ファイル名の先頭の番号と `index:` の一致は検査しない（番号を入れ替えてファイル名はそのまま、を許す）
   - 未使用のファイル（`index:` のないか値が空のもの。[domain-model.md](domain-model.md) の 9）も同じ形式で検査するが、
     問題は `Storage::UnusedFile#problems` に分けて集め、`InvalidConfig` にしない（`InvalidConfig#unused` にも持たせる）。
     YAML として読めない・マッピングでないファイルは未使用か判定できないので、今までどおり error
2. **意味検証**（`Profile#diagnostics(env.capabilities)` → `Domain::ProfileDiagnostics`。`Application::Environment#capabilities` は
   `Capabilities::CORNIX` に `KeycodeCatalog#unsupported_keycodes` を足したもの）
   - 件数の上限（レイヤー 10、マクロ・タップダンス・コンボ 32、コンボのトリガー 4）
   - 番号・名前の重複、参照先（M(n) / TD(n)）の存在、レイヤー番号の範囲
   - 番号の抜けは 4 種類とも許す（compile が空のデータで埋める。#83 の実機の確認で番号はずれない）
   - 未使用のファイルは対象外（`Profile` に入らない）
   - 警告: レイヤー 0（ベース）がない、定義されていないレイヤーを指す MO(n) など、
     Cornix が対応していないとみられる特殊キー（data/unsupported_keycodes.yaml。QK_REPEAT_KEY、USER08 以降など）、
     押せないコンボ（下の「押せないコンボ」）
   - `Domain::Diagnostic(severity, path, message)` の path（`layers[0].left_hand.row0.tab` の形）は
     `Storage::DiagnosticLocator` がファイル上の位置に直す

`Application::Validate` が両方をまとめて `ValidationReport(diagnostics:, profile:, unused:)` を返す（`Domain::Diagnostic` の一覧で、path はファイル上の位置。構造検証の問題は error、
未使用のファイルの構造の問題は warning にし、message の末尾に「（未使用のファイルなので compile に含めません）」を付ける）。
`#errors` / `#warnings` は表示用の「ファイル: キーの位置: 内容」の文字列、`#unused_files` は未使用のファイルの相対パス、
`#to_h` は `--json` と MCP 用の `{ ok, diagnostics, unused: [{ kind, file, name }] }`。
config/ がなければ `Application::ConfigNotFound`。表示は `Interface::Cli::ConfigMessages#print_report`
（`✓ All validations passed` / `✗ Validation failed:` + `  Error: ...`、未使用のファイルがあれば最後に `ℹ  Unused files (no index, not compiled): N` と一覧）。警告だけなら compile は続行する。
拡張（`cornix serve`）の問題の一覧も同じで、未使用のファイルの構造の問題は `source: "structure"` の warning（`Application::Editor::Diagnostics`。プロファイルは開ける）。

## 主なメッセージ

```
Error: layers/1_layer.yaml: mapping.left_hand.row0.tab: キーコード「Spce」を解釈できません: 「Spce」は不明なキーコードです
Error: layers/1_layer.yaml: mapping.left_hand.row1.capz: position_map の left_hand.row1 にないキーです（使えるキー: ...）
Error: layers/2_layer.yaml: index: レイヤーの番号が重複しています: 2
Error: macros/01_macro.yaml: name: マクロの名前が重複しています: Macro 0
Error: combos/00_combo.yaml: output_key: キーコード「Macro('Spare')」を解釈できません: マクロ「Spare」は未使用です（ファイルに index がありません）
Warning: macros/spare.yaml: sequence[0].keys[0]: キーコード「Nope」を解釈できません: 「Nope」は不明なキーコードです（未使用のファイルなので compile に含めません）
Error: layers/1_layer.yaml: mapping.left_hand.row0.T: マクロ M40 が定義されていません
Error: layers/: レイヤーは 10 枚までです: 11 枚
Warning: combos/03_combo.yaml: trigger_keys: 押せないコンボです: トリガーのキーがすべてそろうレイヤーがありません（KC_TRNS の位置はレイヤー 0 の値で見ます）
```

## 押せないコンボ

コンボのトリガーはキーの位置ではなくキーコードなので、トリガーのキーがどのレイヤーでも同時にそろわないと、そのコンボは押せない。
`Domain::ComboReachability` が判定し、意味検証の警告（path は `combos[i].trigger_keys`）と、エディタの snapshot のコンボの
`reachable`（[protocol.md](vscode-extension/protocol.md) の 13.2）の両方がこれを使う。

- レイヤーごとに、そのレイヤーで押せるキーコードを集める: 位置の割り当てと、エンコーダのプッシュ（マトリクスのキー）。
  回転（ccw / cw）は数えない。割り当てのない位置は KC_NO なので数えない
- `KC_TRNS` の位置は、レイヤー 0（番号 0 のレイヤー）の同じ位置の値で見る（レイヤーの重なりは見ない）
- どれかのレイヤーに、トリガーのキー（`KC_NO` を除く）がすべて入っていれば押せる。キーコードは値そのもので比べる
  （`LT1(Space)` の位置では `Space` のトリガーはそろわない）
- トリガーが `KC_NO` だけのコンボ（エディタで作ったばかりのもの）は押せる扱いで、警告しない

## 新しい項目を足すとき

- ファイルの形式は `Storage::Schema` に、値の制約は値オブジェクトの `initialize`（`InvalidValue`）に、
  ファイルをまたぐ整合性は `ProfileDiagnostics` に書く
- キーコードは必ず `KeycodeField` / `KeycodeNotation#parse` を通す（検証と compile が同じ値を使う。旧実装は別経路で不一致があった）

## テスト

`spec/storage/config_repository_spec.rb`, `spec/storage/diagnostic_locator_spec.rb`,
`spec/domain/profile_diagnostics_spec.rb`, `spec/application/config_use_cases_spec.rb`, `spec/interface/cli/config_commands_spec.rb`
