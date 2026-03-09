# Position Map 親指キーセクション マイグレーションガイド

## 変更の概要

Cornix v1.x（2026年3月9日）より、`position_map.yaml`の構造が変更されました。親指クラスタキーを独立した`thumb_keys`セクションに分離し、より明確で保守しやすい設定構造になりました。

### 主な変更点

1. **row3の要素数**: 6要素 → 3要素（標準グリッドキーのみ）
2. **親指キーの分離**: 新しい`thumb_keys`セクションを追加
3. **シンボル名の変更**: より明確で一貫性のある命名

## 新旧構造の比較

### 旧構造（v0.x以前）

```yaml
left_hand:
  row0: [tab, Q, W, E, R, T]
  row1: [lctrl, A, S, D, F, G]
  row2: [lshift, Z, X, C, V, B]
  row3: [caps, fn, option, command, space, esc]  # 6要素

right_hand:
  row0: [Y, U, I, O, P, backspace]
  row1: [H, J, K, L, colon, backslash]
  row2: [N, M, comma, dot, up, rshift]
  row3: [enter, raise, lang, left, down, right]  # 6要素

encoders:
  left:
    push: l_rotary_push
    ccw: l_rotary_ccw
    cw: l_rotary_cw
  right:
    push: r_rotary_push
    ccw: r_rotary_ccw
    cw: r_rotary_cw
```

### 新構造（v1.x以降）

```yaml
left_hand:
  row0: [tab, Q, W, E, R, T]
  row1: [caps, A, S, D, F, G]                # caps に変更
  row2: [lshift, Z, X, C, V, B]
  row3: [lctrl, option, command]             # 3要素のみ

right_hand:
  row0: [Y, U, I, O, P, backspace]
  row1: [H, J, K, L, colon, backslash]
  row2: [N, M, comma, dot, up, rshift]
  row3: [left, down, right]                  # 3要素のみ

thumb_keys:                                  # 新規セクション
  left: [thumb_l_left, thumb_l_middle, thumb_l_right]
  right: [thumb_r_left, thumb_r_middle, thumb_r_right]

encoders:
  left:
    push: l_rotary_push
    ccw: l_rotary_ccw
    cw: l_rotary_cw
  right:
    push: r_rotary_push
    ccw: r_rotary_ccw
    cw: r_rotary_cw
```

### シンボル名のマッピング表

| 旧シンボル名 | 物理位置 | 新シンボル名 | 備考 |
|------------|---------|-------------|------|
| `command` | 左手 row3[3] | `thumb_l_left` | 親指キーに移動 |
| `space` | 左手 row3[4] | `thumb_l_middle` | 親指キーに移動 |
| `esc` | 左手 row3[5] | `thumb_l_right` | 親指キーに移動 |
| `enter` | 右手 row3[0] | `thumb_r_left` | 親指キーに移動 |
| `raise` | 右手 row3[1] | `thumb_r_middle` | 親指キーに移動 |
| `lang` | 右手 row3[2] | `thumb_r_right` | 親指キーに移動 |
| `lctrl` | 左手 row1[0] | `caps` | row1に変更 |
| `caps` | 左手 row3[0] | `lctrl` | row3に変更 |

## マイグレーション手順

### オプション1: 自動マイグレーション（推奨）

新しいバージョンでは、`cornix decompile`を実行すると自動的に新しい構造で設定ファイルが生成されます。

**手順**:

```bash
# 1. 現在の設定をバックアップ
mv config config.backup_$(date +%Y%m%d_%H%M%S)

# 2. 新しい構造でdecompile
cornix decompile

# 3. 生成された設定を確認
cat config/position_map.yaml

# 4. 検証
cornix validate

# 5. コンパイルテスト
cornix compile

# 6. ラウンドトリップチェック
bin/diff_layouts
```

**期待される結果**:
```
=== ✓ FILES ARE IDENTICAL ===
```

### オプション2: 手動マイグレーション

既存の設定をカスタマイズしている場合や、段階的に移行したい場合は手動でマイグレーションできます。

**手順**:

#### 1. position_map.yamlの更新

```bash
# バックアップ
cp config/position_map.yaml config/position_map.yaml.bak

# ファイルを編集
vim config/position_map.yaml
```

**編集内容**:

1. `left_hand.row3`を6要素から3要素に削減
   ```yaml
   # 変更前
   row3: [caps, fn, option, command, space, esc]

   # 変更後
   row3: [lctrl, option, command]
   ```

2. `right_hand.row3`を6要素から3要素に削減
   ```yaml
   # 変更前
   row3: [enter, raise, lang, left, down, right]

   # 変更後
   row3: [left, down, right]
   ```

3. `thumb_keys`セクションを追加（encodersの前）
   ```yaml
   thumb_keys:
     left: [thumb_l_left, thumb_l_middle, thumb_l_right]
     right: [thumb_r_left, thumb_r_middle, thumb_r_right]
   ```

4. `left_hand.row1[0]`を変更（オプション）
   ```yaml
   # 変更前
   row1: [lctrl, A, S, D, F, G]

   # 変更後
   row1: [caps, A, S, D, F, G]
   ```

#### 2. レイヤーファイルの更新

全てのレイヤーファイル（`config/layers/*.yaml`）を更新し、旧シンボル名を新シンボル名に置換します。

```bash
# 一括置換スクリプト例（実行前に内容を確認してください）
cd config/layers

# 左手親指キー
sed -i '' 's/command:/thumb_l_left:/g' *.yaml
sed -i '' 's/space:/thumb_l_middle:/g' *.yaml
sed -i '' 's/esc:/thumb_l_right:/g' *.yaml

# 右手親指キー
sed -i '' 's/enter:/thumb_r_left:/g' *.yaml
sed -i '' 's/raise:/thumb_r_middle:/g' *.yaml
sed -i '' 's/lang:/thumb_r_right:/g' *.yaml

# row1のlctrl → caps（オプション）
sed -i '' 's/^  lctrl:/  caps:/g' *.yaml
```

