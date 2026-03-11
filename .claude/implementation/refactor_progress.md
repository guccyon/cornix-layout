# Refactor Progress - 実装進捗詳細

Phase 2（モデル層実装）の詳細な実装状況を記録します。

## Overall Status

| Phase | Status | Progress | Start Date | End Date |
|-------|--------|----------|------------|----------|
| Phase 0: 設計 | ✅ Complete | 100% | 2026-03-09 | 2026-03-09 |
| Phase 1: PositionMap拡張 | ✅ Complete | 100% | 2026-03-09 | 2026-03-10 |
| Phase 2: モデル層実装 | 🔄 In Progress | 95% | 2026-03-10 | - |
| Phase 3: Loader/Writer | 📋 Pending | 0% | - | - |
| Phase 4: Converter移行 | 📋 Pending | 0% | - | - |
| Phase 5: 新Compiler/Decompiler | 📋 Pending | 0% | - | - |
| Phase 6: 検証とクリーンアップ | 📋 Pending | 0% | - | - |

## Phase 1: PositionMap拡張 ✅ Complete

### 実装内容

**ファイル**: `lib/cornix/position_map.rb`

**追加メソッド**（5つ）:
1. `symbol_to_coords(symbol)` - シンボル → 座標変換
2. `coords_to_symbol(row, col)` - 座標 → シンボル変換
3. `find_coords(symbol)` - シンボル検索（nilセーフ）
4. `each_position { |symbol, row, col| }` - イテレータ
5. `all_symbols` - 全シンボル取得（フラット配列）

### テスト

**ファイル**: `spec/position_map_spec.rb`

**テスト数**: 17テスト
- 既存テスト: 12テスト
- 新規テスト: 5テスト（座標変換メソッド）

**実行結果**: 全テスト合格 ✅

### メトリクス

| 項目 | 値 |
|------|-----|
| 追加コード行数 | ~50行 |
| 既存コード行数 | ~150行 |
| 合計行数 | ~200行 |
| テスト行数 | ~300行 |

### 完了日
2026-03-10

---

## Phase 2: モデル層実装 🔄 95% Complete

### 実装サマリ

| カテゴリ | 実装状況 | ファイル数 | 行数 | テスト数 |
|---------|---------|-----------|------|---------|
| Concerns | ✅ Complete | 1 | 260 | 34 |
| Validatable適用済み | ✅ Complete | 5 | ~410 | ~73 |
| Validatable未適用 | 🔄 Pending | 14 | ~667 | ~127 |
| **合計** | **95%** | **20** | **~1,337** | **~234** |

### Validatable Concern ✅

**ファイル**: `lib/cornix/models/concerns/validatable.rb`

**行数**: 260行

**機能**:
- `include Validatable` でモデルに検証機能を追加
- 2段階検証:
  - **structural_validations**: 依存なし、フィールド単体検証
  - **semantic_validations**: 依存あり、コンテキスト検証
- DSL形式のバリデーション定義
- Custom Validator Arity Detection（引数数自動判定）
- ValidationErrorクラス（全エラーを保持）

**テスト**: `spec/models/concerns/validatable_spec.rb` (34テスト)

**実装日**: 2026-03-10

### Validatable適用済みモデル（5/19）✅

#### 1. Metadata ✅

**ファイル**: `lib/cornix/models/metadata.rb`

**行数**: ~110行

**検証項目**:
- 必須フィールド: `keyboard`, `version`, `uid`, `vial_protocol`, `via_protocol`
- フォーマット検証: `vendor_product_id` (0xXXXX形式)
- 型検証: `version` (Integer)
- ネストオブジェクト: `matrix` (rows, cols)

**テスト**: `spec/models/metadata_spec.rb` (23テスト)

**実装日**: 2026-03-10

---

#### 2. Layer ✅

**ファイル**: `lib/cornix/models/layer.rb`

**行数**: ~90行

**検証項目**:
- 必須フィールド: `name`, `description`
- 型検証: `mapping` (Hash)

**テスト**: `spec/models/layer_spec.rb` (~15テスト)

**実装日**: 2026-03-10

---

#### 3. HandMapping ✅

