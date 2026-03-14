# Validation System

Cornixプロジェクトのバリデーションシステムのドキュメント。

## Overview

Cornixは2層のバリデーションシステムを採用しています：

1. **ファイルシステムレベル検証**（ModelValidator）
   - YAML構文チェック
   - ファイル名検証
   - 一意性チェック（レイヤーインデックス、マクロ/タップダンス/コンボ名）

2. **モデルレベル検証**（Validatableモジュール）
   - Structural validations: フィールド単体検証（依存なし）
   - Semantic validations: コンテキスト検証（依存あり）

## Architecture (Phase 2完了)

### 2層バリデーションアーキテクチャ

```
┌──────────────────────────────────────────┐
│       ModelValidator                     │
│  (ファイルシステムレベル検証)              │
│  - YAML構文                              │
│  - ファイル名                            │
│  - レイヤーインデックス                   │
│  - マクロ/タップダンス/コンボ名一意性      │
│  - モデル検証委譲                        │
└──────────────────────────────────────────┘
                    ↓ delegate
┌──────────────────────────────────────────┐
│       VialConfig.validate!               │
│  (ルート集約モデル検証)                   │
└──────────────────────────────────────────┘
                    ↓ cascade
┌──────────────────────────────────────────┐
│  各モデルの Validatable                   │
│  - Structural validations                │
│  - Semantic validations                  │
│                                          │
│  19モデル全て適用済み ✅                 │
│  - Metadata, Layer, HandMapping, ...     │
└──────────────────────────────────────────┘
```

### Validatableモジュール

**ファイル**: `lib/cornix/models/concerns/validatable.rb` (~260行)

**機能**:
- DSLによる宣言的バリデーション定義
- 2段階検証: structural + semantic
- Custom Validator Arity Detection
- ValidationError統合

**適用モデル**: 全19モデル（Phase 2完了）

**テスト**: `spec/models/concerns/validatable_spec.rb` (34テスト)

### ModelValidator

**ファイル**: `lib/cornix/model_validator.rb` (~400行)

**責務**:
1. ファイルシステムレベル検証
2. モデル検証の委譲（VialConfig.validate!呼び出し）
3. エラー・警告の収集と表示

**テスト**: `spec/model_validator_spec.rb` (27テスト)

### Phase 2.5: Context Pollution Bug修正

**問題**: 親モデルが`:with`キー含むoptionsを子に渡し、子のvalidatorを上書き

**修正**: `options.slice(:keycode_converter, :reference_converter, :position_map, :config_dir)`でコンテキストキーのみ抽出

**影響**: VialConfig, Layer, Collections, HandMapping, ThumbKeys（8ファイル、15箇所）

## Validation Features

### 1. 自動バリデーション

Compileコマンドは自動的にバリデーションを実行します：

```bash
cornix compile
# 🔍 Validating configuration...
# ✓ Validation passed
# 🔨 Compiling...
# ✓ Compilation completed: layout.vil
```

### 2. 明示的バリデーション

```bash
cornix validate
# ✓ All validations passed
```

### 3. 2段階検証

**Structural validations**（依存なし）:
- フィールドの存在チェック
- 型チェック
- フォーマットチェック
- 長さチェック

**Semantic validations**（依存あり）:
- キーコード解決可能性
- 参照整合性（Macro/TapDance/Combo）
- ポジションシンボル存在確認
- 他モデルとの関係チェック

### 4. エラーメッセージ

**ファイルパス付きエラー**（Phase 2.6で実装）:

```bash
✗ Validation failed:
  Error: config/layers/0_base.yaml: name: cannot be blank
  Error: config/layers/1_symbols.yaml: left_hand: thumb_keys: left: keycode 'Macr(...)' cannot be resolved
```

### 5. ValidationError

**クラス**: `Cornix::Models::Concerns::ValidationError`

**機能**:
- 全エラーを配列で保持
- メタ情報（ファイルパス）サポート
- フォーマット済みメッセージ生成

### 6. 自動ロールバック

エラー時は自動的に元の状態に復元（compile/decompile時）

## Validator の使い方

**基本的な使い方**:

```bash
# 設定ファイルを検証
cornix validate

# 成功時
✓ All validations passed

# 失敗時
✗ Validation failed:
  Error: config/layers/0_base.yaml: name: cannot be blank
  Error: config/layers/1_symbols.yaml: Unknown position symbol 'UnknownSymbol'
```