**注意**: 上記のsedコマンドはmacOS用です。Linuxの場合は`sed -i`（`''`なし）を使用してください。

#### 3. 手動での確認と調整

自動置換後、各レイヤーファイルを手動で確認し、意図しない置換がないかチェックします：

```bash
# 各ファイルを確認
for file in config/layers/*.yaml; do
  echo "=== $file ==="
  grep -E "(thumb_|caps|lctrl):" "$file"
done
```

#### 4. 検証とテスト

```bash
# 1. 設定を検証
cornix validate

# 2. コンパイル
cornix compile

# 3. ラウンドトリップチェック
bin/diff_layouts
```

## マイグレーション後の確認項目

### 1. Position Map構造の確認

```bash
cat config/position_map.yaml
```

以下を確認：
- ✅ `left_hand.row3`が3要素
- ✅ `right_hand.row3`が3要素
- ✅ `thumb_keys`セクションが存在（encodersの前）
- ✅ 各thumb_keysが3要素ずつ（左右合計6要素）

### 2. レイヤーファイルの確認

```bash
# 旧シンボル名が残っていないか確認
grep -r "command:" config/layers/
grep -r "space:" config/layers/
grep -r "esc:" config/layers/
grep -r "enter:" config/layers/
grep -r "raise:" config/layers/
grep -r "lang:" config/layers/
```

**期待される結果**: マッチなし（空の出力）

### 3. 新シンボル名の確認

```bash
# 新しい親指キーシンボルが使用されているか確認
grep -r "thumb_" config/layers/ | head -10
```

**期待される結果**: 親指キーのマッピングが表示される

### 4. コンパイルと検証

```bash
# Validatorでエラーがないことを確認
cornix validate
# 期待: ✓ All validations passed

# コンパイルが成功することを確認
cornix compile
# 期待: ✓ Compilation completed

# ラウンドトリップが成功することを確認
bin/diff_layouts
# 期待: === ✓ FILES ARE IDENTICAL ===
```

## トラブルシューティング

### エラー: "Unknown position symbol"

**原因**: レイヤーファイルに旧シンボル名が残っている

**解決方法**:
```bash
# エラーメッセージから該当ファイルを確認
cornix validate
# 出力例: Error: Layer 0_layer.yaml: Unknown position symbol 'command'

# 該当ファイルを編集
vim config/layers/0_layer.yaml

# 旧シンボル名を新シンボル名に置換
# command → thumb_l_left
# space → thumb_l_middle
# etc.
```

### エラー: "Duplicate symbol"

**原因**: position_map.yaml内でシンボル名が重複している

**解決方法**:
```bash
# エラーメッセージを確認
cornix validate
# 出力例: Error: position_map.yaml: Duplicate symbol 'lctrl' at: left_hand.row1[0], left_hand.row3[0]

# position_map.yamlを編集し、重複を解消
vim config/position_map.yaml

# 例: row1[0]を 'caps' に変更
```

### コンパイルは成功するがdiff_layoutsが失敗

**原因**: マイグレーションが不完全で、一部のキーマッピングが変更されている

**解決方法**:
```bash
# 詳細な差分を確認
bin/diff_layouts

# 差分がある場合、該当するレイヤーを確認
vim config/layers/{該当レイヤー}.yaml

# または、最初からやり直す
mv config config.failed
mv config.backup_* config
# 再度マイグレーション手順を実行
```

### バックアップから復元したい

```bash
# 最新のバックアップを確認
ls -lt config.backup_* | head -1

# 現在のconfigを削除
rm -rf config

# バックアップから復元
cp -r config.backup_YYYYMMDD_HHMMSS config

# または、自動マイグレーションをやり直す
cornix decompile
```

## よくある質問

### Q1: 既存の設定をそのまま使い続けられますか？

**A**: いいえ。新しいバージョンでは旧形式のposition_map.yamlはサポートされません。マイグレーションが必須です。

### Q2: マイグレーションでキーマッピングは変更されますか？

**A**: いいえ。物理的なキーマッピングは変更されません。シンボル名が変更されるだけです。コンパイル後のlayout.vilは元のファイルと同一になります。

### Q3: カスタマイズしたシンボル名はどうなりますか？

**A**: カスタマイズしたシンボル名は手動で保持する必要があります。自動マイグレーション（オプション1）では標準のシンボル名が使用されます。カスタマイズを維持したい場合は、手動マイグレーション（オプション2）を使用してください。

### Q4: マイグレーション後、古いバージョンで使用できますか？

**A**: いいえ。新しいposition_map.yaml形式は旧バージョンと互換性がありません。必要に応じてバックアップを保持してください。

### Q5: row1とrow3で'lctrl'と'caps'が入れ替わった理由は？

**A**: Cornixキーボードの物理レイアウトに合わせて、より直感的な命名に変更しました：
- row1[0]: 上から2行目の左端（物理的にCapsLockキーの位置）→ `caps`
- row3[0]: 上から4行目の左端（物理的にCtrlキーの位置）→ `lctrl`

## 参考資料

- **開発ガイド**: `.claude/CLAUDE.md` - 実装詳細とアーキテクチャ
- **README**: `README.md` - position_map.yamlの構造と使用方法
- **GitHub Issues**: 問題が解決しない場合は、GitHubでissueを報告してください

## 変更履歴

- **2026-03-09**: 初版作成（v1.0 リリース時）