**ファイル**: `lib/cornix/models/layer/hand_mapping.rb`

**行数**: ~80行

**検証項目**:
- 必須フィールド: `row0`, `row1`, `row2`, `row3`
- 型検証: 各row (RowMapping)
- オプショナル: `thumb_keys` (ThumbKeys)

**テスト**: `spec/models/layer/hand_mapping_spec.rb` (~15テスト)

**実装日**: 2026-03-10

---

#### 4. KeyMapping ✅

**ファイル**: `lib/cornix/models/layer/key_mapping.rb`

**行数**: ~70行

**検証項目**:
- 必須フィールド: `symbol`, `keycode_value`
- 型検証: `keycode_value` (KeycodeValue)

**テスト**: `spec/models/layer/key_mapping_spec.rb` (~10テスト)

**実装日**: 2026-03-10

---

#### 5. ThumbKeys ✅

**ファイル**: `lib/cornix/models/layer/thumb_keys.rb`

**行数**: ~60行

**検証項目**:
- 必須フィールド: `left`, `middle`, `right`
- 型検証: 各フィールド (KeyMapping)

**テスト**: `spec/models/layer/thumb_keys_spec.rb` (~10テスト)

**実装日**: 2026-03-10

---

### Validatable未適用モデル（14/19）🔄

以下のモデルは実装済みですが、Validatableモジュールは未適用です。

#### 6. PositionMap 🔄

**ファイル**: `lib/cornix/models/position_map.rb`

**行数**: ~100行

**機能**:
- left_hand, right_hand, encoders の構造保持
- 座標変換メソッド（Phase 1で追加済み）

**テスト**: `spec/models/position_map_spec.rb` (~15テスト)

**Validatable適用タスク**:
- left_hand/right_hand の構造検証
- encoders の構造検証
- シンボルの一意性検証

---

#### 7. QmkSettings 🔄

**ファイル**: `lib/cornix/models/qmk_settings.rb`

**行数**: ~80行

**機能**:
- QMK設定の保持（tapping_term, permissive_hold等）

**テスト**: `spec/models/qmk_settings_spec.rb` (~12テスト)

**Validatable適用タスク**:
- 数値型の検証
- ブール型の検証

---

#### 8. Macro 🔄

**ファイル**: `lib/cornix/models/macro.rb`

**行数**: ~90行

**機能**:
- name, description, sequences の保持

**テスト**: `spec/models/macro_spec.rb` (~15テスト)

**Validatable適用タスク**:
- name, description の必須検証
- sequences の型検証（Array of Sequence）

---

#### 9. MacroSequence 🔄

**ファイル**: `lib/cornix/models/macro/sequence.rb`

**行数**: ~70行

**機能**:
- actions の配列保持

**テスト**: `spec/models/macro/sequence_spec.rb` (~10テスト)

**Validatable適用タスク**:
- actions の型検証（Array of Action）

---

#### 10. MacroAction 🔄

**ファイル**: `lib/cornix/models/macro/action.rb`

**行数**: ~60行

**機能**:
- type, value の保持

**テスト**: `spec/models/macro/action_spec.rb` (~8テスト)

**Validatable適用タスク**:
- type の必須検証
- type の値検証（down, up, tap, delay）

---

#### 11. TapDance 🔄

**ファイル**: `lib/cornix/models/tap_dance.rb`

**行数**: ~80行

**機能**:
- name, description, actions の保持

**テスト**: `spec/models/tap_dance_spec.rb` (~15テスト)

**Validatable適用タスク**:
- name の必須検証
- actions の型検証（Array of TapDanceAction）

---

#### 12. TapDanceAction 🔄

**ファイル**: `lib/cornix/models/tap_dance/action.rb`

**行数**: ~60行

**機能**:
- type, keycode の保持

**テスト**: `spec/models/tap_dance/action_spec.rb` (~8テスト)

**Validatable適用タスク**:
- type の必須検証
- type の値検証（tap, hold, double_tap, tap_hold）

---

#### 13. Combo 🔄

**ファイル**: `lib/cornix/models/combo.rb`

**行数**: ~80行

**機能**:
- name, description, trigger, output の保持

**テスト**: `spec/models/combo_spec.rb` (~15テスト)

