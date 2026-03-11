# Cornix Keyboard Layout Manager - Development Guide

## Quick Links

- **Architecture**: [Architecture Documentation](architecture/README.md)
  - [Current Architecture](architecture/architecture.md) ⭐ Phase 2実装状況
  - [Legacy Architecture](architecture/legacy_architecture.md)
  - [Models](architecture/models.md)
  - [Coordinate System](architecture/coordinate_system.md)
  - [Data Flow](architecture/data_flow.md)

- **Implementation**: [Implementation Guide](implementation/README.md)
  - [Refactor Plan](implementation/refactor_plan.md)
  - [Refactor Progress](implementation/refactor_progress.md) ⭐ 実装進捗詳細
  - [Migration Guide](implementation/migration_guide.md)

- **Features**:
  - [Reference System](features/reference_system.md) - Macro/TapDance/Combo参照
  - [Modifier Expressions](features/modifier_expressions.md) - VS Code風修飾キー表現
  - [File Renamer](features/file_renamer.md) - ファイルリネーム機能
  - [Validation](features/validation.md) - バリデーション機能

- **Memories**: [Implementation Memories](memories/)
  - [Model Validation](memories/model_validation.md) - Validatable実装知見

## Recent Changes

### v2.x - Model Layer Implementation (2026-03-10) 🔄 進行中

**Phase 2（モデル層実装）**: 95%完了

**実装済み**:
- ✅ Validatableモジュール (260行、2段階検証)
- ✅ 19モデル実装 (~1,077行)
- ✅ Validatable適用 (5/19モデル)
- 🔄 Validatable適用 (残り14モデル)

詳細: [Refactor Progress](implementation/refactor_progress.md)

### v2.0 - 階層化レイヤーYAML構造への移行 (2026-03-10)

**Breaking Change**: レイヤーYAMLファイルとposition_mapの構造が階層化されました。

**主な変更**:
1. **シンボル名の簡略化**: `l_thumb_left` → `left`, `l_rotary_push` → `push`
2. **階層パスによる一意性保証**: `left_hand.thumb_keys.left`, `encoders.left.push`
3. **レイヤーファイルの階層構造**

**Migration**: `cornix decompile`で自動的に新形式に変換されます。

---

## Development Instructions

**重要な原則**:
- 作業完了時には、得られた知見を `.claude/memories/` に記録すること
- `README.md` と `README.en.md` は**常に一緒に更新**すること
- プロンプト及び計画、作業結果の報告は全て日本語で行うこと
- タスクを実行してコミットする際には必ず RSpec が全て通る状態を確認すること

## Project Overview

CornixキーボードのVial `layout.vil`ファイルとYAML設定ファイル間の双方向変換ツール。

**機能**:
- Compile: YAML → layout.vil
- Decompile: layout.vil → YAML
- Validate: YAML設定の妥当性検証
- Rename: ファイルリネーム機能

**特徴**:
- 3つの参照形式サポート（Name-based, Index-based, Legacy）
- VS Code風修飾キー表現（`Cmd + Q`）
- Round-trip互換性（完全なデータ整合性）

## Architecture Overview

現在の5層構造（Phase 2完了時点）:

```
Presentation Layer
  └─ CLI (bin/cornix)
       ↓
Orchestration Layer (TBD)
  └─ CompileOrchestrator, DecompileOrchestrator
       ↓
Application Layer
  └─ Converter (TBD), Validator (Legacy)
       ↓
Domain Layer ✅ 実装済み
  ├─ 19 Models (~1,077行)
  └─ Validatable Concern (260行)
       ↓
Infrastructure Layer (TBD)
  └─ Loader, Writer
```

詳細: [Current Architecture](architecture/architecture.md)

## Core Components

