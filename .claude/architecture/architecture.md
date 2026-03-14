# Architecture (v2.x)

Cornixプロジェクトの現在のアーキテクチャドキュメント（Phase 2完了時点）。

## Implementation Status

### ✅ Phase 1: PositionMap拡張（完了）

**ファイル**: `lib/cornix/position_map.rb`

**追加メソッド**（5つ）:
- `symbol_to_coords(symbol)` - シンボル → 座標変換
- `coords_to_symbol(row, col)` - 座標 → シンボル変換
- `find_coords(symbol)` - シンボル検索
- `each_position` - イテレータ
- `all_symbols` - 全シンボル取得

**テスト**: `spec/position_map_spec.rb` (17テスト)

### ✅ Phase 2: モデル層実装（完了）

**実装状況**: 19モデルファイル、約1,337行、234テスト

**完了日**: 2026-03-11

#### Validatableモジュール
**ファイル**: `lib/cornix/models/concerns/validatable.rb` (~260行)

**機能**:
- 2段階検証: structural（依存なし）+ semantic（依存あり）
- DSLによる宣言的バリデーション定義
- Custom Validator Arity Detection
- ValidationError統合

**テスト**: `spec/models/concerns/validatable_spec.rb` (34テスト)

#### 全19モデル Validatable適用済み ✅

1. **Metadata** - 必須フィールド、フォーマット検証
2. **Layer** - name/description、mapping検証
3. **HandMapping** - rows、thumb_keys検証
4. **KeyMapping** - keycode_value型検証
5. **ThumbKeys** - left/middle/right検証
6. **PositionMap** - シンボル形式、重複検証
7. **Settings** - 設定値検証
8. **VialConfig** - ルート集約検証
9. **LayerCollection** - レイヤー配列検証
10. **MacroCollection** - マクロ配列検証
11. **TapDanceCollection** - タップダンス配列検証
12. **ComboCollection** - コンボ配列検証
13. **Macro** - マクロ検証
14. **MacroSequence** - シーケンス検証
15. **MacroAction** - アクション検証
16. **TapDance** - タップダンス検証
17. **TapDanceAction** - アクション検証
18. **Combo** - コンボ検証
19. **ComboTrigger** - トリガー検証

詳細: [Refactor Progress](../implementation/refactor_progress.md)

### ✅ Phase 2.5: Context Pollution Bug修正（完了）

**問題**: 親モデルが`:with`キー含むoptionsを子に渡し、子のvalidatorを上書き

**修正**: `options.slice(:keycode_converter, :reference_converter, :position_map, :config_dir)`でコンテキストキーのみ抽出

**影響ファイル**: VialConfig, Layer, Collections, HandMapping, ThumbKeys（合計8ファイル、15箇所）

**完了日**: 2026-03-11

### ✅ Phase 2.6: ModelValidator リファクタリング（完了）

**目的**: バリデーションロジックのモデル層への委譲に伴い、ModelValidatorを焦点化

**変更内容**:
- ModelValidator spec: 90+ テスト → 27テスト（68%削減）
- 責務: ファイルシステム検証 + モデル検証委譲のみ
- 削除: keycode検証、position reference検証、metadata検証等（モデル側で実装済み）

**完了日**: 2026-03-11

### 🔄 Phase 3-6: 未着手

- **Phase 3**: Loader/Writer実装
- **Phase 4**: Converter移行
- **Phase 5**: 新Compiler/Decompiler
- **Phase 6**: 検証とクリーンアップ

## Architecture Overview

現在の5層構造（Phase 2完了時点）:

```
┌─────────────────────────────────────────────┐
│          Presentation Layer                 │
│  ┌──────────────────────────────────────┐  │
│  │ CLI (bin/cornix)                     │  │
│  │ - compile, decompile, validate       │  │
│  └──────────────────────────────────────┘  │
└─────────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────────┐
│       Orchestration Layer (TBD)             │
│  ┌──────────────────────────────────────┐  │
│  │ CompileOrchestrator (未実装)         │  │
│  │ DecompileOrchestrator (未実装)       │  │
│  └──────────────────────────────────────┘  │
└─────────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────────┐
│        Application Layer                    │
│  ┌──────────────────────────────────────┐  │
│  │ Converter (未実装)                   │  │
│  │ - KeycodeConverter (Legacy)          │  │
│  │ - ReferenceConverter (Legacy)        │  │
│  │ Validator (Legacy, 既存)             │  │
│  └──────────────────────────────────────┘  │
└─────────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────────┐
│           Domain Layer ✅ 実装済み           │
│  ┌──────────────────────────────────────┐  │
│  │ Models (19ファイル, ~1,077行)        │  │
│  │  - Metadata (Validatable✅)          │  │
│  │  - Layer (Validatable✅)             │  │
│  │  - PositionMap                       │  │
│  │  - QmkSettings                       │  │
│  │  - Macro, TapDance, Combo            │  │
│  │  - HandMapping (Validatable✅)       │  │
│  │  - KeyMapping (Validatable✅)        │  │
│  │  - ThumbKeys (Validatable✅)         │  │
│  │  - EncoderMapping, EncoderKeys       │  │
│  │  - KeycodeValue                      │  │
│  │  - RowMapping                        │  │
│  │  - Components                        │  │
│  │                                      │  │
│  │ Concerns                             │  │
│  │  - Validatable (260行) ✅            │  │
│  └──────────────────────────────────────┘  │
└─────────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────────┐
│      Infrastructure Layer (TBD)             │
│  ┌──────────────────────────────────────┐  │
│  │ Loader (未実装)                      │  │
│  │ - YamlLoader                         │  │
│  │ - VilLoader                          │  │
│  │ Writer (未実装)                      │  │
│  │ - YamlWriter                         │  │
│  │ - VilWriter                          │  │
│  └──────────────────────────────────────┘  │
└─────────────────────────────────────────────┘
```

