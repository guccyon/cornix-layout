## 2026-03-09: YAML Quote Minimization & Position Map Validation

### 新機能

1. **YAMLクォート最適化** (`lib/cornix/decompiler.rb`)
   - `minimize_quotes()` メソッド追加 - YAML仕様上不要なダブルクォートを自動削除
   - YAMLの特殊文字・予約語・数値を正確に検出してクォート保持
   - 生成されるYAMLファイルがより読みやすく、簡潔に

2. **Position Map シンボル検証強化** (`lib/cornix/validator.rb`)
   - `valid_position_symbol?()` メソッド追加
   - シンボル名がYAMLクォート不要な文字のみで構成されているかチェック
   - 許可: 英数字、アンダースコア、ハイフン（`[a-zA-Z0-9_-]+`）
   - 不許可: `'`, `;`, 単独の `-` 等のYAML特殊文字

3. **Modifier式のクォート柔軟性** (`lib/cornix/keycode_parser.rb`)
   - `Cmd + ]` と `Cmd + "]"` の両方をサポート
   - 正規表現パターン拡張: `[^\s+]` を追加してクォート無し単一文字を許可
   - `parse_modifier_expression()` のクォート除去ロジック改善

### テスト追加

- KeycodeParser: +2テスト（クォート付き・クォート無し両サポート）
- Validator: +2テスト（position_mapシンボル文字検証）
- **総テスト数**: 489 → 493テスト（全成功）

### ドキュメント更新

- CLAUDE.md: Modifier Expression System セクション更新
  - クォート柔軟性の説明追加
  - パターンマッチングの例更新
- CLAUDE.md: Position Map 検証セクション更新
  - シンボル文字検証の説明追加
- CLAUDE.md: Decompiler セクション更新
  - minimize_quotes() の説明追加
- CLAUDE.md: テスト数更新（479 → 493）

### 動作確認

- Round-trip check: ✓ FILES ARE IDENTICAL
- 全テストスイート: 493 examples, 0 failures
- Modifier式のコンパイル検証: `Cmd + ]` → `LGUI(KC_RBRACKET)` 正常
- Position Map 検証: 不正なシンボル `'` を正しく検出

### 影響範囲

- **互換性**: 完全後方互換（既存の設定ファイルに影響なし）
- **Decompile結果**: より読みやすいYAML生成（クォート削減）
- **Validation**: より厳格なposition_map検証（潜在的なYAMLエラーを事前検出）