1. **Compiler** (`lib/cornix/compiler.rb`) - YAML → layout.vil
2. **Decompiler** (`lib/cornix/decompiler.rb`) - layout.vil → YAML
3. **KeycodeParser** (`lib/cornix/keycode_parser.rb`) - 構文解析
4. **ReferenceConverter** (`lib/cornix/converters/reference_converter.rb`) - 参照解決
5. **KeycodeConverter** (`lib/cornix/converters/keycode_converter.rb`) - エイリアス解決
6. **FileRenamer** (`lib/cornix/file_renamer.rb`) - ファイルリネーム
7. **Validator** (`lib/cornix/validator.rb`) - 設定ファイル検証
8. **Models** (`lib/cornix/models/`) - ドメインモデル（19ファイル、Phase 2実装）

## Directory Structure

```
cornix/
├── bin/
│   ├── cornix              # Main CLI dispatcher
│   └── subcommands/        # compile, decompile, validate, cleanup, rename
├── lib/cornix/
│   ├── compiler.rb, decompiler.rb
│   ├── keycode_parser.rb
│   ├── converters/         # ReferenceConverter, KeycodeConverter
│   ├── models/             # 19 domain models ✅ Phase 2
│   │   ├── concerns/       # Validatable
│   │   ├── layer/          # Layer submodels
│   │   ├── macro/, tap_dance/, combo/
│   │   └── ...
│   ├── file_renamer.rb, validator.rb
│   ├── keycode_aliases.yaml
│   └── position_map.yaml
├── spec/                   # 700+ tests
│   ├── models/             # ~234 tests (Phase 2) ✅
│   └── ...
├── .claude/
│   ├── CLAUDE.md           # This file
│   ├── architecture/       # Architecture docs
│   ├── implementation/     # Implementation guide
│   ├── features/           # Feature docs
│   └── memories/           # Implementation knowledge
└── config/                 # User configuration (generated)
    ├── layers/, macros/, tap_dance/, combos/
    ├── metadata.yaml, position_map.yaml
    └── settings/qmk_settings.yaml
```

## Quick Reference

### Common Commands

```bash
# Compile
cornix compile              # Auto-validates, then compiles

# Decompile
cornix decompile            # Generates config/ from layout.vil

# Validate
cornix validate             # Validates YAML configuration

# Rename
cornix rename               # Interactive file renaming

# Cleanup
cornix cleanup              # Removes generated files

# Round-trip check
mv config config.backup
cornix decompile
cornix compile
ruby bin/diff_layouts       # ✓ FILES ARE IDENTICAL
```

### Testing

```bash
# All tests (700+ tests)
bundle exec rspec

# Model tests (Phase 2)
bundle exec rspec spec/models/

# Legacy tests
bundle exec rspec spec/compiler_spec.rb
bundle exec rspec spec/decompiler_spec.rb
bundle exec rspec spec/validator_spec.rb

# Integration tests
bundle exec rspec spec/integration_spec.rb
```

### Development Workflow

1. **計画確認**: [Refactor Progress](.claude/implementation/refactor_progress.md)
2. **実装**: 各フェーズのタスクを順次実装
3. **テスト**: `bundle exec rspec`
4. **Round-trip check**: `ruby bin/diff_layouts`
5. **ドキュメント更新**: `.claude/implementation/refactor_progress.md`
6. **知見記録**: `.claude/memories/`
7. **コミット**: `git commit`

## Key Design Decisions

### 1. Alias System
- layout.vil: 必ずQMK形式（`KC_*`）
- YAML: エイリアス形式（`Tab`, `Space`）
- 関数引数の処理ルール: レイヤー切り替え系は数値保持、修飾キー系は`KC_*`変換

### 2. Reference System
- 3形式サポート: Name-based, Index-based, Legacy
- Name-based推奨（可読性、FileRenamer自動更新）
- Decompiler: 常にname-based形式で出力

詳細: [Reference System](features/reference_system.md)

