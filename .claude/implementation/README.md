# Implementation Guide

Cornixプロジェクトのリファクタリング実装ガイドです。

## Overview

Cornixは現在、モノリシックな構造（v1.x）から責務分離された5層アーキテクチャ（v2.x）へのリファクタリング中です。

## Current Status

### ✅ 完了
- **Phase 1**: PositionMap拡張（座標変換メソッド5つ追加）
- **Phase 2**: モデル層実装（19モデル、Validatableモジュール）
  - Validatable適用: 5/19モデル（残り14モデルは未適用）

### 🔄 進行中
- Phase 2完了のための残タスク（14モデルへのValidatable適用）

### 📋 未着手
- **Phase 3**: Loader/Writer実装
- **Phase 4**: Converter移行
- **Phase 5**: 新Compiler/Decompiler実装
- **Phase 6**: 検証とクリーンアップ

## Documents

### 1. [Refactor Plan](./refactor_plan.md)
リファクタリングの全体計画。

- 目標: コード行数削減（1,321行 → 270行）
- 6つのフェーズ
- 各フェーズの詳細タスク

### 2. [Refactor Progress](./refactor_progress.md) ⭐ **最重要**
実装進捗の詳細記録。

- Phase 1-2の実装状況
- 実装済みファイル一覧（19モデル、18テスト）
- 元の計画との差異
- メトリクス（コード行数、テスト数）
- 残タスク

### 3. [Migration Guide](./migration_guide.md)
Phase 3以降のタスクと移行手順。

- Loader/Writer実装ガイド
- Converter移行ガイド
- 新Compiler/Decompiler実装ガイド

## Phase Overview

```
Phase 0: 設計 ✅
  └─ アーキテクチャ設計、ドキュメント作成

Phase 1: PositionMap拡張 ✅
  └─ 座標変換メソッド追加（5つ）

Phase 2: モデル層実装 🔄 95%
  ├─ 19モデル実装 ✅
  ├─ Validatableモジュール実装 ✅
  ├─ Validatable適用（5/19） ✅
  └─ Validatable適用（残り14/19） 🔄

Phase 3: Loader/Writer実装 📋
  ├─ YamlLoader
  ├─ VilLoader
  ├─ YamlWriter
  └─ VilWriter

Phase 4: Converter移行 📋
  ├─ KeycodeConverter → Application Layer
  └─ ReferenceConverter → Application Layer

Phase 5: 新Compiler/Decompiler 📋
  ├─ CompileOrchestrator
  └─ DecompileOrchestrator

Phase 6: 検証とクリーンアップ 📋
  ├─ Round-trip check
  ├─ Legacy code削除
  └─ ドキュメント最終更新
```

## Quick Start

### Phase 2完了のための作業

```bash
# 1. 残りモデルへのValidatable適用
# 各モデルに以下を追加:
# - include Validatable
# - structural_validations do ... end
# - validate! in initialize

# 2. テスト実行
bundle exec rspec spec/models/

# 3. 進捗更新
vim .claude/implementation/refactor_progress.md
```

### Phase 3開始のための作業

```bash
# 1. 設計レビュー
cat .claude/implementation/migration_guide.md

# 2. YamlLoader実装開始
vim lib/cornix/infrastructure/loaders/yaml_loader.rb

# 3. テスト作成
vim spec/infrastructure/loaders/yaml_loader_spec.rb
```

## Implementation Workflow

### 1. 計画確認
- [Refactor Plan](./refactor_plan.md) でフェーズの全体像を把握
- [Migration Guide](./migration_guide.md) で具体的なタスクを確認

### 2. 実装
- 各フェーズのタスクを順次実装
- テストを書きながら進める（TDD）

### 3. 検証
- テスト実行（`bundle exec rspec`）
- Round-trip check（`ruby bin/diff_layouts`）

### 4. ドキュメント更新
- [Refactor Progress](./refactor_progress.md) を更新
- 実装した内容を記録

### 5. コミット
```bash
git add .
git commit -m "feat: implement Phase X - ..."
```

## Testing Strategy

### Legacy Tests（既存）
```bash
# 全テスト実行（493テスト）
bundle exec rspec

# 特定カテゴリ
bundle exec rspec spec/compiler_spec.rb
bundle exec rspec spec/decompiler_spec.rb
bundle exec rspec spec/validator_spec.rb
```