**推奨ワークフロー**:

```bash
# 1. 設定を編集
vim config/layers/0_base.yaml

# 2. 検証
cornix validate

# 3. コンパイル（検証成功後のみ）
cornix compile
```

## 検証項目

### ファイルシステムレベル（ModelValidator）

1. **YAML構文の正当性** (`validate_yaml_syntax`)
   - 全YAMLファイルのパースエラーを検出
   - ユーザーフレンドリーなエラーメッセージ
   - YAMLエラーのあるファイルは以降の検証をスキップ（多重エラー防止）

2. **レイヤーインデックスの妥当性** (`validate_layer_indices`)
   - ファイル名が`N_name.yaml`形式であることを確認
   - インデックス範囲チェック（0-9）
   - 重複インデックス検出

3. **マクロ名の一意性** (`validate_macro_names`)
   - マクロ名が全体で一意であることを確認
   - 重複検出時はファイル名を表示

4. **タップダンス名の一意性** (`validate_tap_dance_names`)
   - タップダンス名が全体で一意であることを確認
   - 重複検出時はファイル名を表示

5. **コンボ名の一意性** (`validate_combo_names`)
   - コンボ名が全体で一意であることを確認
   - 重複検出時はファイル名を表示

### モデルレベル（Validatable）

#### Structural Validations（Phase 2完了）

1. **Metadataモデル**
   - 必須フィールド: `keyboard`, `version`, `uid`, `vial_protocol`, `via_protocol`
   - `vendor_product_id`の形式チェック（`0xXXXX`）
   - `matrix`の型・範囲チェック（`rows`, `cols`は正の整数）

2. **Layerモデル**
   - name必須・空白不可
   - description必須
   - index範囲チェック（0-9）

3. **HandMappingモデル**
   - row0-3配列型チェック
   - thumb_keys必須チェック
   - 各行の長さチェック（row0-2は最大6、row3は最大3）

4. **KeyMappingモデル**
   - symbol必須
   - keycode必須
   - logical_coord型チェック

5. **ThumbKeysモデル**
   - left/middle/right必須
   - 各キーの構造検証

6. **PositionMapモデル** ✨ NEW (Phase 2)
   - シンボル形式検証（`[a-zA-Z0-9_-]+`）
   - スコープ内重複検出
   - 要素数検証（row0-2: 6要素、row3/thumb_keys: 3要素） ✨ NEW (Phase 2.7)
   - 必須キー検証（left_hand, right_hand, encoders） ✨ NEW (Phase 2.7)

7. **Macroモデル** ✨ NEW (Phase 2.7)
   - MacroActionバリューオブジェクト検証
   - 有効なアクション: tap, down, up, delay, beep（QMK仕様準拠）
   - MacroStep構造検証（action, keys, duration）
   - sequence配列検証（Array[MacroStep]）

8. **TapDanceモデル** ✨ NEW (Phase 2.7)
   - キーコードフィールド検証（on_tap, on_hold, on_double_tap, on_tap_hold）
   - tapping_term型検証

9. **Comboモデル** ✨ NEW (Phase 2.7)
   - trigger_keys配列検証
   - output_key検証

#### Semantic Validations（Phase 2.7完了）

1. **KeyMappingモデル**
   - キーコード解決可能性検証（KeycodeConverter経由）
   - 参照検証（Macro/TapDance/Combo）
   - ポジションシンボル検証（position_map参照）

2. **HandMapping/ThumbKeys**
   - 各キーマッピングのセマンティック検証委譲

3. **VialConfig**
   - 全サブモデルのセマンティック検証統括

4. **Collections（Layer/Macro/TapDance/Combo）**
   - コレクション要素の検証委譲

5. **MacroStepモデル** ✨ NEW (Phase 2.7)
   - キーコード配列の解決可能性検証（keys配列）
   - KeycodeParser → KeycodeConverter パイプライン

6. **TapDanceモデル** ✨ NEW (Phase 2.7)
   - 各キーコードフィールドの解決可能性検証
   - on_tap, on_hold, on_double_tap, on_tap_hold

7. **Comboモデル** ✨ NEW (Phase 2.7)
   - trigger_keys配列の解決可能性検証
   - output_keyの解決可能性検証

### 検証の実行モード（Phase 2で実装）

#### Strict Mode（デフォルト、compile/decompile用）

