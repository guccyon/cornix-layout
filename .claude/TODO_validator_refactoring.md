# Validator Refactoring - TODO List

**ブランチ**: `feature/validator-refactoring`
**開始日**: 2026-03-11
**期間**: 10日間（2週間）

---

## Phase 1: Validatableモード制御（2日）

**目標**: Validatableモジュールにstrict/collectモード制御を追加

### Tasks

- [ ] 1.1 `validate!(context, mode:)` メソッド実装
  - [ ] `:strict` モード（fail-fast、例外投げる）
  - [ ] `:collect` モード（エラー配列返す）
  - [ ] モード検証（無効なモードでエラー）

- [ ] 1.2 `ValidationError` 拡張
  - [ ] `metadata` 属性追加
  - [ ] `format_message` でファイルパス表示
  - [ ] コンストラクタ更新

- [ ] 1.3 テスト実装（~20テスト）
  - [ ] Strict modeテスト（例外投げる）
  - [ ] Collect modeテスト（エラー配列返す）
  - [ ] Metadataテスト（ファイルパス表示）
  - [ ] 無効モードテスト

- [ ] 1.4 既存テスト確認
  - [ ] `bundle exec rspec spec/models/concerns/validatable_spec.rb`
  - [ ] 全テスト合格（734 → 754テスト）

**ファイル**:
- `lib/cornix/models/concerns/validatable.rb` (~50行追加)
- `spec/models/concerns/validatable_spec.rb` (~20テスト追加)

**完了時**: コミット「feat: Add validation mode control to Validatable (strict/collect)」

---

## Phase 2: YAMLメタ情報（1日）

**目標**: YamlLoaderでメタ情報付与、モデルで保存

### Tasks

- [ ] 2.1 YamlLoader拡張
  - [ ] `load_yaml_file` でsingleton method `__metadata` 付与
  - [ ] `load` メソッドに `validate:` パラメータ追加
  - [ ] Auto-validation機能実装

- [ ] 2.2 モデルファクトリーメソッド更新（19モデル）
  - [ ] Metadata.from_yaml_hash
  - [ ] Layer.from_yaml_hash
  - [ ] KeyMapping.from_yaml_hash
  - [ ] HandMapping.from_yaml_hash
  - [ ] ThumbKeys.from_yaml_hash
  - [ ] EncoderMapping.from_yaml_hash
  - [ ] VialConfig.from_yaml_hashes
  - [ ] LayerCollection
  - [ ] Settings.from_yaml_hash
  - [ ] PositionMap.from_yaml_hash (存在する場合)
  - [ ] Macro.from_yaml_hash
  - [ ] MacroCollection
  - [ ] MacroSequence.from_yaml_hash
  - [ ] MacroAction.from_yaml_hash
  - [ ] TapDance.from_yaml_hash
  - [ ] TapDanceCollection
  - [ ] TapDanceAction.from_yaml_hash
  - [ ] Combo.from_yaml_hash
  - [ ] ComboCollection
  - [ ] ComboTrigger.from_yaml_hash

- [ ] 2.3 テスト実装（~10テスト）
  - [ ] Singleton methodテスト
  - [ ] Metadataファイルパステスト
  - [ ] Auto-validationテスト

- [ ] 2.4 既存テスト確認
  - [ ] `bundle exec rspec spec/loaders/yaml_loader_spec.rb`
  - [ ] 全テスト合格（754 → 764テスト）

**ファイル**:
- `lib/cornix/loaders/yaml_loader.rb` (~30行追加)
- `lib/cornix/models/*.rb` (19ファイル、各~5行追加)
- `spec/loaders/yaml_loader_spec.rb` (~10テスト追加)

**完了時**: コミット「feat: Add YAML metadata support with singleton methods」

---

## Phase 3: PositionMap Validatable（1日）

**目標**: PositionMapモデルにValidatable適用

### Tasks

- [ ] 3.1 PositionMap Validatable適用
  - [ ] `include Concerns::Validatable`
  - [ ] Structural validations追加（シンボル形式）
  - [ ] Semantic validations追加（重複チェック）
  - [ ] `from_yaml_hash` 更新（メタ情報保存）

- [ ] 3.2 テスト実装（~30テスト）
  - [ ] Structural validationテスト
  - [ ] Semantic validationテスト
  - [ ] エラーメッセージテスト

- [ ] 3.3 ModelValidator更新
  - [ ] `validate_position_map` メソッド削除
  - [ ] PositionMapモデル検証への委譲
  - [ ] テスト更新

