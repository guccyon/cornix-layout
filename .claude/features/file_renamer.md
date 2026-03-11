# FileRenamer の使い方

**基本的な使い方**:

```bash
# 単一ファイルのリネーム（dry-run）
ruby bin/rename_file \
  --old-path config/macros/03_macro.yml \
  --new-basename 03_end_of_line.yml \
  --name "End of Line" \
  --description "Jump to end of line" \
  --dry-run

# 実行（バックアップ自動作成）
ruby bin/rename_file \
  --old-path config/macros/03_macro.yml \
  --new-basename 03_end_of_line.yml \
  --name "End of Line"

# バッチリネーム（JSON経由）
ruby bin/rename_file --batch tmp/rename_plans.json

# バッチリネーム＋成功時にバックアップ削除
ruby bin/rename_file --batch tmp/rename_plans.json --cleanup-backup
```

**JSON計画ファイル形式** (`tmp/rename_plans.json`):

```json
[
  {
    "old_path": "config/macros/03_macro.yml",
    "new_basename": "03_end_of_line.yml",
    "content_updates": {
      "name": "End of Line",
      "description": "Jump to end of line with Cmd+Right"
    }
  }
]
```

**推奨ワークフロー（Skill経由）**:

```bash
# LLMによる内容解析とリネーム提案
claude /rename
```

**推奨ワークフロー（cornix rename）**:

```bash
# インタラクティブなリネーム（推奨）
cornix rename

# 実行フロー：
# 1. 現在の設定をコンパイル（ベースライン）
# 2. マクロ/タップダンスを解析してリネーム提案
# 3. 各提案にy/n/editで応答
# 4. リネーム実行（自動バックアップ）
# 5. コンパイル検証（構造比較）
# 6. 一時ファイル削除
```

**重要な機能**:

1. **インデックスプレフィックス保持**: `03_macro.yml` → `03_end_of_line.yml` （`03_`を維持）
2. **事前検証**: ファイル存在、インデックス一致、重複チェック
3. **自動バックアップ**: `config.backup_<timestamp>/` に全体をバックアップ
4. **トランザクション型**: バッチ処理は全成功 or 全ロールバック
5. **コンパイル検証**: リネーム後に `Compiler` で妥当性確認
