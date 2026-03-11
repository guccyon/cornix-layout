6. **自動ロールバック**: エラー時は自動的に元の状態に復元

### Validator の使い方

**基本的な使い方**:

```bash
# 設定ファイルを検証
ruby bin/validate

# 成功時
✓ All validations passed

# 失敗時
✗ Validation failed:
  Error: Layer 0_base.yaml, symbol 'LT1': Invalid keycode 'InvalidKeycode'
  Error: Layer 1_symbols.yaml: Unknown position symbol 'UnknownSymbol'
```

**推奨ワークフロー**:

```bash
# 1. 設定を編集
vim config/layers/0_base.yaml

# 2. 検証
ruby bin/validate

# 3. コンパイル（検証成功後のみ）
ruby bin/compile
```

**Phase 1 実装済み検証項目**:

1. **YAML構文の正当性** (`validate_yaml_syntax`)
   - 全YAMLファイルのパースエラーを検出
   - ユーザーフレンドリーなエラーメッセージ
   - YAMLエラーのあるファイルは以降の検証をスキップ（多重エラー防止）

2. **メタデータの妥当性** (`validate_metadata`)
   - `metadata.yaml`の存在チェック
   - 必須フィールド: `keyboard`, `version`, `uid`, `vial_protocol`, `via_protocol`
   - `vendor_product_id`の形式チェック（`0xXXXX`）
   - `matrix`の型・範囲チェック（`rows`, `cols`は正の整数）

3. **Position Map の妥当性** (`validate_position_map`)
   - `position_map.yaml`内のシンボルが一意であることを検証
   - 同じシンボルが複数の物理位置に割り当てられている場合はエラー
   - 左手・右手間での重複も検出
   - nil や空文字列は無視
   - **NEW (2026-03-09)**: シンボル名がYAMLクォート不要な文字のみで構成されているかチェック
     - 許可: 英数字、アンダースコア、ハイフン（`[a-zA-Z0-9_-]+`）
     - 不許可: `'`, `;`, 単独の `-` 等のYAML特殊文字

4. **キーコードの妥当性** (`validate_keycodes`)
   - レイヤー内の全キーコードを検証
   - QMKキーコード（`KC_*`）、エイリアス（`Tab`, `Space`）をサポート
   - 関数形式のキーコードも検証（`MO(1)`, `LSFT(A)`, `LT(2, Space)`）
   - 関数引数も再帰的に検証（ネストされた関数にも対応）
   - `KeycodeConverter`を活用してエイリアス解決

5. **Position Map参照の整合性** (`validate_position_references`)
   - レイヤーで使用される全シンボル（`LT1`, `RT1`等）を検証
   - `position_map.yaml`に定義されていないシンボルを検出
   - `position_map.yaml`が存在しない場合は警告（エラーではない）
   - `PositionMap`クラスを活用して全シンボルを抽出

**既存の検証項目**（Phase 0実装済み）:

5. **レイヤーインデックスの妥当性** (`validate_layer_indices`)
6. **マクロ名の一意性** (`validate_macro_names`)
7. **タップダンス名の一意性** (`validate_tap_dance_names`)
8. **コンボ名の一意性** (`validate_combo_names`)
9. **レイヤー内の参照妥当性** (`validate_layer_references`)

**未実装（Phase 2以降の候補）**:

- マクロシーケンス構文の妥当性
- タップダンスアクションの妥当性
- コンボトリガー数の妥当性
- QMK Settings の型・範囲チェック
- エンコーダー設定の妥当性
- Index フィールドの存在チェック
