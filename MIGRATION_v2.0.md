# Cornix v2.0 - 階層化レイヤーYAML構造への移行ガイド

## 概要

Cornix v2.0では、レイヤーファイルの構造を**フラット構造から階層構造**に変更しました。これにより、可読性とメンテナンス性が大幅に向上します。

## 変更内容

### 旧構造（v1.x）
```yaml
# 0_layer.yml
mapping:
  tab: Tab
  Q: Q
  W: W
  l_thumb_left: LGUI_T(LANG2)
  l_rotary_push: Mute
  # ... 50個以上のキーが同じレベルに混在
```

### 新構造（v2.0）
```yaml
# 0_base.yml
mapping:
  left_hand:
    row0:
      tab: Tab
      Q: Q
      W: W
    thumb_keys:
      l_thumb_left: LGUI_T(LANG2)
      l_thumb_middle: Space
      l_thumb_right: Escape
  right_hand:
    row0:
      Y: Y
      # ...
    thumb_keys:
      r_thumb_left: Enter
      r_thumb_middle: MO(1)
      r_thumb_right: LANG1
  encoders:
    left:
      l_rotary_push: Mute
```

## 後方互換性

- ✅ **Compiler**: 新旧両構造を読み込み可能
- ✅ **Validator**: 新旧両構造を検証可能
- ❌ **Decompiler**: 常に新構造で出力（旧構造には戻りません）

## Breaking Changes

- **新規生成**: 常に階層構造で出力
- **ファイル名**: 0_layer.yml → 0_base.yml
- **拡張子**: 全てのレイヤーファイルは `.yml`
- **NoKeyセクション最適化**: 全てのキーが `NoKey` のセクション/rowは出力されない
- **後方互換性**: 既存フラット構造も読み込み可能

## マイグレーション方法

### オプション1: 全て再生成（推奨 - シンプル）

カスタマイズしたファイル名やdescription等が失われます。

```bash
# 1. 現在の設定をバックアップ
cp -r config config.backup.v1

# 2. 古い設定を削除
rm -rf config

# 3. 新構造で再生成
cornix decompile

# 4. コンパイルテスト
cornix compile
ruby bin/diff_layouts  # ✓ FILES ARE IDENTICAL と表示されること
```

**リスク**: カスタマイズしたファイル名、description、nameフィールドが全てデフォルトに戻ります。

---

### オプション2: カスタマイズを保持（推奨）

ファイル名やdescription等のカスタマイズを手動でマージします。

```bash
# 1. 現在の設定をバックアップ
cp -r config config.backup.v1

# 2. 一時ディレクトリに新構造を生成
mkdir config.new
cornix decompile  # config/ に新構造が生成される
mv config config.new

# 3. 旧構造を復元
mv config.backup.v1 config

# 4. カスタマイズを手動でマージ
# - マクロ/タップダンスのファイル名とname/descriptionフィールドをコピー
# - レイヤーファイル名（カスタマイズしている場合）をコピー
```

#### マージ手順の詳細

**a. マクロファイル**
```bash
# 旧: config/macros/03_end_of_line.yml (カスタマイズ済み)
# 新: config.new/macros/03_macro.yml (デフォルト名)

# nameとdescriptionを新ファイルにコピー:
# config.new/macros/03_macro.yml を編集
# - name: "Macro 3" → "End of Line" に変更
# - description: "Macro 3" → "Jump to end of line" に変更

# ファイルをリネーム
mv config.new/macros/03_macro.yml config.new/macros/03_end_of_line.yml
```

**b. タップダンスファイル**
```bash
# 同様に、nameとdescriptionをマージしてリネーム
```

**c. レイヤーファイル**
```bash
# 新構造のレイヤーをそのまま使用（マッピング内容は同じ）
# カスタマイズしたレイヤー名があれば、nameフィールドを編集
```

**d. 旧configを削除して新configに置き換え**
```bash
rm -rf config
mv config.new config
```

**e. コンパイルテスト**
```bash
cornix compile
ruby bin/diff_layouts  # ✓ FILES ARE IDENTICAL
```

---

### オプション3: 段階的移行（最も安全）

新旧を並行して確認しながら移行します。

```bash
# 1. 現在の設定をバックアップ
cp -r config config.backup.v1

# 2. 別の作業ディレクトリで新構造を確認
cd /tmp
git clone <your-repo> cornix-test
cd cornix-test
cornix decompile
cat config/layers/0_base.yaml  # 新構造を確認

# 3. 問題なければ、元のリポジトリで適用
cd <original-repo>
rm -rf config
cornix decompile

# 4. カスタマイズをマージ（オプション2の手順に従う）

# 5. コンパイルテスト
cornix compile
ruby bin/diff_layouts
```

---

## 新構造の利点

