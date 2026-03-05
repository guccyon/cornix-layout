# Testing and Verification

## Round-trip Check

### 概要
layout.vilファイルの完全性を保証するための標準的な検証手順。

### 目的
- デコンパイル → コンパイルのサイクルでデータが失われないことを確認
- コードの変更が既存の動作を壊していないことを保証

### 手順

#### 1. 準備
```bash
# 現在のconfigをバックアップ（存在する場合）
mv config config.backup_$(date +%Y%m%d_%H%M%S)
```

#### 2. デコンパイル
```bash
# tmp/layout.vil からYAML設定を生成
ruby bin/decompile
```

**出力例**:
```
Decompiling: /Users/.../work/cornix/tmp/layout.vil
Output to: /Users/.../work/cornix/config

  Created: config/metadata.yaml
  Created: config/position_map.yaml
  Created: config/settings/qmk_settings.yaml
  Created: config/layers/0_base.yaml
  ...
✓ Decompilation completed: config
```

#### 3. コンパイル
```bash
# YAML設定からlayout.vilを生成
ruby bin/compile
```

**出力例**:
```
✓ Compiled: /Users/.../work/cornix/layout.vil
✓ Compilation completed: /Users/.../work/cornix/layout.vil
```

#### 4. 比較
```bash
# オリジナルとコンパイル後を比較
ruby bin/diff_layouts
```

**成功時の出力**:
```
=== Comparing layout.vil files ===

Keys in original: alt_repeat_key, combo, encoder_layout, key_override, layout, ...
Keys in compiled: alt_repeat_key, combo, encoder_layout, key_override, layout, ...

Version: ✓
UID: ✓
Vial protocol: ✓
Via protocol: ✓

Layout structure:
  Original layers: 10
  Compiled layers: 10
  Match: ✓

Encoder layout:
  Match: ✓

Macros:
  Original non-empty: 11
  Compiled non-empty: 11
  Match: ✓

Tap Dance:
  Match: ✓

Combos:
  Match: ✓

Settings:
  Match: ✓

=== ✓ FILES ARE IDENTICAL ===
```

**失敗時の出力**:
```
=== ✗ FILES DIFFER ===

Checking differences...
  Layer 1 differs
    Row 2: [KC_A, KC_B, ...]
          vs: [KC_A, KC_C, ...]
```

### bin/diff_layouts の仕組み

#### 比較対象
- `tmp/layout.vil` (オリジナル)
- `layout.vil` (コンパイル後)

#### 比較項目
1. **Metadata**
   - version, uid, vial_protocol, via_protocol

2. **Layout structure**
   - 10レイヤーの完全一致
   - 各レイヤーの各行の配列が一致

3. **Encoder layout**
   - 左右エンコーダーの設定

4. **Macros**
   - 非空マクロの数と内容

5. **Tap Dance**
   - すべてのタップダンス設定

6. **Combos**
   - すべてのコンボ設定

7. **Settings**
   - QMK設定パラメータ

#### 実装
```ruby
# bin/diff_layouts:4-6
orig = JSON.parse(File.read('tmp/layout.vil'))
comp = JSON.parse(File.read('layout.vil'))
```

### トラブルシューティング

#### config/ディレクトリが既に存在
**症状**:
```
⚠️  Error: config/ directory already contains configuration files.
```

**解決**:
```bash
mv config config.backup
ruby bin/decompile
```

#### 比較が失敗する
**原因の特定**:
1. どのセクションで失敗しているか確認
2. 該当するYAMLファイルを確認
3. compile/decompileロジックを確認

**デバッグ手順**:
```bash
# 特定のレイヤーを確認
cat config/layers/1_symbol.yaml

# JSONを直接比較
diff <(jq -S . tmp/layout.vil) <(jq -S . layout.vil)
```

## 開発フロー

### コード変更後の確認
```bash
# 1. コードを修正（compiler.rb, decompiler.rb等）

# 2. Round-trip check
mv config config.old
ruby bin/decompile
ruby bin/compile
ruby bin/diff_layouts

# 3. 期待: FILES ARE IDENTICAL

# 4. 失敗した場合は修正して再テスト
```

### 新機能追加時
```bash
# 1. 新しい機能を実装

# 2. tmp/layout.vilに新機能のデータがあることを確認

# 3. Round-trip check

# 4. 新しいYAMLフィールドが正しく生成されることを確認
cat config/適切なファイル.yaml

# 5. コンパイル後も同じデータが保持されることを確認
```

## RSpecとの違い

### RSpecの状況
- `spec/`ディレクトリは存在
- テストファイル: `integration_spec.rb`, `keycode_resolver_spec.rb`, `position_map_spec.rb`
- 現状は未実装（`spec_helper.rb`の設定が不完全）

### Round-trip Checkの利点
- ✅ 実際のlayout.vilファイルを使用
- ✅ エンドツーエンドのテスト
- ✅ セットアップが簡単（RSpecの設定不要）
- ✅ JSONレベルでの完全一致を保証

### 推奨
現状ではRound-trip Checkを主要な検証方法として使用する。
