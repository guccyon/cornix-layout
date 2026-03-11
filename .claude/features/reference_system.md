# Reference System (Flexible Macro/TapDance/Combo References)

**概要**: マクロ、タップダンス、コンボへの参照を、より読みやすく柔軟な形式でサポート。

#### サポートする3つの参照形式

**1. Name-based（新規、推奨）**
```yaml
# レイヤーファイル内
mapping:
  Q: Macro('End of Line')           # マクロを名前で参照
  W: TapDance('Escape or Layer')    # タップダンスを名前で参照
  E: Combo('Bracket Pair')          # コンボを名前で参照
```

**利点**:
- 可読性が高い（`M3`より`Macro('End of Line')`の方が分かりやすい）
- 意味が明確（何をするマクロかが名前から分かる）
- リネーム自動追従（FileRenamerで名前変更時に自動更新）

**2. Index-based（新規、明示的）**
```yaml
mapping:
  Q: Macro(0)           # マクロをインデックスで参照
  W: TapDance(2)        # タップダンスをインデックスで参照
  E: Combo(1)           # コンボをインデックスで参照
```

**利点**:
- 数値で明示的（0-31の範囲）
- リネーム時に変更されない（安定性重視）
- Validatorでは範囲のみチェック（ファイル存在不要）

**3. Legacy（既存、後方互換）**
```yaml
mapping:
  Q: M0           # レガシーマクロ形式
  W: TD(2)        # レガシータップダンス形式
```

**利点**:
- 既存の設定ファイルがそのまま動作
- QMK標準形式と互換性あり
- 後方互換性維持

#### アーキテクチャ: Parser → Resolver フロー

```
User YAML (3形式いずれか)
    ↓
KeycodeParser.parse()
    ↓ (構造化トークン)
    ↓
ReferenceConverter.resolve()
    ↓ (name/index → QMK)
    ↓
layout.vil (QMK形式: M3, TD(2))
```

**逆方向（Decompile）**:
```
layout.vil (QMK: M3, TD(2))
    ↓
KeycodeParser.parse()
    ↓
ReferenceConverter.reverse_resolve(prefer_name: true)
    ↓ (QMK → name-based)
    ↓
User YAML (name-based形式)
```

#### KeycodeParser の役割

**目的**: 全てのマッピング値の構文を統一的に解析

**パース例**:
```ruby
# Name-based reference
KeycodeParser.parse("Macro('End of Line')")
# => { type: :reference, function: 'Macro', args: [{ type: :string, value: 'End of Line' }] }

# Index-based reference
KeycodeParser.parse("Macro(0)")
# => { type: :reference, function: 'Macro', args: [{ type: :number, value: 0 }] }

# Legacy format
KeycodeParser.parse("M3")
# => { type: :legacy_macro, value: 'M3' }

# Function with nested keycode
KeycodeParser.parse("LT(1, Space)")
# => { type: :function, name: 'LT', args: [...] }
```

**トークンタイプ**:
- `:reference` - Macro(), TapDance(), Combo() 形式
- `:function` - MO(), LSFT(), LT() 等の関数
- `:keycode` - KC_TAB, KC_SPACE 等のQMKキーコード
- `:alias` - Tab, Space 等のエイリアス
- `:legacy_macro` - M0, M15 等
- `:legacy_tap_dance` - TD(0), TD(2) 等
- `:number` - 単独数値（レイヤーインデックス等）
- `:string` - 文字列リテラル

#### ReferenceConverter の役割

**目的**: 参照をname/index↔QMK形式で相互変換

**主要メソッド**:
```ruby
# Forward resolution (Compile時)
@reference_resolver.resolve({
  type: :reference,
  function: 'Macro',
  args: [{ type: :string, value: 'End of Line' }]
})
# => "M5" (nameからindexを検索 → QMK形式)

# Reverse resolution (Decompile時)
@reference_resolver.reverse_resolve("M5", prefer_name: true)
# => { type: :reference, function: 'Macro', args: [{ type: :string, value: 'End of Line' }] }
```

**キャッシング戦略**:
- Lazy loading: 初回参照時にYAMLファイルを読み込み
- メモリフットプリント: ~7 KB (30ファイル × 50 bytes × 3タイプ)
- パフォーマンス: 初回~100ms、以降は即座
- キャッシュクリア: FileRenamer更新後に`clear_cache()`

**双方向マッピング**:
```ruby
# name → index
'End of Line' → 5

# index → QMK
5 → 'M5'

# QMK → index
'M5' → 5

# index → name (prefer_name: true)
5 → 'End of Line'
```

#### Validator での動作

**Name-based参照**: ファイル存在を検証
```yaml
mapping:
  Q: Macro('Unknown')  # ❌ Error: Macro 'Unknown' not found
```