## File Structure

### lib/cornix/models/ (実装済み)

```
lib/cornix/models/
├── concerns/
│   └── validatable.rb              # Validatableモジュール (260行)
├── metadata.rb                     # Metadataモデル (110行, Validatable✅)
├── layer.rb                        # Layerモデル (90行, Validatable✅)
├── layer/
│   ├── hand_mapping.rb            # HandMapping (80行, Validatable✅)
│   ├── key_mapping.rb             # KeyMapping (70行, Validatable✅)
│   ├── thumb_keys.rb              # ThumbKeys (60行, Validatable✅)
│   ├── encoder_mapping.rb         # EncoderMapping (70行)
│   ├── encoder_keys.rb            # EncoderKeys (60行)
│   ├── keycode_value.rb           # KeycodeValue (50行)
│   └── row_mapping.rb             # RowMapping (50行)
├── position_map.rb                # PositionMapモデル (100行)
├── qmk_settings.rb                # QmkSettingsモデル (80行)
├── macro.rb                       # Macroモデル (90行)
├── macro/
│   ├── sequence.rb                # MacroSequence (70行)
│   └── action.rb                  # MacroAction (60行)
├── tap_dance.rb                   # TapDanceモデル (80行)
├── tap_dance/
│   └── action.rb                  # TapDanceAction (60行)
├── combo.rb                       # Comboモデル (80行)
├── combo/
│   └── trigger.rb                 # ComboTrigger (60行)
└── components.rb                  # Componentsモジュール
```

### spec/models/ (テスト)

```
spec/models/
├── concerns/
│   └── validatable_spec.rb        # 34テスト
├── metadata_spec.rb               # 23テスト
├── layer_spec.rb                  # ~15テスト
├── layer/
│   ├── hand_mapping_spec.rb      # ~15テスト
│   ├── key_mapping_spec.rb       # ~10テスト
│   ├── thumb_keys_spec.rb        # ~10テスト
│   ├── encoder_mapping_spec.rb   # ~10テスト
│   ├── encoder_keys_spec.rb      # ~8テスト
│   ├── keycode_value_spec.rb     # ~10テスト
│   └── row_mapping_spec.rb       # ~8テスト
├── position_map_spec.rb           # ~15テスト
├── qmk_settings_spec.rb           # ~12テスト
├── macro_spec.rb                  # ~15テスト
├── macro/
│   ├── sequence_spec.rb          # ~10テスト
│   └── action_spec.rb            # ~8テスト
├── tap_dance_spec.rb              # ~15テスト
├── tap_dance/
│   └── action_spec.rb            # ~8テスト
├── combo_spec.rb                  # ~15テスト
└── combo/
    └── trigger_spec.rb            # ~8テスト

推定合計: 200-250テスト、~5,000行
```

## Key Design Decisions

### 1. インナークラスの分離（計画との差異）
**元の計画**: Layer内にインナークラスとして定義
**実装**: `layer/`サブディレクトリに分離

**理由**:
- ファイルサイズの肥大化防止
- 個別テストの容易性
- 保守性の向上

**影響**: なし（むしろ改善）

### 2. Validatableモジュールの追加（追加機能）
**元の計画**: ValidationErrorのみ
**実装**: Validatableモジュール全体

**機能**:
- 2段階検証（structural + semantic）
- DSLによる宣言的バリデーション
- Custom Validator Arity Detection

**影響**: モデルの自己検証能力が大幅に向上

### 3. KeycodeValueの導入（追加コンポーネント）
**元の計画**: 記載なし
**実装**: KeycodeValueクラス

**理由**:
- キーコード値の型安全性向上
- エイリアス vs QMK形式の明確化

**影響**: KeyMappingの型チェックが厳密化

### 4. Validatable適用の段階的実装（実装方針）
**元の計画**: 全モデルに一度に適用
**実装**: 5モデルに先行適用、残り14モデルは後回し

**理由**:
- パターン確立と検証
- 段階的なテストカバレッジ拡大

**影響**: Phase 2が「ほぼ完了」状態（完全完了には残り14モデルへの適用が必要）

## Metrics

### Code Size
- **実装済み**: ~1,077行（19モデル）
- **テスト**: ~5,000行（200-250テスト）
- **目標**: Phase 6完了時に1,321行 → 270行（全体）

