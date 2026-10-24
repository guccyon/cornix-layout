# rename（設定ファイルの名前付け）

既定の名前（`Macro N` / `TapDance N` / `Combo N` / `Layer N`）の設定ファイルに、Claude の提案から名前とファイル名を付ける。
利用者向けの説明は [README.ja.md](../README.ja.md) の「名前を付ける（`rename`）」。

## 入口

- `cornix rename`（`Interface::Cli::Commands::Rename`）: 検証 → 提案 → 1 件ずつ Y/n/e(dit) → 実行 → 後片付け
- `bin/rename_file`（`Application::RenameFiles` の薄い入口。結果を JSON で表示）

```bash
ruby bin/rename_file --old-path config/macros/03_macro.yaml --new-basename 03_end_of_line.yaml --name "End of Line" [--dry-run]
ruby bin/rename_file --batch tmp/rename_plans.json [--dry-run] [--cleanup-backup] [--config-dir DIR]
```

計画（`Application::RenamePlan`）の JSON:

```json
[{ "old_path": "config/macros/03_macro.yaml", "new_basename": "03_end_of_line.yaml",
   "content_updates": { "name": "End of Line", "description": "..." },
   "reasoning": "...", "confidence": "high" }]
```

## 部品

- `Application::SuggestRenames`: `RenamePrompt` を `ClaudeCli`（`claude` コマンド）に渡し、出力から JSON を取り出して
  `tmp/rename_plans.json` に保存する。出力は `tmp/claude_output.log`。Claude CLI は `Environment#claude` で差し替えられる
- `Application::RenameFiles#check(plan)` / `#call(plans, verify: true)` → `RenameOutcome`
  1. 事前検証（ファイルがある、行き先が空いている、YAML が読める）。番号は `index:` だけで決まるので、ファイル名の番号の接頭辞は
     変えても足しても外してもよい（issue #85 で「番号の接頭辞が同じ」の検査をやめた。Claude への依頼の文は今どおり接頭辞を保つよう頼む）
  2. 変更前の設定を `ProfileMapper#to_image` まで通した DeviceImage を覚える
  3. `config.backup_<YYYYmmdd_HHMMSS>/` にバックアップ（`.backup_manifest.yaml` 付き）
  4. 1 件ずつ name / description の行を書き換え、ファイル名を変え、マクロ・タップダンスの name が変わったら
     `ConfigEditor#replace_references` で全 YAML の `Macro('旧名')` / `TapDance('旧名')` をテキスト置換
  5. 変更後の DeviceImage が変更前と同じことを確かめる（16bit 値の比較）
  6. どこかで失敗したらバックアップから元に戻す（バックアップは残す）
- `Storage::ConfigEditor`: ファイル操作・行単位の書き換え（コメントや書式を保つ）・バックアップと復元
  - 参照の置き換えは、ファイルを書かずにテキストの上でも呼べる（VS Code 拡張 v0.2 で分けた）。
    `ConfigEditor.reference_pattern(function, name)` は `function('name')` の参照に合う正規表現（引用符は `'` `"` と YAML の中で重ねた `''` `\"`。1 番目のグループが引用符）、
    `ConfigEditor.replace_references_in(text, function, old_name, new_name)` はテキストの中の参照を置き換えた文字列を返す（名前に同じ引用符があれば、もう一方の引用符で囲む）。
    どちらも `Macro` / `TapDance` に加えて `Shortcut` を扱える。ファイルに書く `#replace_references` はこれを呼ぶだけで、振る舞いは変わらない（`Macro` / `TapDance` だけ）
- `Application::Editor::ItemEdits`（`cornix serve` の `profile/planItemEdit`。[protocol.md](vscode-extension/protocol.md) の 12.5）: VS Code 拡張の項目の名前の変更。
  `RenameFiles` と同じ考え方（参照をテキストで置き換え、前後の compile の結果を 16bit 値で照合する）だが、ファイルは書かずに書き換え（範囲と新しい文字）として返す
  - 設定ディレクトリを読み、操作をメモリの上の `ItemEdits::Changeset` に積む。`name` の行を書き換え、全設定ファイルの `Macro` / `TapDance` / `Shortcut('旧名')` を
    `reference_pattern` で探して参照 1 つずつの範囲を `replace_references_in` で置き換え、ファイル名の slug を変える（`renameTo`。番号の接頭辞と拡張子は保つ。接頭辞のないファイルには付けない）
  - 当てたあとの中身を compile して前の 16bit 値と違えば `ItemEdits::Unverified`（`-32061` の reason `"verify"`）で、何も返さない。
    レイヤーとコンボは名前で参照されないので `name` の行とファイル名だけ、位置の名前の変更（`RenamePosition`）は `position_map.yaml` と全レイヤー（未使用のレイヤーのファイルも）の `mapping` のキーを書き換える
  - 削除（`ItemEdits::Delete`）は参照を書き換えず、壊れる参照の場所を返す（`reference_pattern` で表記を探すほか、16bit 値で番号の参照も数える）
- パスは `Environment#root` 基準で解決する

## テスト

`spec/application/rename_spec.rb`, `spec/storage/config_editor_spec.rb`, `spec/end_to_end_spec.rb`（bin/rename_file の実行）。
`ItemEdits` は `spec/application/editor/item_edits_spec.rb`・`spec/application/editor/item_edits/`・`spec/fixtures/protocol/profile_plan_item_edit/`