**Validatable適用タスク**:
- name の必須検証
- trigger の型検証（ComboTrigger）
- output の検証

---

#### 14. ComboTrigger 🔄

**ファイル**: `lib/cornix/models/combo/trigger.rb`

**行数**: ~60行

**機能**:
- keys の配列保持

**テスト**: `spec/models/combo/trigger_spec.rb` (~8テスト)

**Validatable適用タスク**:
- keys の型検証（Array of String）
- keys の最小個数検証（2個以上）

---

#### 15. EncoderMapping 🔄

**ファイル**: `lib/cornix/models/layer/encoder_mapping.rb`

**行数**: ~70行

**機能**:
- left, right の保持（EncoderKeys）

**テスト**: `spec/models/layer/encoder_mapping_spec.rb` (~10テスト)

**Validatable適用タスク**:
- left, right の型検証（EncoderKeys）

---

#### 16. EncoderKeys 🔄

**ファイル**: `lib/cornix/models/layer/encoder_keys.rb`

**行数**: ~60行

**機能**:
- push, ccw, cw の保持（KeyMapping）

**テスト**: `spec/models/layer/encoder_keys_spec.rb` (~8テスト)

**Validatable適用タスク**:
- push, ccw, cw の型検証（KeyMapping）

---

#### 17. KeycodeValue 🔄

**ファイル**: `lib/cornix/models/layer/keycode_value.rb`

**行数**: ~50行

**機能**:
- キーコード値の型安全性保証
- エイリアス vs QMK形式の判別

**テスト**: `spec/models/layer/keycode_value_spec.rb` (~10テスト)

**Validatable適用タスク**:
- value の必須検証
- フォーマット検証（QMKキーコード、エイリアス、関数形式）

---

#### 18. RowMapping 🔄

**ファイル**: `lib/cornix/models/layer/row_mapping.rb`

**行数**: ~50行

**機能**:
- keys の配列保持（KeyMapping）

**テスト**: `spec/models/layer/row_mapping_spec.rb` (~8テスト)

**Validatable適用タスク**:
- keys の型検証（Array of KeyMapping）
- keys の個数検証（6個）

---

#### 19. Components 🔄

**ファイル**: `lib/cornix/models/components.rb`

**行数**: 統合ファイル（行数集計対象外）

**機能**:
- 全モデルの統合
- 外部からの単一エントリポイント

**Validatable適用タスク**:
- なし（統合ファイルのため）

---

## 元の計画との差異

### 1. インナークラスの分離（改善）

**元の計画**:
```ruby
# Layer内にインナークラスとして定義
class Layer
  class HandMapping
    class KeyMapping
      # ...
    end
  end
end
```

**実装**:
```
lib/cornix/models/
├── layer.rb
└── layer/
    ├── hand_mapping.rb
    ├── key_mapping.rb
    ├── thumb_keys.rb
    └── ...
```

**理由**:
- ファイルサイズの肥大化防止
- 個別テストの容易性
- 保守性の向上

**影響**: なし（むしろ改善）

---

### 2. Validatableモジュールの追加（追加機能）

**元の計画**: ValidationErrorクラスのみ

**実装**:
- Validatableモジュール全体（260行）
- 2段階検証（structural + semantic）
- DSL形式のバリデーション定義
- Custom Validator Arity Detection

**理由**:
- モデルの自己検証能力が必要
- 宣言的なバリデーション定義が望ましい
- コード重複の削減

**影響**: 大幅な機能向上、保守性向上

---

### 3. KeycodeValueの導入（追加コンポーネント）

**元の計画**: 記載なし

**実装**: KeycodeValueクラス（50行）

**理由**:
- キーコード値の型安全性向上
- エイリアス vs QMK形式の明確化
- バリデーションの一元化

**影響**: KeyMappingの型チェックが厳密化

---

### 4. Validatable適用の段階的実装（実装方針）

**元の計画**: 全モデルに一度に適用

**実装**: 5モデルに先行適用、残り14モデルは後回し

**理由**:
- パターン確立と検証
- 段階的なテストカバレッジ拡大
- リスク分散