### Model Tests（新規）
```bash
# モデル層全体
bundle exec rspec spec/models/

# 特定モデル
bundle exec rspec spec/models/metadata_spec.rb
bundle exec rspec spec/models/layer_spec.rb

# Validatableモジュール
bundle exec rspec spec/models/concerns/validatable_spec.rb
```

### Integration Tests
```bash
# Round-trip check
mv config config.backup
ruby bin/decompile
ruby bin/compile
ruby bin/diff_layouts  # ✓ FILES ARE IDENTICAL

# バックアップ復元
rm -rf config
mv config.backup config
```

## Key Files

### Implementation Files
- `lib/cornix/models/` - モデル層（19ファイル、~1,077行）
- `lib/cornix/models/concerns/validatable.rb` - Validatableモジュール（260行）
- `lib/cornix/position_map.rb` - PositionMap拡張（Phase 1）

### Test Files
- `spec/models/` - モデル層テスト（18ファイル、~5,000行、200-250テスト）
- `spec/models/concerns/validatable_spec.rb` - Validatableテスト（34テスト）

### Documentation
- `.claude/architecture/` - アーキテクチャドキュメント
- `.claude/implementation/` - 実装ガイド（このディレクトリ）
- `.claude/features/` - 機能別ドキュメント
- `.claude/memories/` - 実装の知見

## Metrics

### Phase 2時点
- **実装済みコード**: ~1,077行（モデル層）
- **テストコード**: ~5,000行（200-250テスト）
- **実装進捗**: Phase 2 95%完了

### 目標（Phase 6完了時）
- **コード行数削減**: 1,321行 → 270行（全体）
- **重複削除**: 座標計算の重複排除
- **テストカバレッジ**: 100%維持

## Design Principles

### 1. 段階的実装
- 各フェーズを完全に完了させてから次へ
- テストを書きながら進める
- 既存機能を壊さない

### 2. 後方互換性
- Legacy CLIは維持（bin/cornix）
- Round-trip checkで検証
- ユーザーには透過的

### 3. ドキュメント駆動
- 実装前に設計を文書化
- 実装後に進捗を記録
- 知見をmemoriesに保存

### 4. テスト駆動
- テストファースト
- 各コンポーネントを独立してテスト
- Integration testで全体検証

## Common Tasks

### Validatable適用パターン
```ruby
# 1. Validatableをinclude
class ModelName
  include Validatable

  attr_accessor :field1, :field2

  # 2. structural_validationsを定義
  structural_validations do
    validate :field1, presence: true, type: String
    validate :field2, presence: true, type: Integer
  end

  # 3. initializeでvalidate!呼び出し
  def initialize(field1:, field2:)
    @field1 = field1
    @field2 = field2
    validate!
  end
end
```

### テストパターン
```ruby
RSpec.describe ModelName do
  describe '#initialize' do
    it 'creates valid instance' do
      model = described_class.new(field1: 'value', field2: 123)
      expect(model.valid?).to be true
    end

    it 'raises ValidationError for invalid data' do
      expect {
        described_class.new(field1: nil, field2: 123)
      }.to raise_error(Cornix::Models::ValidationError)
    end
  end
end
```

## Troubleshooting

### テストが失敗する
```bash
# 詳細出力で実行
bundle exec rspec --format documentation

# 特定のテストのみ実行
bundle exec rspec spec/models/metadata_spec.rb:10
```

### Validatableの検証エラー
```ruby
# エラーメッセージを確認
begin
  model = Model.new(invalid: data)
rescue Cornix::Models::ValidationError => e
  puts e.errors  # 全エラーを表示
end
```

### Round-trip checkの失敗
```bash
# どのセクションで差分があるか確認
ruby bin/diff_layouts

# 手動でYAMLを確認
cat config/layers/0_base.yaml
cat config.backup/layers/0_base.yaml
```

## References

- [Architecture Overview](../architecture/README.md)
- [Current Architecture](../architecture/architecture.md)
- [Models Documentation](../architecture/models.md)
- [Model Validation Memory](../memories/model_validation.md)
- [Main Development Guide](../CLAUDE.md)

## Next Steps

1. **Phase 2完了**: 残り14モデルへのValidatable適用
2. **Phase 3開始**: Loader/Writer実装
3. **継続的更新**: [Refactor Progress](./refactor_progress.md)を更新