- [ ] 3.4 既存テスト確認
  - [ ] `bundle exec rspec spec/models/position_map_spec.rb`
  - [ ] `bundle exec rspec spec/validators/model_validator_spec.rb`
  - [ ] 全テスト合格（764 → 794テスト）

**ファイル**:
- `lib/cornix/models/position_map.rb` (~100行検証追加)
- `spec/models/position_map_spec.rb` (~30テスト追加)
- `lib/cornix/validators/model_validator.rb` (メソッド削除)

**完了時**: コミット「feat: Apply Validatable to PositionMap model」

---

## Phase 4: KeyMapping セマンティック検証（1日）

**目標**: KeyMappingにセマンティック検証追加

### Tasks

- [ ] 4.1 KeyMapping検証追加
  - [ ] 参照検証（Macro/TapDance/Combo）
  - [ ] キーコード解決検証
  - [ ] ポジションシンボル検証

- [ ] 4.2 テスト実装（~40テスト）
  - [ ] 参照検証テスト
  - [ ] キーコード検証テスト
  - [ ] シンボル検証テスト

- [ ] 4.3 ModelValidator更新
  - [ ] `validate_layer_references` 削除
  - [ ] `validate_keycodes` 削除
  - [ ] `validate_position_references` 削除
  - [ ] KeyMappingモデル検証への委譲
  - [ ] テスト更新

- [ ] 4.4 既存テスト確認
  - [ ] `bundle exec rspec spec/models/layer/key_mapping_spec.rb`
  - [ ] `bundle exec rspec spec/validators/model_validator_spec.rb`
  - [ ] 全テスト合格（794 → 834テスト）

**ファイル**:
- `lib/cornix/models/layer/key_mapping.rb` (~50行検証追加)
- `spec/models/layer/key_mapping_spec.rb` (~40テスト追加)
- `lib/cornix/validators/model_validator.rb` (3メソッド削除)

**完了時**: コミット「feat: Add semantic validations to KeyMapping model」

---

## Phase 5: ModelValidator リファクタリング（1日）

**目標**: ModelValidatorをリネーム・移動・リファクタリング

### Tasks

- [ ] 5.1 ファイル移動
  - [ ] `lib/cornix/validators/model_validator.rb` → `lib/cornix/model_validator.rb`
  - [ ] Namespace更新: `Validators::ModelValidator` → `ModelValidator`

- [ ] 5.2 ModelValidator実装更新
  - [ ] モード対応 `validate(mode: :collect)` 実装
  - [ ] `validate_file_system` メソッド
  - [ ] `validate_models(mode:)` メソッド
  - [ ] 重複検証メソッド削除確認

- [ ] 5.3 Require path更新
  - [ ] `bin/subcommands/compile.rb`
  - [ ] `bin/subcommands/validate.rb`
  - [ ] `spec/model_validator_spec.rb`
  - [ ] 他の参照箇所（Grep確認）

- [ ] 5.4 CLI統合
  - [ ] `compile.rb`: mode: :collect追加
  - [ ] `validate.rb`: mode: :collect追加

- [ ] 5.5 テスト更新（~50テスト）
  - [ ] Mode controlテスト
  - [ ] File-systemテスト
  - [ ] Model delegationテスト

- [ ] 5.6 既存テスト確認
  - [ ] `bundle exec rspec spec/model_validator_spec.rb`
  - [ ] `bundle exec rspec`（全テスト）
  - [ ] 全テスト合格（834テスト維持）

**ファイル**:
- `lib/cornix/model_validator.rb` (移動 + リファクタリング、815 → ~400行)
- `bin/subcommands/compile.rb` (require更新)
- `bin/subcommands/validate.rb` (require更新)
- `spec/model_validator_spec.rb` (~50テスト更新)

**完了時**: コミット「refactor: Rename and relocate ModelValidator to lib/cornix/」

---

## Phase 6: 残り13モデルへのValidatable適用（3日）

**目標**: 全モデルにValidatable適用

### Day 1: VialConfig + Collections（1日）

- [ ] 6.1 VialConfig
  - [ ] Validatable適用
  - [ ] Structural validations
  - [ ] Semantic validations（サブモデル委譲）
  - [ ] テスト（~20テスト）

- [ ] 6.2 LayerCollection
  - [ ] Validatable適用
  - [ ] Validations
  - [ ] テスト（~10テスト）

- [ ] 6.3 MacroCollection
  - [ ] Validatable適用
  - [ ] Validations
  - [ ] テスト（~10テスト）