```ruby
vial_config.validate!(context, mode: :strict)
# → 最初のエラーで即座に例外を投げる（fail-fast）
```

**用途**: compile/decompile時に即座にエラー停止

#### Collect Mode（validate コマンド用）

```ruby
errors = vial_config.validate!(context, mode: :collect)
# → 全エラーを配列で返す（例外なし）
```

**用途**: validateコマンドで全エラーを一度に表示

## Testing

### テスト構造

```
spec/
├── model_validator_spec.rb (27テスト)
│   └─ ファイルシステム検証 + 委譲テスト
├── models/
│   ├── concerns/
│   │   └── validatable_spec.rb (34テスト)
│   ├── metadata_spec.rb (23テスト)
│   ├── layer_spec.rb (~40テスト)
│   ├── layer/
│   │   ├── hand_mapping_spec.rb (~30テスト)
│   │   ├── key_mapping_spec.rb (~25テスト)
│   │   └── thumb_keys_spec.rb (~20テスト)
│   └── ... (他14モデル)
└── integration/
    ├── compiler_integration_spec.rb
    └── decompiler_integration_spec.rb
```

### テスト結果（Phase 2.7完了時点）

```
862 examples, 0 failures, 5 pending
Finished in 1.05 seconds
```

**Phase 2 → Phase 2.7 テスト数推移**:
- Phase 2完了時: 837 examples
- Phase 2.7完了時: 862 examples (+25)

## Implementation History

### Phase 2.7完了（2026-03-12）: バリデーション強化

Phase 2で実装したValidatableモジュールを活用し、7段階のバリデーション強化を実施。

#### Phase 1: KeycodeConverter強化
- `resolve()`が無効なキーコードに対して`nil`を返す
- バリデーションで扱いやすいエラーハンドリング

#### Phase 2: Macro Sequenceサブモデル化
- **MacroAction**バリューオブジェクト: QMK準拠5種類のアクション
- **MacroStep**モデル: 構造+意味検証
- **Context Pollution Bug修正**: コンテキストキーのみ抽出

**QMKアクション仕様**:
- `tap`: キーをタップ
- `down`: キーを押す
- `up`: キーを離す
- `delay`: 遅延（ミリ秒）
- `beep`: ビープ音

#### Phase 3: TapDance/Comboキーコード検証
- TapDance: `on_tap`, `on_hold`, `on_double_tap`, `on_tap_hold`の意味検証
- Combo: `trigger_keys`, `output_key`の意味検証
- キーコード解決可能性を厳密にチェック

#### Phase 4: PositionMap構造検証強化
- 必須キー検証: `left_hand`, `right_hand`, `encoders`
- 要素数検証: row0-2 (6要素), row3/thumb_keys (3要素)
- シンボル名形式検証: `/^[a-zA-Z0-9_-]+$/`
- 重複検証: シンボルの一意性
- 防御的実装: `build_path_map`のnil安全

#### Phase 5: KeyMapping検証強化
- position_map参照の完全一致検証

#### Phase 6: エラーメッセージ改善
- ValidationErrorフォーマット: セミコロン → 箇条書き
- ファイルパス表示: `Error in config/file.yaml:\n  - error1\n  - error2`

#### Phase 7: 統合テスト修正
- VialWriter/YamlWriter: MacroStepフォーマット対応
- Compiler/Decompiler: テストフィクスチャ修正
- 無効な`text`アクション削除（QMK仕様準拠）

**テスト結果**:
```
862 examples, 0 failures, 5 pending
Finished in 1.05 seconds
```

**主な改善点**:
1. QMK仕様準拠: Macroアクション
2. 厳密なキーコード検証
3. PositionMap構造検証
4. エラーメッセージ可読性向上
5. データ整合性保証

### Phase 2完了（2026-03-11）

- ✅ Validatableモジュール実装（260行、34テスト）
- ✅ 全19モデルにValidatable適用
- ✅ Context Pollution Bug修正（8ファイル、15箇所）
- ✅ ModelValidator リファクタリング（90+ テスト → 27テスト）
- ✅ vendor_product_id形式統一
- ✅ Round-trip test成功
- ✅ 全837テスト合格

詳細: [Refactor Progress](../implementation/refactor_progress.md)

## References

- [Architecture Overview](../architecture/README.md)
- [Current Architecture](../architecture/architecture.md)
- [Refactor Progress](../implementation/refactor_progress.md)
- [Model Validation Memory](../memories/model_validation.md)
