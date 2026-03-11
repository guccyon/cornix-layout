# Architecture Documentation

Cornixプロジェクトのアーキテクチャドキュメント集です。

## Overview

Cornixは現在、モノリシックな構造（v1.x）から責務分離された新アーキテクチャ（v2.x）へのリファクタリング途中です。

## Documents

### 1. [Architecture](./architecture.md)
**最も重要**: 現在の実装状況を反映したアーキテクチャドキュメント。

- 実装済み機能（Phase 1-2完了）
- 5層構造の説明
- モデル層詳細（19ファイル、Validatable統合）
- 未実装部分の明確化

### 2. [Legacy Architecture](./legacy_architecture.md)
v1.x（旧実装）のアーキテクチャドキュメント。

- モノリシックなCompiler/Decompiler構造
- 座標計算の重複
- リファクタリングの動機

### 3. [Models](./models.md)
モデル層の詳細設計。

- 19のモデルクラス
- Validatableモジュール
- インナークラスの分離パターン
- 相互依存関係

### 4. [Coordinate System](./coordinate_system.md)
座標変換システムの詳細。

- PositionMap拡張（5つの座標変換メソッド）
- シンボル → 座標変換
- 座標 → シンボル変換
- 左手・右手の逆順処理

### 5. [Data Flow](./data_flow.md)
データフロー設計。

- Compile: YAML → layout.vil
- Decompile: layout.vil → YAML
- Loader/Writer層の責務
- Converter層の役割

## Architecture Evolution

```
v1.x (Legacy)              v2.x (Current - Phase 2完了)
┌──────────────┐           ┌──────────────────────────┐
│ Compiler     │           │ Presentation Layer      │
│ (~700 lines) │           │   ├─ CLI               │
│              │           │   └─ (TBD)             │
│ Decompiler   │           ├──────────────────────────┤
│ (~600 lines) │    →      │ Orchestration Layer     │
│              │           │   ├─ CompileOrchestrator│
│座標計算重複   │           │   └─ DecompileOrch...  │
│              │           ├──────────────────────────┤
└──────────────┘           │ Application Layer       │
                           │   ├─ Converter (TBD)   │
                           │   └─ Validator (Legacy)│
                           ├──────────────────────────┤
                           │ Domain Layer            │
                           │   ├─ 19 Models ✅      │
                           │   └─ Validatable ✅    │
                           ├──────────────────────────┤
                           │ Infrastructure Layer    │
                           │   ├─ Loader (TBD)      │
                           │   └─ Writer (TBD)      │
                           └──────────────────────────┘
```

## Implementation Status

- ✅ **Phase 1**: PositionMap拡張（座標変換メソッド）
- ✅ **Phase 2**: モデル層実装（19モデル + Validatable）
- 🔄 **Phase 3-6**: 未着手

詳細は [Implementation Guide](../implementation/README.md) を参照。

## Next Steps

1. Phase 2完了の確認（残りモデルへのValidatable適用）
2. Phase 3開始（Loader/Writer実装）
3. Phase 4-6（Converter移行、新Compiler/Decompiler、検証）

詳細は [Refactor Progress](../implementation/refactor_progress.md) を参照。

## Design Principles

### 1. 責務分離 (Separation of Concerns)
- 各層が明確な責務を持つ
- 依存は上位層から下位層へのみ

### 2. テスタビリティ (Testability)
- 各コンポーネントが独立してテスト可能
- モックが容易

### 3. 保守性 (Maintainability)
- コード行数削減（目標: 1,321行 → 270行）
- 重複排除

### 4. 型安全性 (Type Safety)
- KeycodeValueクラスによる型チェック
- Validatableによる自己検証

## References

- [Implementation Guide](../implementation/README.md)
- [Refactor Plan](../implementation/refactor_plan.md)
- [Refactor Progress](../implementation/refactor_progress.md)
- [Migration Guide](../implementation/migration_guide.md)
