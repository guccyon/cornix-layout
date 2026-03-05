# Cornix Keyboard Layout Manager - Project Context

## What is Cornix?

Cornixは分割型キーボードで、以下の特徴を持つ：
- 左右それぞれ6列×4行のキー配置
- ロータリーエンコーダー（左右1個ずつ）
- Vialファームウェア対応

## What is Vial?

Vialは、QMKファームウェアベースのキーボード設定ツール。
- GUIでキーマップを編集可能
- 設定を`layout.vil`ファイルとして保存
- リアルタイムでキーボードに反映

## Problem Statement

### Vialの課題
1. **layout.vilは直接編集が困難**
   - バイナリ的なJSON形式
   - 人間が読みにくい構造
   - GitやDiffでの管理が難しい

2. **バージョン管理が困難**
   - 変更履歴の追跡が難しい
   - レビューが困難
   - 複数人での編集がしづらい

3. **ドキュメント化が難しい**
   - コメントを書けない
   - 意図が伝わりにくい

### 解決策

このプロジェクトは、layout.vilとYAML設定ファイル間の双方向変換を提供：

```
layout.vil ←→ YAML Configuration Files
  (Vial)         (Human-readable)
```

**利点**:
- ✅ 人間が読める形式（YAML）
- ✅ Git管理が容易
- ✅ コメント記述可能
- ✅ モジュール化（レイヤー、マクロ、タップダンスを個別ファイルで管理）
- ✅ 差分管理（上位レイヤーはLayer 0からの差分のみ）

## Use Cases

### 1. キーマップのバージョン管理
```bash
# layout.vilをYAML設定に変換
ruby bin/decompile

# Gitで管理
git add config/
git commit -m "Update symbol layer shortcuts"
```

### 2. チーム開発
```bash
# メンバーAがレイヤー1を編集
# config/layers/1_symbol.yaml を編集

# メンバーBがマクロを追加
# config/macros/new_macro.yaml を作成

# マージが容易
git merge feature/add-macro
```

### 3. 設定の共有
```yaml
# config/layers/1_symbol.yaml
name: Symbol (Mac)
description: Mac用シンボルレイヤー

# コメントで意図を説明
overrides:
  Q: "LShift+[1]"    # ! を入力
  W: "LShift+[2]"    # @ を入力

  # VSCode用ショートカット
  A: MACRO(bracket_pair)
```

### 4. 設定の再利用
```bash
# 別のキーボードに設定を移植
cp -r cornix/config/ other-keyboard/config/
cd other-keyboard
ruby bin/compile
```

## Technical Background

### QMK Firmware
- オープンソースのキーボードファームウェア
- 高度なカスタマイズ機能
- レイヤー、マクロ、タップダンス、コンボなど

### Vial Protocol
- QMKの拡張
- リアルタイム設定変更
- layout.vil形式での設定保存

### Key Concepts

#### Layers (レイヤー)
- 最大10レイヤー（0-9）
- Layer 0: ベースレイヤー（常時有効）
- Layer 1-9: 条件付きで有効化

#### Macros (マクロ)
- キーの連続入力を記録
- 複雑な操作を1キーで実行

#### Tap Dance (タップダンス)
- タップ回数で動作を変更
- 例: 1回タップ → A, 2回タップ → B

#### Combos (コンボ)
- 複数キー同時押しで別のキーを出力
- 例: D + F → [

#### Encoders (ロータリーエンコーダー)
- 回転とプッシュで操作
- CW (時計回り), CCW (反時計回り), Push

## File Format Details

### layout.vil Structure
```json
{
  "version": 1,
  "uid": "...",
  "layout": [[...], [...], ...],      // 10 layers
  "encoder_layout": [[...], ...],     // Encoder settings
  "macro": [[...], ...],              // Macros
  "tap_dance": [[...], ...],          // Tap dances
  "combo": [[...], ...],              // Combos
  "settings": {...}                   // QMK settings
}
```

### YAML Configuration Structure
```
config/
├── metadata.yaml           # Version, UID, protocols
├── position_map.yaml       # Physical key positions
├── settings/
│   └── qmk_settings.yaml   # Tapping term, etc.
├── layers/
│   ├── 0_base.yaml         # Full key mapping
│   └── 1_symbol.yaml       # Overrides only
├── macros/
│   └── macro_name.yaml     # Macro sequences
├── tap_dance/
│   └── td_name.yaml        # Tap dance actions
└── combos/
    └── combo_name.yaml     # Combo definitions
```

## Design Philosophy

### Human-Readable First
- YAMLで直感的に編集可能
- コメントで意図を記述
- 英数字の名前でわかりやすく

### Modular Organization
- 機能ごとに個別ファイル
- 変更の影響範囲を限定
- チーム開発を容易に

### Differential Layers
- Layer 0のみ完全定義
- Layer 1-9は差分のみ
- 変更箇所が明確

### Safety First
- 既存設定の上書き防止
- Round-trip checkで完全性保証
- エラーメッセージで問題箇所を明示

## Future Enhancements

### 計画中
- [ ] Validation機能の実装
- [ ] RSpecテストの整備
- [ ] カスタムエイリアスのサポート
- [ ] ライブラリ機能（コミュニティマクロ）
- [ ] GUI設定エディタ

### 検討中
- [ ] 他キーボードへの対応
- [ ] VSCode拡張
- [ ] Web版エディタ
