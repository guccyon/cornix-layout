# rename（設定ファイルの名前付け）

既定の名前（`Macro N` / `TapDance N` / `Combo N` / `Layer N`）の設定ファイルに、Claude の提案から名前とファイル名を付ける。
利用者向けの説明は [README.ja.md](../../README.ja.md) の「設定ファイルに名前を付ける」。

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
  1. 事前検証（ファイルがある、番号の接頭辞が同じ、行き先が空いている、YAML が読める）
  2. 変更前の設定を `ProfileMapper#to_image` まで通した DeviceImage を覚える
  3. `config.backup_<YYYYmmdd_HHMMSS>/` にバックアップ（`.backup_manifest.yaml` 付き）
  4. 1 件ずつ name / description の行を書き換え、ファイル名を変え、マクロ・タップダンスの name が変わったら
     `ConfigEditor#replace_references` で全 YAML の `Macro('旧名')` / `TapDance('旧名')` をテキスト置換
  5. 変更後の DeviceImage が変更前と同じことを確かめる（16bit 値の比較）
  6. どこかで失敗したらバックアップから元に戻す（バックアップは残す）
- `Storage::ConfigEditor`: ファイル操作・行単位の書き換え（コメントや書式を保つ）・バックアップと復元
- パスは `Environment#root` 基準で解決する

## テスト

`spec/application/rename_spec.rb`, `spec/storage/config_editor_spec.rb`, `spec/end_to_end_spec.rb`（bin/rename_file の実行）
