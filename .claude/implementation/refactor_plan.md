# Cornix Compiler/Decompiler リファクタリング

## プロジェクト概要

このディレクトリには、Cornix Compiler/Decompiler の大規模リファクタリングに関する設計ドキュメントが含まれています。

## 背景と目的

### 現在の問題点

現在の `compiler.rb` (554行) と `decompiler.rb` (767行) は、以下の問題を抱えています：

1. **責務の混在**: ファイルI/O、データ変換、検証、フォーマット処理が1クラスに混在
2. **重複コード**: `detect_left/right_hand_diff` (計120行)、`compile_base/override_layer` (計140行) 等が重複
3. **ハードウェア座標の散在**: `[2][6]`, `row+4`, `5-col_idx` 等の物理座標計算が16箇所に分散
4. **型なし中間データ**: `@data['layout'][row][col]` のような多次元配列アクセスが型安全性を欠く
5. **テストの困難さ**: ファイル依存が強く、ユニットテストが書きにくい

### リファクタリングの目標

- **中間データモデルの導入**: VialConfig, Layer, Macro 等の PORO モデルで型安全な構造を実現
- **責務の分離**: Loader/Writer でI/O、モデルでビジネスロジック、Validator で検証
- **重複の解消**: ハードウェア座標変換を PositionMap に集約、左右の差分検出を統一
- **テスト可能性**: モデル単位のユニットテスト、結合テストは最小限のハッピーパス

### 期待される効果

#### 定量的効果

- **行数削減**: 1,321行 (compiler+decompiler) → ~270行 (オーケストレーター)
- **重複削減**: 28箇所の重複計算 → 0箇所
- **テスト実行時間**: ~1.77秒 → 目標2.0秒以内
- **テスト数**: 493 → ~415 (重複削除により効率化)

#### 定性的効果

- **保守性向上**: 変更時の影響範囲が明確（キー名変更 → 対象モデルのみ）
- **可読性向上**: 責務が分離され、各クラスが単一責務
- **テスト可能性向上**: モデル単位でのユニットテストが容易
- **拡張性向上**: 新しいエンティティ追加時のパターンが明確

## ドキュメント構成

このディレクトリには以下のドキュメントが含まれています：

### 1. [architecture.md](architecture.md)

システム全体のアーキテクチャ設計。レイヤー構造図、モジュール間依存関係、新旧アーキテクチャの比較を含みます。

**内容**:
- システムレイヤー構造図（Mermaid）
- モジュール間依存関係図（Mermaid class diagram）
- 責務分離の説明
- 新旧アーキテクチャの比較表

### 2. [models.md](models.md)

各モデルの詳細設計。クラス図、メソッドシグネチャ、インナークラスの責務を記載。

**内容**:
- VialConfig（Root Aggregate）
- Layer & LayerCollection（インナークラス含む）
- Macro/TapDance/Combo & Collections
- Metadata & Settings
- モデル階層構造図（Mermaid）

### 3. [data_flow.md](data_flow.md)

データ変換フローの詳細。Compile/Decompile の各ステップをシーケンス図で可視化。

**内容**:
- Compileフロー（Mermaid sequence diagram）
- Decompileフロー（Mermaid sequence diagram）
- 各変換ステップの説明
- データ形式の変換例

### 4. [coordinate_system.md](coordinate_system.md)

座標変換システムの設計。論理座標と物理座標の違い、PositionMapの変換ルールを解説。

**内容**:
- 論理座標 vs 物理座標の説明
- PositionMapの変換ルール
- ハードウェア固有の制約（右手逆順、エンコーダー位置）
- 変換例とテストケース

### 5. [migration_guide.md](migration_guide.md)

実装ガイド。各タスクの実装手順、並列実装の進め方、テストの書き方を記載。

**内容**:
- Phase別の実装手順
- 並列実装可能なタスク
- テストの書き方とfixtureの使用方法
- トラブルシューティング

## 実装フェーズ

### Phase 0: 設計ドキュメント作成 ✅

このディレクトリの全ドキュメント作成（所要時間: 3-4時間）

### Phase 1: 基盤整備

- **Task 1**: PositionMap拡張（物理座標変換メソッド追加）
- 所要時間: 2-3時間

### Phase 2: モデル層実装