- [ ] 6.4 TapDanceCollection
  - [ ] Validatable適用
  - [ ] Validations
  - [ ] テスト（~10テスト）

- [ ] 6.5 ComboCollection
  - [ ] Validatable適用
  - [ ] Validations
  - [ ] テスト（~10テスト）

**完了時**: コミット「feat: Apply Validatable to VialConfig and Collections」

### Day 2: Settings + Macro models（1日）

- [ ] 6.6 Settings
  - [ ] Validatable適用
  - [ ] Validations
  - [ ] テスト（~10テスト）

- [ ] 6.7 Macro
  - [ ] Validatable適用
  - [ ] Validations
  - [ ] テスト（~10テスト）

- [ ] 6.8 MacroSequence
  - [ ] Validatable適用
  - [ ] Validations
  - [ ] テスト（~10テスト）

- [ ] 6.9 MacroAction
  - [ ] Validatable適用
  - [ ] Validations
  - [ ] テスト（~10テスト）

**完了時**: コミット「feat: Apply Validatable to Settings and Macro models」

### Day 3: TapDance + Combo models（1日）

- [ ] 6.10 TapDance
  - [ ] Validatable適用
  - [ ] Validations
  - [ ] テスト（~10テスト）

- [ ] 6.11 TapDanceAction
  - [ ] Validatable適用
  - [ ] Validations
  - [ ] テスト（~10テスト）

- [ ] 6.12 Combo
  - [ ] Validatable適用
  - [ ] Validations
  - [ ] テスト（~10テスト）

- [ ] 6.13 ComboTrigger
  - [ ] Validatable適用
  - [ ] Validations
  - [ ] テスト（~10テスト）

- [ ] 6.14 既存テスト確認
  - [ ] `bundle exec rspec`
  - [ ] 全テスト合格（834 → 974テスト）

**完了時**: コミット「feat: Apply Validatable to TapDance and Combo models」

---

## Phase 7: 統合テスト＆ドキュメント（1日）

**目標**: 統合テスト、ドキュメント更新

### Tasks

- [ ] 7.1 Round-trip検証
  - [ ] `mv config config.backup`
  - [ ] `cornix decompile`
  - [ ] `cornix compile`
  - [ ] `ruby bin/diff_layouts`
  - [ ] ✓ FILES ARE IDENTICAL

- [ ] 7.2 Validation modeテスト
  - [ ] エラーYAML作成
  - [ ] `cornix compile` → fail-fast確認
  - [ ] `cornix validate` → 全エラー表示確認
  - [ ] ファイルパス表示確認

- [ ] 7.3 全テストスイート実行
  - [ ] `bundle exec rspec`
  - [ ] 全974テスト合格確認

- [ ] 7.4 手動テスト
  - [ ] `cornix validate` 正常系
  - [ ] `cornix compile` 正常系
  - [ ] `cornix decompile` 正常系
  - [ ] エラーケース確認

- [ ] 7.5 ドキュメント更新
  - [ ] `.claude/implementation/refactor_progress.md` - Phase 2-3完了
  - [ ] `.claude/architecture/architecture.md` - 検証フロー更新
  - [ ] `.claude/features/validation.md` - モード制御追加
  - [ ] `.claude/memories/validator_refactoring.md` - 実装知見
  - [ ] `README.md` - Validation節更新
  - [ ] `README.en.md` - Validation節更新

- [ ] 7.6 最終確認
  - [ ] コミット履歴確認
  - [ ] 変更ファイル確認
  - [ ] 削除ファイル確認（validators/model_validator.rb）

**完了時**: コミット「docs: Update architecture and implementation docs for validator refactoring」

---

## Final Checklist

- [ ] 全974+テスト合格
- [ ] Round-trip check成功
- [ ] 検証エラーにファイルパス表示
- [ ] Compile fail-fast動作（strict mode）
- [ ] Validate全エラー表示（collect mode）
- [ ] ModelValidatorとモデル間の重複排除
- [ ] ModelValidator削減（815 → ~400行）
- [ ] 全19モデルにValidatable適用
- [ ] ドキュメント更新完了
- [ ] Pull Request作成

---

## Progress Tracking

- **Phase 1**: ⬜ Not Started
- **Phase 2**: ⬜ Not Started
- **Phase 3**: ⬜ Not Started
- **Phase 4**: ⬜ Not Started
- **Phase 5**: ⬜ Not Started
- **Phase 6**: ⬜ Not Started
- **Phase 7**: ⬜ Not Started

**Overall**: 0/7 phases complete (0%)