**Index-based参照**: 範囲のみチェック（後方互換性）
```yaml
mapping:
  Q: Macro(0)   # ✓ OK (0-31は常に有効、ファイル不要)
  W: Macro(99)  # ❌ Error: Index 99 out of range (0-31)
```

**Legacy形式**: そのまま許可
```yaml
mapping:
  Q: M0    # ✓ OK (後方互換性)
  W: TD(2) # ✓ OK
```

#### FileRenamer での動作

**自動更新ルール**: Name-based形式のみ更新

```yaml
# マクロファイル: 03_macro.yml
name: OldMacroName  # → NewMacroName に変更

# レイヤーファイル: 0_base.yaml
mapping:
  Q: Macro('OldMacroName')  # ✅ 自動更新 → Macro('NewMacroName')
  W: Macro(3)               # ❌ 変更なし (index-based)
  E: M3                     # ❌ 変更なし (legacy)
```

**設計理由**:
- 予測可能性: Name-basedを選んだユーザーは自動更新を期待
- 安全性: Index/Legacyを使うユーザーは変更を望まない
- ユーザー選択の尊重: 形式選択で動作を制御可能

#### Decompiler のアップグレード動作

**原則**: 常にname-based形式で出力（`prefer_name: true`）

```
layout.vil:     M3, TD(2), COMBO(1)
   ↓
Decompile (prefer_name: true)
   ↓
config YAML:    Macro('End of Line'), TapDance('Escape'), Combo('Bracket')
```

**Generic名の扱い**:
```yaml
# マクロファイルで名前が "Macro 3" の場合
name: Macro 3
# ↓ Decompile結果
mapping:
  Q: Macro('Macro 3')  # ✓ Generic名でも有効
```

#### 使用例

**Case 1: 新規レイヤー作成（Name-based推奨）**
```yaml
# config/layers/5_navigation.yaml
name: Navigation Layer
description: Arrow keys and shortcuts
mapping:
  Q: Macro('Copy Line')          # 分かりやすい
  W: TapDance('Escape or Del')   # 機能が明確
  E: KC_UP
```

**Case 2: 動的な設定（Index-based）**
```yaml
# config/layers/8_dynamic.yaml
name: Dynamic Layer
mapping:
  Q: Macro(0)    # ファイル未作成でもOK
  W: Macro(1)    # 後でファイル追加予定
  E: Macro(2)
```

**Case 3: 既存設定の互換性（Legacy）**
```yaml
# config/layers/9_legacy.yaml
name: Legacy Layer
mapping:
  Q: M0     # 既存の設定そのまま
  W: TD(2)  # 動作保証
```

#### ベストプラクティス

**推奨**: Name-based形式を使用
- 可読性が高い
- FileRenamer自動更新の恩恵
- チーム開発で分かりやすい

**Index-based使用ケース**:
- プログラム生成の設定
- 頻繁に変更されるマクロ
- リネーム自動追従が不要な場合

**Legacy使用ケース**:
- 既存の設定を維持
- QMK標準との互換性重視

#### Migration Guide（オプション）

**既存設定の移行は不要**: 全形式が完全にサポートされ、後方互換性が保証されています。

**Option 1: 何もしない（デフォルト）**
```yaml
# 既存のレガシー形式はそのまま動作
mapping:
  Q: M0
  W: TD(2)
```
動作保証され、コンパイル・デコンパイル可能。

**Option 2: 段階的移行**
```yaml
# 新しいレイヤーでname-based使用
# 既存レイヤーはlegacy維持
mapping:
  Q: Macro('New Macro')  # 新規
  W: M0                  # 既存（そのまま）
```
両形式の混在可能。

**Option 3: 完全移行（オプション）**
```bash
# 1. バックアップ
mv config config.backup

# 2. Decompile（自動的にname-basedに変換）
ruby bin/decompile

# 3. 変更確認
git diff config/

# 4. コンパイルテスト
ruby bin/compile
ruby bin/diff_layouts  # 動作確認
```

Decompilerは自動的にlegacy → name-based変換を行います。

#### よくある質問

**Q1: Name-basedとIndex-basedの使い分けは？**
A: 基本的にName-basedを推奨。可読性が高く、FileRenamerでの自動更新も効きます。Index-basedは動的生成やリネーム不要な場合に使用。

**Q2: Legacy形式は使い続けられる？**
A: はい。完全に後方互換性があり、今後もサポートされます。

**Q3: Decompile後にlegacy形式が消える？**
A: はい。Decompilerは常にname-based形式で出力します（より読みやすいため）。元に戻す必要があればバックアップから復元してください。

**Q4: FileRenamerで名前変更時、Index-based参照は更新される？**
A: いいえ。Name-based参照のみ自動更新されます。これは意図的な設計です（予測可能性と安全性のため）。