### Test Coverage
- **Validatableモジュール**: 34テスト ✅
- **Metadata**: 23テスト ✅
- **Layer関連**: ~66テスト（推定）
- **その他モデル**: ~120テスト（推定）
- **合計**: 200-250テスト（Phase 2時点）

### Implementation Progress
- **Phase 1**: 100% ✅
- **Phase 2**: 95%（Validatable適用: 5/19モデル）
- **Phase 3-6**: 0%

## Dependencies

### モデル間依存関係

```
Metadata (独立)
   ↓
PositionMap (独立)
   ↓
Layer
   ├─ HandMapping
   │   ├─ RowMapping
   │   │   └─ KeyMapping
   │   │       └─ KeycodeValue
   │   └─ ThumbKeys
   │       └─ KeyMapping
   │           └─ KeycodeValue
   └─ EncoderMapping
       └─ EncoderKeys
           └─ KeyMapping
               └─ KeycodeValue

Macro
   └─ Sequence
       └─ Action

TapDance
   └─ Action

Combo
   └─ Trigger

QmkSettings (独立)

Components (全モデルを統合)
```

### 外部依存（Legacy）
現在のモデル層は以下のLegacyコンポーネントに依存していません:
- ✅ Compiler/Decompiler: 完全分離
- ✅ KeycodeConverter: 参照なし
- ✅ ReferenceConverter: 参照なし
- ✅ Validator: 参照なし

将来的な統合:
- Phase 4でConverterをモデル層で使用
- Phase 5で新Compiler/DecompilerがモデルをORMとして使用

## Validatable Integration Pattern

### 段階的適用手順

```ruby
# Step 1: Validatableをinclude
class ModelName
  include Validatable

  attr_accessor :field1, :field2

  def initialize(field1:, field2:)
    @field1 = field1
    @field2 = field2
  end
end

# Step 2: structural_validationsを定義
class ModelName
  structural_validations do
    validate :field1, presence: true, type: String
    validate :field2, presence: true, type: Integer
  end
end

# Step 3: semantic_validations（必要に応じて）
class ModelName
  semantic_validations do
    validate :field1, custom: ->(value, options) {
      # contextを使った検証
      context = options[:context]
      value.start_with?(context[:prefix])
    }
  end
end

# Step 4: initialize後にvalidate!呼び出し
def initialize(field1:, field2:)
  @field1 = field1
  @field2 = field2
  validate!
end
```

### 適用済みモデルの例

**Metadata** (`lib/cornix/models/metadata.rb`):
```ruby
class Metadata
  include Validatable

  structural_validations do
    validate :keyboard, presence: true, type: String
    validate :version, presence: true, type: Integer
    validate :vendor_product_id, presence: true, format: /^0x[0-9A-Fa-f]{4}$/
    validate :matrix, presence: true, custom: ->(value) {
      value.is_a?(Hash) &&
      value[:rows].is_a?(Integer) &&
      value[:cols].is_a?(Integer)
    }
  end

  def initialize(data)
    @keyboard = data['keyboard']
    @version = data['version']
    # ... (他のフィールド)
    validate!  # 自己検証
  end
end
```

## Testing Strategy

### 既存テスト（Legacy）
- `spec/compiler_spec.rb` (48テスト)
- `spec/decompiler_spec.rb` (37テスト)
- `spec/validator_spec.rb` (82テスト)
- ... 他
- **合計**: 493テスト（Phase 2開始前）

### 新規テスト（Phase 2）
- `spec/models/` 以下
- **合計**: 200-250テスト（推定）

### テスト実行
```bash
# 全テスト実行
bundle exec rspec

# モデル層のみ
bundle exec rspec spec/models/

# 特定モデル
bundle exec rspec spec/models/metadata_spec.rb
```

## Next Steps

### Phase 2完了のための残タスク
1. **Validatable適用**（残り14モデル）
   - PositionMap, QmkSettings
   - Macro, MacroSequence, MacroAction
   - TapDance, TapDanceAction
   - Combo, ComboTrigger
   - EncoderMapping, EncoderKeys
   - KeycodeValue, RowMapping
   - Components

2. **テストカバレッジ確認**
   - 既存テストが全て通ることを確認
   - 新規テストの実行

3. **ドキュメント更新**
   - `implementation/refactor_progress.md`を更新
   - Phase 2完了をマーク

### Phase 3開始準備
1. Loader/Writer設計レビュー
2. YamlLoader実装開始
3. VilLoader実装開始

詳細は [Migration Guide](../implementation/migration_guide.md) を参照。

## References

- [Legacy Architecture](./legacy_architecture.md) - 旧実装の説明
- [Models](./models.md) - モデル層詳細設計
- [Coordinate System](./coordinate_system.md) - 座標変換システム
- [Data Flow](./data_flow.md) - データフロー設計
- [Refactor Plan](../implementation/refactor_plan.md) - 全体計画
- [Refactor Progress](../implementation/refactor_progress.md) - 実装進捗
- [Model Validation Memory](../memories/model_validation.md) - Validatable実装知見