### 3. Modifier Expression System
- VS Code風構文: `Cmd + Q`, `Shift + Ctrl + A`
- QMKショートカット自動検出: LSG, MEH, HYPR等
- Decompiler: QMK形式を保持（逆変換しない）

詳細: [Modifier Expressions](features/modifier_expressions.md)

### 4. Model Layer Architecture
- 5層構造: Presentation → Orchestration → Application → Domain → Infrastructure
- Validatableモジュール: 2段階検証（structural + semantic）
- 19モデル実装済み（Phase 2）

詳細: [Current Architecture](architecture/architecture.md)

### 5. Position Map Structure
- 階層化構造（v2.0）: `left_hand.thumb_keys.left`
- シンボル名簡略化: 冗長なプレフィックス削除
- システムファイル: `lib/cornix/position_map.yaml`
- ユーザー版: `config/position_map.yaml`（カスタマイズ可能）

### 6. File Organization
- `lib/cornix/keycode_aliases.yaml`: システムファイル（config/にコピーしない）
- `lib/cornix/position_map.yaml`: テンプレート
- `lib/cornix/models/`: ドメインモデル（Phase 2実装）

## Testing & Verification

### Round-trip Check（標準検証手順）

```bash
# 1. バックアップ
mv config config.backup

# 2. Decompile
cornix decompile

# 3. Compile
cornix compile

# 4. 比較
ruby bin/diff_layouts
# 期待結果: === ✓ FILES ARE IDENTICAL ===
```

### Test Coverage

- **Legacy tests**: 493テスト（Phase 2開始前）
- **Model tests**: ~234テスト（Phase 2）
- **合計**: ~727テスト

## Current Status

### ✅ 完了
- Phase 1: PositionMap拡張（座標変換メソッド）
- Phase 2: モデル層実装（19モデル、Validatable）
  - Validatable適用: 5/19モデル

### 🔄 進行中
- Phase 2完了: 残り14モデルへのValidatable適用

### 📋 未着手
- Phase 3: Loader/Writer実装
- Phase 4: Converter移行
- Phase 5: 新Compiler/Decompiler
- Phase 6: 検証とクリーンアップ

詳細: [Refactor Progress](implementation/refactor_progress.md)

## Next Steps

### 1. Phase 2完了（即座）
残り14モデルへのValidatable適用:
- PositionMap, QmkSettings
- Macro, MacroSequence, MacroAction
- TapDance, TapDanceAction
- Combo, ComboTrigger
- EncoderMapping, EncoderKeys
- KeycodeValue, RowMapping

### 2. Phase 3開始（Phase 2完了後）
Loader/Writer実装:
- YamlLoader, VilLoader
- YamlWriter, VilWriter

### 3. Phase 4-6（Phase 3完了後）
Converter移行、新Compiler/Decompiler、検証とクリーンアップ

詳細: [Migration Guide](implementation/migration_guide.md)

## Troubleshooting

### keycode_aliases.yamlが見つからない
→ `lib/cornix/keycode_aliases.yaml`の配置を確認

### Round-trip checkが失敗する
→ `ruby bin/diff_layouts`で差分箇所を確認

### config/ディレクトリが生成されない
→ `.decompile.lock`ファイルを削除

### テストが失敗する
→ `bundle exec rspec --format documentation`で詳細確認

## References

### Official Documentation
- [QMK Keycodes](https://docs.qmk.fm/keycodes)
- [Vial Documentation](https://get.vial.today/)
- [QMK Firmware](https://docs.qmk.fm/)

### Internal Documentation
- [Architecture](architecture/README.md)
- [Implementation Guide](implementation/README.md)
- [Feature Documentation](features/)
- [Implementation Memories](memories/)

### Help & Feedback
- `/help`: Get help with using Claude Code
- Feedback: https://github.com/anthropics/claude-code/issues

---

**Note**: このCLAUDE.mdは簡潔なインデックス版です。詳細な実装ガイドやアーキテクチャ情報は、各リンク先のドキュメントを参照してください。