**影響**: Phase 2が「ほぼ完了」状態（完全完了には残り14モデルへの適用が必要）

---

## メトリクス

### コード行数

| カテゴリ | Phase 2開始前 | Phase 2現在 | 増加 |
|---------|--------------|------------|------|
| 実装コード | ~1,321行 | ~2,398行 | +1,077行 |
| テストコード | ~10,000行 | ~15,000行 | +5,000行 |

**注**: Phase 2は新規コード追加フェーズ。Phase 5-6でLegacyコード削除により、最終的に目標（270行）に到達予定。

### テスト数

| カテゴリ | Phase 2開始前 | Phase 2現在 | 増加 |
|---------|--------------|------------|------|
| Legacyテスト | 493 | 493 | 0 |
| Modelテスト | 0 | ~234 | +234 |
| **合計** | **493** | **~727** | **+234** |

### ファイル数

| カテゴリ | Phase 2開始前 | Phase 2現在 | 増加 |
|---------|--------------|------------|------|
| 実装ファイル | ~20 | ~39 | +19 |
| テストファイル | ~15 | ~33 | +18 |
| **合計** | **~35** | **~72** | **+37** |

---

## Phase 2完了のための残タスク

### タスク一覧

1. **PositionMap** - Validatable適用
2. **QmkSettings** - Validatable適用
3. **Macro** - Validatable適用
4. **MacroSequence** - Validatable適用
5. **MacroAction** - Validatable適用
6. **TapDance** - Validatable適用
7. **TapDanceAction** - Validatable適用
8. **Combo** - Validatable適用
9. **ComboTrigger** - Validatable適用
10. **EncoderMapping** - Validatable適用
11. **EncoderKeys** - Validatable適用
12. **KeycodeValue** - Validatable適用
13. **RowMapping** - Validatable適用
14. **全テスト実行** - 既存493 + 新規234テストが全て合格することを確認

### 推定工数

| タスク | 工数（時間） |
|-------|------------|
| 各モデルValidatable適用 | 0.5時間 × 13 = 6.5時間 |
| テスト調整 | 2時間 |
| ドキュメント更新 | 1時間 |
| **合計** | **9.5時間** |

### 完了条件

- ✅ 19モデル全てにValidatable適用完了
- ✅ 全テスト合格（既存493 + 新規234 = 727テスト）
- ✅ ドキュメント更新完了
- ✅ Phase 2完了マーク

---

## Next Steps（Phase 3準備）

Phase 2完了後、Phase 3（Loader/Writer実装）に進みます。

### Phase 3タスク概要

1. **YamlLoader実装** - YAML → Models
2. **VilLoader実装** - layout.vil → Models
3. **YamlWriter実装** - Models → YAML
4. **VilWriter実装** - Models → layout.vil

詳細は [Migration Guide](./migration_guide.md) を参照。

---

## 実装の知見

Phase 2実装中に得られた知見は [Model Validation Memory](../memories/model_validation.md) に記録されています。

### 重要なパターン

1. **Validatableの適用順序**
   - 依存なしモデル → 依存ありモデルの順
   - 例: KeycodeValue → KeyMapping → ThumbKeys

2. **2段階検証の使い分け**
   - structural: フィールド単体検証（presence, type, format）
   - semantic: コンテキスト検証（他モデルとの関係）

3. **Custom Validator Arity Detection**
   - 1引数: `value`のみ
   - 2引数: `value, options`（contextアクセス可能）

4. **ValidationError vs ArgumentError**
   - ValidationError: バリデーション失敗時
   - ArgumentError: プログラミングエラー時

---

## References

- [Architecture Overview](../architecture/README.md)
- [Current Architecture](../architecture/architecture.md)
- [Models Documentation](../architecture/models.md)
- [Refactor Plan](./refactor_plan.md)
- [Migration Guide](./migration_guide.md)
- [Model Validation Memory](../memories/model_validation.md)

---

## Change Log

| Date | Change | Author |
|------|--------|--------|
| 2026-03-10 | Phase 1完了、Phase 2開始 | System |
| 2026-03-10 | Validatable実装完了（5モデル適用） | System |
| 2026-03-11 | ドキュメント構造整理（.refactor/ → .claude/） | System |