- **Task 2**: Metadata & Settings モデル（所要時間: 2-3時間）
- **Task 3**: Macro & MacroCollection モデル（所要時間: 3-4時間）
- **Task 4**: TapDance & TapDanceCollection モデル（所要時間: 3-4時間）
- **Task 5**: Combo & ComboCollection モデル（所要時間: 3-4時間）
- **Task 6**: Layer & LayerCollection モデル（所要時間: 8-10時間）【最も複雑】
- **Task 7**: VialConfig モデル（所要時間: 3-4時間）

**並列実装**: Task 2-6は並列実行可能（Task 1完了後）

### Phase 3: Loader/Writer実装

- **Task 8**: VialLoader（JSON → VialConfig）
- **Task 9**: YamlLoader（YAML → VialConfig）
- **Task 10**: VialWriter（VialConfig → JSON）
- **Task 11**: YamlWriter（VialConfig → YAML）

**並列実装**: Task 8-11は並列実行可能（Task 7完了後）
**所要時間**: 6-8時間（並列実行）

### Phase 4: Converter/Validator実装

- **Task 12**: KeycodeConverter（既存KeycodeResolver移行）
- **Task 13**: ReferenceConverter（既存ReferenceResolver移行）
- **Task 14**: ModelValidator（既存Validator移行）

**並列実装**: Task 12-14は並列実行可能（Task 7完了後）
**所要時間**: 5-6時間（並列実行）

### Phase 5: Orchestrator実装

- **Task 15**: 新Compiler（オーケストレーター）
- **Task 16**: 新Decompiler（オーケストレーター）

**所要時間**: 6-8時間（Task 8-14完了後）

### Phase 6: 検証 & クリーンアップ

- **Task 17**: Round-trip check
- **Task 18**: Spec整理
- **Task 19**: デッドコード削除
- **Task 20**: ドキュメント更新

**所要時間**: 3-4時間（Task 15-16完了後）

## クイックスタートガイド

### 前提条件

- Ruby 2.7+
- RSpec 3.x
- 既存のCornixプロジェクト環境

### 実装開始手順

1. **設計ドキュメントを読む**（このディレクトリ内の全ドキュメント）
2. **Phase 1から実装開始**（PositionMap拡張）
3. **テストを書きながら進める**（Test-after戦略だが、モデル実装直後にテスト作成）
4. **各フェーズ完了時にRound-trip checkを実行**

### 検証方法

```bash
# 既存テストが全てパス
bundle exec rspec

# Round-trip check
mv config config.backup
ruby bin/decompile
ruby bin/compile
ruby bin/diff_layouts  # 期待結果: FILES ARE IDENTICAL
```

### 並列実装の進め方

Phase 2, 3, 4 では複数のタスクを並列実装可能です：

- **Phase 2**: Task 2-6（5つ並列可能、Task 6は最も複雑なため専任推奨）
- **Phase 3**: Task 8-11（4つ並列可能）
- **Phase 4**: Task 12-14（3つ並列可能）

各タスクは独立しており、同じPhase内であれば順序は自由です。

## リスクと緩和策

### リスク1: 出力の差分発生

**リスク**: 新実装で微妙な差異が発生し、Round-trip checkが失敗

**緩和策**:
- Phase 1で PositionMap を先に実装し、既存コードで動作確認
- Phase 5の新Compiler/Decompiler実装時に、1レイヤーずつ検証
- `bin/diff_layouts` で各フェーズごとに検証

### リスク2: テスト実装の遅延

**リスク**: モデル実装が先行し、テストが追いつかない

**緩和策**:
- Test-after戦略だが、モデル実装直後にテストを書く
- Fixtureを先に用意し、テストデータを共通化

### リスク3: 実装量の見積もりミス

**リスク**: 2,850行の新規実装が想定より時間がかかる

**緩和策**:
- Phase 2でシンプルなモデル (Metadata, Settings) から始め、テンプレート化
- Layer モデルが最も複雑なため、Phase 2の最後に実装
- Phase 6で余裕を持ったバッファ（検証 & クリーンアップ）

## 完了条件

- ✅ 全493テスト（既存）がパス
- ✅ Round-trip check (`bin/diff_layouts`) が成功
- ✅ 新テストスイート (~415テスト) がパス
- ✅ `CLAUDE.md` にリファクタリング結果を記録
- ✅ `README.md`, `README.en.md` のアーキテクチャセクション更新
- ✅ メモリファイル (`MEMORY.md`) に設計判断を記録

## 参照

- [Cornix プロジェクトルート](../)
- [CLAUDE.md](../. claude/CLAUDE.md)
- [既存のREADME](../README.md)