### 1. 視覚的な構造化
```yaml
# 一目で左手・右手・エンコーダーが区別できる
# 親指キーは物理的な配置に従い、左手・右手セクション内に配置
mapping:
  left_hand:     # 左手セクション
    row0: ...
    row1: ...
    row2: ...
    row3: ...
    thumb_keys:  # ← row3の直後に配置
  right_hand:    # 右手セクション
    row0: ...
    row1: ...
    row2: ...
    row3: ...
    thumb_keys:  # ← row3の直後に配置
  encoders:      # エンコーダーセクション（別位置）
```

### 2. メンテナンス性向上
- 特定のセクションだけを編集しやすい
- 行数が増えても迷わない
- コメントを追加しやすい

### 3. オーバーライドレイヤーの最適化
```yaml
# 変更のあるセクションのみ出力（差分最小化）
overrides:
  left_hand:
    row0:
      tab: Escape  # この行だけ変更
  # 他のセクションは省略（ベースから継承）
```

## トラブルシューティング

### Q1: マイグレーション後にコンパイルエラーが出る

**A**: Validatorのエラーメッセージを確認してください。
```bash
cornix validate
```

よくあるエラー:
- `Unknown position symbol 'tab'` → 階層構造が壊れている可能性
  - 解決: `cornix decompile` で再生成

### Q2: カスタマイズしたマクロ名が失われた

**A**: オプション2の手順に従って、旧構造から手動でマージしてください。
```bash
# config.backup.v1/macros/*.yml から name/description をコピー
```

### Q3: Round-tripチェックが失敗する

**A**: まずクリーンな状態から試してください。
```bash
rm -rf config
cornix decompile
cornix compile
ruby bin/diff_layouts
```

それでも失敗する場合は、Issueを報告してください。

### Q4: 既存の設定を新構造に手動で変換できる？

**A**: できますが推奨しません。`cornix decompile` を使用してください。

手動変換する場合:
```yaml
# 旧構造
mapping:
  tab: Tab
  Q: Q

# 新構造に変換
mapping:
  left_hand:
    row0:
      tab: Tab
      Q: Q
```

ただし、position_mapの構造に正確に従う必要があり、エラーが起きやすいです。

## ロールバック方法

新構造で問題が発生した場合、一時的に旧バージョンに戻すことができます。

```bash
# 1. 新構造を保存
mv config config.new

# 2. 旧構造を復元
mv config.backup.v1 config

# 3. 旧バージョンのCornixを使用
git checkout <previous-commit>
cornix compile
```

**注意**: 旧バージョンに戻っても、新構造の利点は失われます。問題を報告して、新バージョンで解決することを推奨します。

## Position Map 構造の変更

親指キーの配置が変更され、より自然で直感的な構造になりました。

### 旧構造
```yaml
left_hand:
  row0: [tab, Q, W, E, R, T]
  row1: [caps, A, S, D, F, G]
  row2: [lshift, Z, X, C, V, B]
  row3: [lctrl, command, option]
right_hand:
  row0: [Y, U, I, O, P, backspace]
  row1: [H, J, K, L, colon, enter]
  row2: [N, M, comma, dot, up, rshift]
  row3: [left, down, right]
thumb_keys:
  left: [l_thumb_left, l_thumb_middle, l_thumb_right]
  right: [r_thumb_left, r_thumb_middle, r_thumb_right]
encoders:
  left:
    push: l_rotary_push
    ccw: l_rotary_ccw
    cw: l_rotary_cw
```

### 新構造
```yaml
left_hand:
  row0: [tab, Q, W, E, R, T]
  row1: [caps, A, S, D, F, G]
  row2: [lshift, Z, X, C, V, B]
  row3: [lctrl, command, option]
  thumb_keys: [l_thumb_left, l_thumb_middle, l_thumb_right]  # ← row3の直後
right_hand:
  row0: [Y, U, I, O, P, backspace]
  row1: [H, J, K, L, colon, enter]
  row2: [N, M, comma, dot, up, rshift]
  row3: [left, down, right]
  thumb_keys: [r_thumb_left, r_thumb_middle, r_thumb_right]  # ← row3の直後
encoders:  # ← エンコーダーは別グループで維持
  left:
    push: l_rotary_push
    ccw: l_rotary_ccw
    cw: l_rotary_cw
```

### 変更理由

**改善点**:
- 親指キーは物理的にキーボードの一部であり、左手・右手それぞれのセクション内に配置することで、物理的な配置と構造が一致
- 左手全体、右手全体を一目で把握可能
- セクションとしての区別は保ちつつ、視覚的な連続性を確保
- エンコーダーは明確にキーと異なる位置にあるため、別グループで維持

**マイグレーション影響**:
- `position_map.yaml`も自動的に更新されます
- 手動でカスタマイズした場合は、新構造に合わせて調整してください
- レイヤーファイル（`0_base.yml`等）も自動的に新構造で生成されます

## 参考情報

- Round-trip整合性テスト: `ruby bin/diff_layouts`
- バリデーション: `cornix validate`
- Issue報告: https://github.com/anthropics/claude-code/issues

---

**v2.0リリース日**: 2026-03-09
