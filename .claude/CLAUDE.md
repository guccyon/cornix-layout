# Cornix Keyboard Layout Manager - Development Guide

## Recent Changes

### v2.0 - 階層化レイヤーYAML構造への移行 (2026-03-10)

**Breaking Change**: レイヤーYAMLファイルとposition_mapの構造が階層化されました。

**主な変更**:
1. **シンボル名の簡略化**
   - 親指キー: `l_thumb_left` → `left`, `r_thumb_middle` → `middle`
   - エンコーダー: `l_rotary_push` → `push`, `r_rotary_ccw` → `ccw`

2. **階層パスによる一意性保証**
   - 例：`left_hand.thumb_keys.left`, `encoders.left.push`
   - 冗長なプレフィックス（`l_`, `r_`）が不要になりました

3. **レイヤーファイルの階層構造**
   ```yaml
   # Before (v1.x)
   mapping:
     l_thumb_left: Space
     r_rotary_push: KC_MUTE

   # After (v2.0)
   mapping:
     left_hand:
       thumb_keys:
         left: Space
     encoders:
       right:
         push: KC_MUTE
   ```

4. **影響範囲**
   - 全コアファイル: compiler.rb, decompiler.rb, position_map.rb, validator.rb
   - 全テストスイート: 493テスト対応完了
   - Round-trip check: 完全互換性維持

**Migration**: 既存の設定は`cornix decompile`で自動的に新形式に変換されます。

---

## Development Instructions

**重要**: 作業完了時には、得られた知見やシステムのコンテキストを必ず `.claude/` ディレクトリに記録すること。
- 新しい実装パターンの発見
- よくある間違いとその解決方法
- システムの制約や設計上の重要な決定事項
- ドキュメント更新: `README.md` と `README.en.md` は**常に一緒に更新**すること
- プロンプト及び計画、作業結果の報告は全て日本語で行うこと

## Project Overview

CornixキーボードのVial `layout.vil`ファイルとYAML設定ファイル間の双方向変換ツール。

## Architecture

### Core Components

1. **Compiler** (`lib/cornix/compiler.rb`)
   - YAML設定 → layout.vil に変換
   - `KeycodeParser`で構文解析 → `ReferenceResolver`/`KeycodeResolver`で解決
   - `resolve_to_qmk()`メソッドで再帰的にQMK形式に変換
   - **重要**: layout.vilには必ずQMKキーコード（`KC_*`形式）を出力（Vial互換性のため）
   - **関数引数の処理**:
     - レイヤー切り替え系（MO, TO, OSL, TG, TT, DF, LT, TD, COMBO）: 数値引数をそのまま保持（例: `MO(3)` → `MO(3)`）
     - 修飾キー系（LSFT, LCTL, LGUI_T等）: 数値を`KC_*`に変換（例: `LSFT(1)` → `LSFT(KC_1)`）
   - **参照形式サポート**: Name-based (`Macro('name')`), Index-based (`Macro(3)`), Legacy (`M3`)
   - `lib/cornix/keycode_aliases.yaml`を直接参照（config/からは読まない）

2. **Decompiler** (`lib/cornix/decompiler.rb`)
   - layout.vil → YAML設定に変換
   - `KeycodeParser`で構文解析 → `ReferenceResolver`/`KeycodeResolver`で逆解決
   - `resolve_to_alias()`メソッドで再帰的にエイリアス化（関数内部の引数も変換）
   - 生成されるYAMLファイルは読みやすいエイリアス形式（例: `Tab`, `Trans`, `LSFT(1)`）
   - **参照形式アップグレード**: レガシー形式（`M3`, `TD(2)`）を自動的にname-based（`Macro('name')`, `TapDance('name')`）にアップグレード
   - `config/`ディレクトリに各種YAMLファイルを生成
   - **重要**: `keycode_aliases.yaml`はコピーしない（システムファイルとして`lib/cornix/`に固定配置）
   - **NEW (2026-03-09)**: `minimize_quotes()` - YAML仕様上不要なダブルクォートを削除
     - YAMLの特殊文字（`-`, `:`, `,`, `;`, `#`, `@`, `&`, `*` 等）を正確に検出
     - 予約語（`true`, `false`, `null`, `yes`, `no`）はクォート保持
     - 数値に見える文字列もクォート保持
     - エスケープシーケンス（`\`）を含む文字列はクォート保持

3. **KeycodeParser** (`lib/cornix/keycode_parser.rb`) - **NEW**
   - マッピング値の構文解析を担当
   - 全てのキーコード構文を構造化トークンに変換
   - **主な機能**:
     - `parse()`: 文字列 → 構造化トークン（例: `Macro('name')` → `{type: :reference, function: 'Macro', args: [...]}`）
     - `unparse()`: 構造化トークン → 文字列（逆変換）
     - `token_type()`: トークンタイプの識別
   - **トークンタイプ**: `:reference`, `:function`, `:keycode`, `:alias`, `:legacy_macro`, `:legacy_tap_dance`, `:number`, `:string`
   - **アーキテクチャ**:
     ```
     Compiler/Decompiler/Validator/FileRenamer
       ↓
     KeycodeParser (構文解析)
       ↓
       ├─ ReferenceResolver (マクロ/タップダンス/コンボ参照)
       ├─ KeycodeResolver (エイリアス)
       └─ [Future: ModifierResolver]
     ```
   - **将来の拡張性**: モディファイア構文の追加が容易

4. **ReferenceResolver** (`lib/cornix/reference_resolver.rb`) - **NEW**
   - マクロ/タップダンス/コンボ参照の解決を担当
   - **主な機能**:
     - `resolve()`: 参照 → QMK形式（例: `Macro('name')` → `M3`, `TapDance('name')` → `TD(2)`）
     - `reverse_resolve()`: QMK形式 → 参照（例: `M3` → `Macro('name')`、prefer_name: true でname-based優先）
     - `validate_reference()`: 参照の存在確認
     - `clear_cache()`: キャッシュクリア（FileRenamer更新後）
   - **Lazy Loading**: 初回参照時にYAMLファイルを読み込み、以降はキャッシュ
   - **双方向マッピング**: name↔index↔QMK形式の相互変換
   - **サポート形式**:
     - Name-based: `Macro('End of Line')`, `TapDance('Escape')`
     - Index-based: `Macro(3)`, `TapDance(2)`
     - Legacy: `M3`, `TD(2)` (backward compatible)

5. **KeycodeResolver** (`lib/cornix/keycode_resolver.rb`)
   - キーコードエイリアスの解決を担当
   - `resolve()`: エイリアス → QMKキーコード（**Compilerで使用**）
   - `reverse_resolve()`: QMKキーコード → エイリアス（**Decompilerで使用**）
   - **定義順優先**: 複数のエイリアスがある場合、YAMLの定義順で最初のものを返す
     - 例: `Trans`, `Transparent`, `___` → `Trans`が優先（最初に定義）
     - ユーザーは`keycode_aliases.yaml`の定義順序で優先順位を制御可能

6. **FileRenamer** (`lib/cornix/file_renamer.rb`)
   - 設定ファイル（マクロ、タップダンス、レイヤー）のリネーム機能
   - **主な機能**:
     - インデックスプレフィックス保持（`03_macro.yml` → `03_end_of_line.yml`）
     - YAML内容更新（`name`, `description`フィールド）
     - 自動バックアップ＆ロールバック（`config.backup_<timestamp>/`）
     - コンパイル検証（リネーム後に`Compiler`で妥当性確認）
     - トランザクション型バッチ処理（全成功 or 全ロールバック）
     - **レイヤー参照の自動更新**（name-based形式のみ）
   - **CLI**: `bin/rename_file` - 単一ファイル/バッチモードサポート
   - **統合**: `bin/cornix rename` - インタラクティブなリネームコマンド

7. **RenameCommand** (`lib/cornix/rename_command.rb`)
   - `cornix rename`コマンドの実装（NEW）
   - **一連のシーケンス**:
     1. リネーム前のコンパイル（ベースライン作成）
     2. LLM推論によるリネームプラン作成（パターンマッチング）
     3. インタラクティブなユーザー確認（y/n/edit）
     4. FileRenamerによるリネーム実行
     5. コンパイル検証（diff_layoutsで構造比較）
     6. 一時ファイルクリーンアップ
   - **パターン検出**: brackets, curly braces, copy等を自動検出
   - **信頼度レベル**: high/medium/low で提案の確度を表示

8. **CliHelpers** (`lib/cornix/cli_helpers.rb`) - **NEW**
   - 全てのCLIサブコマンドで共有されるユーティリティ関数
   - **主な機能**:
     - `check_config_lock()`: config/ディレクトリの既存ファイル保護
     - `ensure_config_exists()`: config/ディレクトリの存在確認
     - `cleanup()`: 生成ファイルの安全な削除

### bin/ Directory Architecture

**Overview**: Refactored for maintainability with clean separation of concerns.

**Structure**:
- `bin/cornix` - Main CLI dispatcher (lightweight, ~62 lines)
- `bin/subcommands/` - All subcommand implementations
- `lib/cornix/cli_helpers.rb` - Shared CLI utilities

**Key Features**:
- **Auto-validation**: `cornix compile` automatically runs validation before compiling
- **Delegation Pattern**: `bin/cornix` uses `load` to execute subcommands
- **Code Deduplication**: Eliminated 100% duplication, all commands go through `cornix` dispatcher

**Delegation Pattern**:
```ruby
case command
when 'compile'
  load File.expand_path('subcommands/compile.rb', __dir__)
end
```

**Subcommands**:
- `compile.rb`: Auto-validates then compiles YAML → layout.vil
- `decompile.rb`: Decompiles layout.vil → YAML with lock protection
- `validate.rb`: Validates YAML configuration files
- `cleanup.rb`: Safely removes generated files
- `rename.rb`: RenameCommand wrapper

### Directory Structure

```
cornix/
├── bin/
│   ├── cornix              # Main CLI dispatcher (~62 lines)
│   ├── subcommands/        # Subcommand implementations
│   │   ├── compile.rb      # Compile with auto-validation
│   │   ├── decompile.rb    # Decompile with lock protection
│   │   ├── validate.rb     # Validation-only
│   │   ├── cleanup.rb      # Safe cleanup
│   │   └── rename.rb       # RenameCommand wrapper
│   ├── diff_layouts        # Round-trip check tool
│   └── rename_file         # File renamer CLI (advanced)
├── lib/cornix/
│   ├── compiler.rb
│   ├── decompiler.rb
│   ├── keycode_resolver.rb
│   ├── file_renamer.rb
│   ├── rename_command.rb
│   ├── cli_helpers.rb              # Shared CLI utilities (NEW)
│   ├── keycode_aliases.yaml
│   ├── position_map.yaml
│   ├── position_map.rb
│   └── validator.rb
├── spec/                             # RSpec test suite
│   ├── compiler_spec.rb             # 30 tests
│   ├── decompiler_spec.rb           # 27 tests
│   ├── keycode_resolver_spec.rb     # 21 tests
│   ├── position_map_spec.rb         # 17 tests
│   ├── validator_spec.rb            # 63 tests
│   ├── file_renamer_spec.rb         # 44 tests (NEW)
│   └── integration_spec.rb          # 6 tests
├── .claude/
│   └── skills/
│       └── rename.clmd              # Rename skill (NEW)
├── config/                          # User configuration (generated by decompile)
│   ├── metadata.yaml
│   ├── position_map.yaml
│   ├── settings/qmk_settings.yaml
│   ├── layers/*.yaml
│   ├── macros/*.yaml
│   ├── tap_dance/*.yaml
│   └── combos/*.yaml
├── tmp/
│   ├── layout.vil                   # Original file for testing
│   └── rename_plans.json            # Rename plans (NEW)
└── layout.vil                       # Generated file by compile
```

## Key Design Decisions

### 0. Alias System Implementation (Critical)

**アーキテクチャ**:
- Decompiler: QMK → Alias 変換（`resolve_to_alias()`）
- Compiler: Alias → QMK 変換（`resolve_to_qmk()`）
- layout.vil: **必ずQMK形式**（Vial互換性のため）
- YAML設定: エイリアス形式（可読性のため）

**関数引数の処理ルール**（重要）:
```ruby
# compiler.rb の resolve_to_qmk() より
if arg.match?(/^\d+$/)
  # レイヤー切り替え・タップダンス・コンボの場合、数値をそのまま保持
  if function_name.match?(/^(MO|TO|OSL|TG|TT|DF|LT\d*|TD|COMBO)$/)
    arg  # 例: MO(3) → MO(3)
  else
    "KC_#{arg}"  # 例: LSFT(1) → LSFT(KC_1)
  end
else
  resolve_to_qmk(arg)  # 再帰的に解決
end
```

**よくある間違い**:
1. ❌ `MO(3)` を `MO(KC_3)` に変換してしまう
   - ✅ レイヤー番号は数値のまま保持
2. ❌ `LSFT(1)` を `LSFT(1)` のままにする
   - ✅ 修飾キー関数の数値引数は `LSFT(KC_1)` に変換
3. ❌ `TD(2)` を `TD(KC_2)` に変換してしまう
   - ✅ タップダンスインデックスは数値のまま保持

### 0.5. Reference System (Flexible Macro/TapDance/Combo References)

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
ReferenceResolver.resolve()
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
ReferenceResolver.reverse_resolve(prefer_name: true)
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

#### ReferenceResolver の役割

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

### 0.6. Modifier Expression System (VS Code風修飾キー表現)

**概要**: VS CodeやIDEのような読みやすい修飾キー表現（例: `Cmd + Q`）をサポート。自動的にQMK形式（`LGUI(KC_Q)`）にコンパイルし、QMKショートカット（LSG、MEH、HYPR等）を自動検出。

#### アーキテクチャ

**アプローチ**: KeycodeParserに新しいパターン検出を追加（新しいResolverは作らない）。

**理由**:
- KeycodeParserが既に全ての構文解析を集約している
- 修飾キー表現は構文糖衣であり、セマンティック参照（Macro/TapDance）ではない
- 既存のparser-firstアーキテクチャに適合: parse() → resolve() → QMK

**データフロー**:
```
ユーザー入力: "Cmd + Q"
    ↓
KeycodeParser.parse() → { type: :modifier_expression, modifiers: ['Cmd'], key: 'Q' }
    ↓
ModifierExpressionCompiler.to_qmk() → "LGUI(KC_Q)"
    ↓
layout.vil (QMK形式)
    ↓ (decompile - 変換しない)
LGUI(KC_Q) → LGUI(Q) (標準decompile)
```

**コンポーネント**:
1. **KeycodeParser**（修正） - パターン検出、parse/unparseロジック追加（+60行）
2. **ModifierExpressionCompiler**（新規） - トークン → QMKショートカット/ネスト関数に変換（~200行）
3. **Compiler**（修正） - 1行のcase追加で統合（+4行）
4. **Validator**（修正） - 修飾キー名とキーの検証追加（+16行）

#### サポート形式

**基本構文**:
```yaml
Cmd + Q               # → LGUI(KC_Q)
Shift + Cmd + Q       # → LSG(KC_Q)
Ctrl + Shift + Alt + Q # → MEH(KC_Q)
```

**特徴**:
- 順序無関係: `Cmd + Shift` = `Shift + Cmd` → `LSG`
- 柔軟なスペース: `Cmd+Q` = `Cmd + Q` = `Cmd  +  Q`
- プラットフォーム対応: `Command`, `Win`, `Option`, `Ctrl`すべてサポート
- **クォート柔軟性**: `Cmd + ]` = `Cmd + "]"` （両方サポート、unparseは常にクォート無し）

#### QMK修飾キーショートカットマップ

**単一修飾キー（左）**: LCTL, LSFT, LALT, LGUI
**単一修飾キー（右）**: RCTL, RSFT, RALT, RGUI

**2修飾キー組み合わせ（左）**:
- LCS (Ctrl+Shift)
- LCA (Ctrl+Alt)
- LCG (Ctrl+GUI)
- LSA (Shift+Alt)
- LSG (Shift+GUI)
- LAG (Alt+GUI)

**2修飾キー組み合わせ（右）**: RCS, RCA, RCG, RSA, RSG, RAG

**3修飾キー組み合わせ（左）**:
- MEH (Ctrl+Shift+Alt)
- LCSG (Ctrl+Shift+GUI)
- LCAG (Ctrl+Alt+GUI)
- LSAG (Shift+Alt+GUI)

**3修飾キー組み合わせ（右）**: RCSG, RCAG, RSAG

**特殊組み合わせ**:
- MEH (Ctrl+Shift+Alt) - 左右同じ名前
- HYPR (Ctrl+Shift+Alt+GUI) - 4修飾キー

#### 変換アルゴリズム

**ステップ1: 式のパース**
```ruby
# Pattern: /^(\w+)(\s*\+\s*(?:\w+|"[^"]*"|'[^']*'|[^\s+]))+$/
# クォート付き・クォート無しの両方をサポート
"Cmd + Shift + Q" → { type: :modifier_expression, modifiers: ['Cmd', 'Shift'], key: 'Q' }
"Cmd + ]" → { type: :modifier_expression, modifiers: ['Cmd'], key: ']' }
"Cmd + \"]\"" → { type: :modifier_expression, modifiers: ['Cmd'], key: ']' }  # クォート除去
```

**ステップ2: 修飾キーの解決**
```ruby
['Cmd', 'Shift'] → ['LGUI', 'LSFT']
```

**ステップ3: QMKショートカット検出**
```ruby
# 順序無関係（ソート後に検索）
['LGUI', 'LSFT'] → sort → ['LGUI', 'LSFT'] → SHORTCUTS lookup → 'LSG'
```

**ステップ4: ネスト関数へのフォールバック**
```ruby
# ショートカットが存在しない場合
modifiers: ['LGUI', 'LALT'], key: 'Space'
→ LGUI(LALT(KC_SPACE))  # 最初の修飾キー = 最外部
```

**ステップ5: キーの解決**
```ruby
# KeycodeResolverに委譲
'Q' → 'KC_Q'
'Space' → 'KC_SPACE'
'KC_ENTER' → 'KC_ENTER'（既にQMK形式）
```

#### 修飾キーエイリアス定義

**左側（L/R省略時のデフォルト）**:
- `Shift` → LSFT
- `Ctrl`, `Control` → LCTL
- `Alt`, `Option` → LALT
- `Cmd`, `Command`, `Win`, `Gui` → LGUI

**右側（R接頭辞を明示）**:
- `RShift` → RSFT
- `RCtrl`, `RControl` → RCTL
- `RAlt`, `ROption` → RALT
- `RCmd`, `RCommand`, `RWin`, `RGui` → RGUI

#### 実装詳細

**KeycodeParser変更**（lib/cornix/keycode_parser.rb, +60行）:
```ruby
# Pattern 3: Modifier expressions - Cmd + Q, Shift + Ctrl + A
if keycode_str.match?(/^(\w+)(\s*\+\s*\w+)+$/)
  return parse_modifier_expression(keycode_str)
end

def self.parse_modifier_expression(expr)
  parts = expr.split(/\s*\+\s*/).map(&:strip)
  modifiers = parts[0..-2]
  key = parts[-1]
  { type: :modifier_expression, modifiers: modifiers, key: key }
end
```

**ModifierExpressionCompiler**（lib/cornix/modifier_expression_compiler.rb, ~200行）:
```ruby
SHORTCUTS = {
  ['LALT', 'LCTL', 'LGUI', 'LSFT'] => 'HYPR',
  ['LALT', 'LCTL', 'LSFT'] => 'MEH',
  ['LCTL', 'LGUI', 'LSFT'] => 'LCSG',
  # ... 20+ shortcuts
}.freeze

MODIFIER_TO_FUNCTION = {
  'Shift' => 'LSFT', 'Cmd' => 'LGUI', 'Command' => 'LGUI',
  # ... all modifier aliases
}.freeze

def self.to_qmk(token, keycode_resolver)
  mod_functions = token[:modifiers].map { |m| resolve_modifier(m) }
  resolved_key = resolve_key(token[:key], keycode_resolver)
  shortcut = find_shortcut(mod_functions)
  shortcut ? "#{shortcut}(#{resolved_key})" : nest_modifiers(mod_functions, resolved_key)
end

def self.find_shortcut(mod_functions)
  sorted_mods = mod_functions.sort
  SHORTCUTS[sorted_mods]
end
```

**Compiler統合**（lib/cornix/compiler.rb, +4行）:
```ruby
when :modifier_expression
  ModifierExpressionCompiler.to_qmk(parsed, @keycode_resolver)
```

**Validator統合**（lib/cornix/validator.rb, +16行）:
```ruby
when :modifier_expression
  parsed[:modifiers].each do |mod|
    unless valid_modifier?(mod)
      @errors << "Invalid modifier name: #{mod} in expression '#{keycode}'"
      return false
    end
  end
  return valid_simple_keycode?(parsed[:key])

def valid_modifier?(modifier)
  Cornix::ModifierExpressionCompiler::MODIFIER_TO_FUNCTION.key?(modifier)
end
```

#### テストカバレッジ

**新規テスト**: 合計79テスト（全479テスト中）
- KeycodeParser: +21テスト（修飾キー表現パース、unparse、round-trip）
- ModifierExpressionCompiler: 52テスト（全機能カバレッジ）
  - シンプル式、2/3/4修飾キー、QMKショートカット全組み合わせ
  - 順序無関係、修飾キーエイリアス、キー解決
  - エラーハンドリング
- Compiler統合: +8テスト
- Validator統合: +8テスト
- Integration: +2テスト（round-trip、QMK形式保持）

**実行結果**: 全479テスト成功（0 failures）

#### よくある使用例

**アプリケーション操作**:
```yaml
Q: Cmd + Q          # アプリ終了
W: Cmd + W          # ウィンドウを閉じる
T: Cmd + T          # 新規タブ
```

**エディタショートカット**:
```yaml
C: Cmd + C          # コピー
V: Cmd + V          # ペースト
S: Cmd + S          # 保存
F: Ctrl + Shift + F # プロジェクト検索 → LCS(KC_F)
```

**ウィンドウ管理**:
```yaml
Left: Ctrl + Shift + Alt + Left   # MEH(KC_LEFT)
Right: Ctrl + Shift + Alt + Right # MEH(KC_RIGHT)
```

#### よくある間違い

1. ❌ プラス記号をキーとして使用
   - `Shift + +` は構文解析できない
   - ✅ `LSFT(KC_PLUS)` または `Plus`エイリアス使用

2. ❌ 関数をキーとして使用
   - `Cmd + LT(1, Space)` は構文解析できない
   - ✅ `LGUI(LT(1, Space))` QMK構文で記述

3. ❌ Decompile後に修飾キー表現に戻ると期待
   - Decompilerは QMK形式を保持（`LGUI(Q)`）
   - ✅ 意図的な設計（QMK関数は様々な方法で記述可能なため）

4. ❌ 修飾キー表現とQMK構文を混同
   - `Cmd + Q` は YAML専用（ユーザー入力）
   - layout.vilには必ず`LGUI(KC_Q)`形式（QMK標準）

#### Decompile動作の理由

**原則**: Decompilerは修飾キー表現に自動変換しない（QMK形式を保持）

**理由**:
1. **曖昧性**: QMK関数は様々な方法で記述可能
   - `LGUI(KC_Q)` = `Cmd + Q` = `LGUI_T(KC_Q)`?
   - 元の意図を正確に復元できない

2. **情報損失**: layout.vilにはQMK形式のみ（修飾キー表現は含まれない）
   - Compile: `Cmd + Q` → `LGUI(KC_Q)` (OK)
   - Decompile: `LGUI(KC_Q)` → `?` (どちらに戻すべき？)

3. **ユーザー選択の尊重**: 修飾キー表現を使うかはユーザーの選択
   - 明示的に記述した場合のみ維持
   - 既存のQMK構文を勝手に変換しない

#### Round-trip Check

**期待動作**:
```bash
# 1. 修飾キー表現を含むYAML作成
cat > config/layers/0_base.yaml <<EOF
mapping:
  Q: Cmd + Q
EOF

# 2. Compile
ruby bin/compile  # → layout.vilに LGUI(KC_Q)

# 3. Decompile
mv config config.backup
ruby bin/decompile  # → config/layers/*.yamlに LGUI(Q)

# 4. Recompile
ruby bin/compile

# 5. 検証
ruby bin/diff_layouts  # ✓ FILES ARE IDENTICAL
```

**重要**: 修飾キー表現は元に戻らないが、QMK形式は完全に一致する。

#### 制限事項とエスケープハッチ

**制限事項**:
1. プラス記号をキーとして使用不可: `Shift + +`
2. 関数をキーとして使用不可: `Cmd + LT(1, Space)`
3. パターンは単語文字のみ: `/^(\w+)(\s*\+\s*\w+)+$/`

**エスケープハッチ**: QMK構文を直接記述
```yaml
Q: LGUI(KC_PLUS)         # プラス記号
W: LGUI(LT(1, Space))    # ネストした関数
E: Cmd + Q               # 修飾キー表現（推奨）
```

### 1. keycode_aliases.yaml の配置

**配置場所**: `lib/cornix/keycode_aliases.yaml`

**理由**:
- システムが提供する参照ファイル（ユーザー編集対象外）
- QMK公式ドキュメント（https://docs.qmk.fm/keycodes）に基づく包括的な定義
- `config/`には生成しない（ユーザー設定と混在させない）

**内容**:
- Basic Keycodes: 文字、数字、記号、ファンクションキー、ナビゲーション、修飾キー
- Layer Switching: MO(), DF(), TG(), TO(), TT(), OSL(), LT()
- Modifiers: Mod-Tap (MT, LCTL_T, etc.), One Shot Modifiers (OSM), 修飾キー組み合わせ
- Media Keys, Mouse Keys, Backlight/RGB, Quantum Keys
- 合計337行

### 2. Position Map Template

**配置場所**: `lib/cornix/position_map.yaml`

**理由**:
- システムが提供するデフォルトテンプレート（Cornixの標準レイアウト）
- ユーザーは`config/position_map.yaml`でシンボル名をカスタマイズ可能
- Decompilerはテンプレートから生成（`layout.vil`の実データではない）

**構造（v2.0以降）**:
```yaml
left_hand:
  row0: [tab, Q, W, E, R, T]           # 6要素
  row1: [caps, A, S, D, F, G]          # 6要素
  row2: [lshift, Z, X, C, V, B]        # 6要素
  row3: [lctrl, command, option]       # 3要素（標準グリッドキーのみ）
  thumb_keys: [left, middle, right]    # 簡略化されたシンボル名
right_hand:
  row0: [Y, U, I, O, P, backspace]     # 6要素
  row1: [H, J, K, L, colon, enter]     # 6要素
  row2: [N, M, comma, dot, up, rshift] # 6要素
  row3: [left, down, right]            # 3要素（標準グリッドキーのみ）
  thumb_keys: [left, middle, right]    # 簡略化されたシンボル名
encoders:
  left:
    push: push     # 簡略化されたシンボル名
    ccw: ccw
    cw: cw
  right:
    push: push
    ccw: ccw
    cw: cw
```

**重要な変更（v2.0）**:
- シンボル名の簡略化：`l_thumb_left` → `left`, `l_rotary_push` → `push`
- 階層パスによる一意性保証：`left_hand.thumb_keys.left`, `encoders.left.push`
- 冗長なプレフィックス（`l_`, `r_`）が不要になりました

**設計理由**:
- 親指キーは物理的にキーボードの一部であり、左手・右手それぞれのセクション内に配置
- row3の直後に配置することで、物理的な配置と構造が一致
- エンコーダーは明確にキーと異なる位置にあるため、別グループで維持
- 階層構造により、同じシンボル名（`left`, `push`等）を異なるコンテキストで再利用可能


**ハードウェアマッピング**:

**親指キーの配置** (重要):
- 親指キーは論理的には left_hand/right_hand 内の thumb_keys として定義
- 物理的には Row 3 の Cols 3-5 に配置（標準グリッドキーの右側）

**左手（Row 0-3）**:
- Row 0-2: Cols 0-5（標準6要素、逆順なし）
- Row 3, Cols 0-2: 標準グリッドキー（`lctrl`, `command`, `option`）
- Row 3, Cols 3-5: 親指キー（順序通り）
  - Col 3: `left` (v2.0: 旧`l_thumb_left`)
  - Col 4: `middle` (v2.0: 旧`l_thumb_middle`)
  - Col 5: `right` (v2.0: 旧`l_thumb_right`)

**右手（Row 4-7、ハードウェアではRow 0-3に対応）**:
- Row 0-2: Cols 0-5（標準6要素、**逆順処理あり**: `5 - col_idx`）
- Row 3, Cols 0-2: 標準グリッドキー（**逆順処理あり**: `2 - col_idx`）
  - Col 0: `right` (position_map順序: left → down → right)
  - Col 1: `down`
  - Col 2: `left`
- Row 3, Cols 3-5: 親指キー（**逆順処理あり**: `5 - col_idx`）
  - Col 5: `left` (v2.0: 旧`r_thumb_left`)
  - Col 4: `middle` (v2.0: 旧`r_thumb_middle`)
  - Col 3: `right` (v2.0: 旧`r_thumb_right`)

**重要**: 右手は全行で逆順処理が適用されます。これはCornixキーボードのハードウェア特性です。

**動作フロー**:
1. Decompiler起動時: `lib/cornix/position_map.yaml`を`@position_map_template`に読み込み
2. `extract_position_map()`: テンプレートから`config/position_map.yaml`を生成
3. Compiler: `config/position_map.yaml`（ユーザー版）を読み込み

**keycode_aliases.yamlとの違い**:
| ファイル | 性質 | config/への配置 | ユーザー編集 |
|---------|------|----------------|------------|
| keycode_aliases.yaml | QMK標準定義 | コピーしない | 不要 |
| position_map.yaml | ハードウェア固有 | 生成する | 可能 |

**実装詳細**:
```ruby
# lib/cornix/decompiler.rb
def initialize(vil_path)
  # Position Mapテンプレートを読み込み
  @position_map_template_path = File.join(__dir__, 'position_map.yaml')
  unless File.exist?(@position_map_template_path)
    raise "Missing required template: #{@position_map_template_path}"
  end
  @position_map_template = YAML.load_file(@position_map_template_path)
end

def extract_position_map(output_dir)
  # テンプレートから生成（再構築不要）
  write_yaml_with_flow_arrays("#{output_dir}/position_map.yaml", @position_map_template)
end

def extract_base_layer(dir, layer_data, encoder_data)
  # 左手（Row 0-3）
  ['row0', 'row1', 'row2', 'row3'].each_with_index do |row_key, row_idx|
    row = @position_map_template['left_hand'][row_key]
    row.each_with_index do |symbol, col_idx|
      keycode = layer_data[row_idx][col_idx]
      mapping[symbol] = resolve_to_alias(keycode) unless keycode == -1
    end
  end

  # 右手（Row 0-3、逆順処理あり）
  ['row0', 'row1', 'row2', 'row3'].each_with_index do |row_key, row_idx|
    row = @position_map_template['right_hand'][row_key]
    row.each_with_index do |symbol, col_idx|
      # 全行で逆順: (row.size - 1) - col_idx
      hardware_col_idx = (row.size - 1) - col_idx
      keycode = layer_data[row_idx + 4][hardware_col_idx]
      mapping[symbol] = resolve_to_alias(keycode) unless keycode == -1
    end
  end

  # エンコーダー（階層構造で参照）
  # v2.0以降: 階層パスで参照（encoders.left.push, encoders.right.cw等）
  mapping['l_rotary_push'] = resolve_to_alias(layer_data[2][6])
  mapping['l_rotary_ccw'] = resolve_to_alias(encoder_data[0][0])
  mapping['l_rotary_cw'] = resolve_to_alias(encoder_data[0][1])
  mapping['r_rotary_push'] = resolve_to_alias(layer_data[5][6])
  mapping['r_rotary_ccw'] = resolve_to_alias(encoder_data[1][0])
  mapping['r_rotary_cw'] = resolve_to_alias(encoder_data[1][1])

  # 親指キー（left_hand/right_hand内のthumb_keysとして処理）
  # v2.0以降: シンボル名は簡略化（left, middle, right）、階層パスで一意性保証
  # 左手親指キー（Row 3, Cols 3-5、順序通り）
  @position_map_template['left_hand']['thumb_keys'].each_with_index do |symbol, idx|
    col_idx = 3 + idx
    keycode = layer_data[3][col_idx]
    mapping[symbol] = resolve_to_alias(keycode) unless keycode == -1
  end

  # 右手親指キー（Row 7, Cols 3-5、逆順）
  @position_map_template['right_hand']['thumb_keys'].each_with_index do |symbol, idx|
    col_idx = 5 - idx  # 逆順: 5, 4, 3
    keycode = layer_data[7][col_idx]
    mapping[symbol] = resolve_to_alias(keycode) unless keycode == -1
  end
end

def extract_override_layer(dir, index, layer_data, encoder_data)
  # エンコーダープッシュボタンの差分も検出（重要）
  # v2.0以降: 階層構造のYAMLファイルに出力
  l_push_keycode = layer_data[2][6]
  l_push_base = base_layer[2][6]
  if l_push_keycode != l_push_base && l_push_keycode != -1
    overrides['l_rotary_push'] = resolve_to_alias(l_push_keycode)
  end

  r_push_keycode = layer_data[5][6]
  r_push_base = base_layer[5][6]
  if r_push_keycode != r_push_base && r_push_keycode != -1
    overrides['r_rotary_push'] = resolve_to_alias(r_push_keycode)
  end

  # 親指キーの差分は detect_left_hand_diff() / detect_right_hand_diff() で統合的に処理
  # （thumb_keysは left_hand/right_hand 内の一部として検出される）
end
```

**POSITION_MAP定数削除**:
- 旧: decompiler.rb 11-24行目にハードコード
- 新: 外部YAMLファイルから動的ロード
- メリット: メンテナンス性向上、変更履歴追跡可能

**右手の逆順処理**:
- row0-2（6要素）: `5 - col_idx`（例: col 0 → hardware col 5）
- row3（3要素）: `2 - col_idx`（例: col 0 → hardware col 2）
- 親指キー: `5 - idx`（例: idx 0 → col 5）
- 理由: Cornixキーボードのハードウェア特性（右手側は物理的に右から左にインデックスが振られている）

### 3. Compiler の参照パス

```ruby
# lib/cornix/compiler.rb
def initialize(config_dir)
  @config_dir = config_dir
  # lib/cornix/keycode_aliases.yaml を直接参照
  aliases_path = File.join(__dir__, 'keycode_aliases.yaml')
  @keycode_resolver = KeycodeResolver.new(aliases_path)
  @position_map = PositionMap.new("#{config_dir}/position_map.yaml")
end
```

**ポイント**:
- `__dir__`は現在のRubyファイルのディレクトリ（`lib/cornix/`）
- config/ではなくlib/cornix/から直接参照
- ユーザーがkeycode_aliases.yamlを編集する必要がない

### 4. Decompiler の動作

```ruby
# lib/cornix/decompiler.rb
def decompile(output_dir)
  FileUtils.mkdir_p(output_dir)

  extract_metadata(output_dir)
  extract_position_map(output_dir)
  # copy_keycode_aliases は削除済み
  extract_qmk_settings(output_dir)
  extract_layers(output_dir)
  extract_macros(output_dir)
  extract_tap_dance(output_dir)
  extract_combos(output_dir)

  puts "✓ Decompilation completed: #{output_dir}"
end
```

**ポイント**:
- `keycode_aliases.yaml`はコピーしない
- `config/`にはユーザーが編集可能なファイルのみを生成

## Testing & Verification

### Round-trip Check (標準検証手順)

layout.vilの整合性を確認する手順：

```bash
# 1. 既存configをバックアップ
mv config config.backup

# 2. オリジナルからdecompile
ruby bin/decompile  # tmp/layout.vil を使用

# 3. 生成された設定からcompile
ruby bin/compile

# 4. 比較
ruby bin/diff_layouts
```

**期待結果**: `=== ✓ FILES ARE IDENTICAL ===`

**重要**: Compilerは以下の双方向変換を正確に実装しているため、完全一致が期待されます：

1. **Decompileフェーズ**: layout.vil（QMK形式） → YAML（エイリアス形式）
   - 例: `KC_TAB` → `Tab`, `KC_TRNS` → `Trans`, `LSFT(KC_1)` → `LSFT(1)`

2. **Compileフェーズ**: YAML（エイリアス形式） → layout.vil（QMK形式）
   - 例: `Tab` → `KC_TAB`, `Trans` → `KC_TRNS`, `LSFT(1)` → `LSFT(KC_1)`

この双方向変換により、元のlayout.vilと再コンパイル後のlayout.vilが完全に一致します。

### bin/diff_layouts の使い方

- `tmp/layout.vil`（オリジナル）と`layout.vil`（コンパイル後）を比較
- レイヤー、エンコーダー、マクロ、タップダンス、コンボ、設定を個別にチェック
- 差分がある場合は詳細を表示

比較項目：
- ✓ Version, UID, Vial protocol, Via protocol
- ✓ Layout structure (10 layers)
- ✓ Encoder layout
- ✓ Macros (non-empty count)
- ✓ Tap Dance
- ✓ Combos
- ✓ Settings

## Development Workflow

### コード変更時の確認手順

1. `lib/cornix/compiler.rb` または `decompiler.rb` を修正
2. Round-trip check を実行（上記手順）
3. すべてが一致することを確認
4. `README.md`, `README.en.md` を更新（該当する場合）

### 新しいキーコードを追加する場合

1. `lib/cornix/keycode_aliases.yaml` を編集
2. エイリアス名とQMKキーコードのマッピングを追加
3. Round-trip check で動作確認
4. README のキーコードセクションを更新

## Common Operations

### decompile時の安全機能

`config/`ディレクトリが既に存在する場合、自動的にブロックされる：

```
⚠️  Error: config/ directory already contains configuration files.
```

**回避方法**:
```bash
mv config config.backup
ruby bin/decompile
```

### パス解決の注意点

- `__dir__`は現在のRubyファイルのディレクトリを返す
- `lib/cornix/compiler.rb`内では`__dir__` = `/path/to/lib/cornix`
- プロジェクトルートへのパスは`File.expand_path('../..', __dir__)`

### RSpec テストスイート

- `spec/`ディレクトリに包括的なテストスイートを実装済み
- **総テストケース数**: 493（position_map検証・modifier式クォート柔軟性実装後）
- **総行数**: 5,400行以上

**テストファイル構成**:
1. **`keycode_parser_spec.rb` (118テスト)**: KeycodeParser機能
   - 参照形式パース（name-based, index-based）
   - 関数形式パース（シンプル、ネスト、複数引数）
   - QMKキーコード検出、レガシー形式検出、エイリアス検出
   - 引数パース（カンマ区切り、ネスト深度）
   - **+21テスト**: 修飾キー表現パース（Modifier Expression System）
   - **+2テスト**: クォート付き・クォート無し両サポート（2026-03-09）
   - Unparse ラウンドトリップ検証
2. **`modifier_expression_compiler_spec.rb` (52テスト)**: ModifierExpressionCompiler機能（NEW）
   - シンプル修飾キー表現（単一、2/3/4修飾キー）
   - QMKショートカット自動検出（LCS, LSG, MEH, HYPR等）
   - 順序無関係マッチング（Cmd + Shift = Shift + Cmd）
   - 修飾キーエイリアス解決（Command, Win, Option等）
   - 右側修飾キーサポート（RShift, RCmd等）
   - キーエイリアス解決（Space, Tab, Enter等）
   - ネスト関数フォールバック
   - エラーハンドリング（未知の修飾キー）
3. **`reference_resolver_spec.rb` (44テスト)**: ReferenceResolver機能
   - Name→Index解決（マクロ/タップダンス/コンボ）
   - Index→Name逆解決
   - レガシー形式パススルー
   - キャッシング動作（lazy load, cache hits）
   - エラーケース（名前未発見、範囲外インデックス）
4. `compiler_spec.rb` (48テスト): Compiler機能、キーコード変換、レイヤー/マクロ/タップダンス/コンボのコンパイル
   - **+8テスト**: 修飾キー表現統合（Modifier Expression System）
   - **+10テスト**: KeycodeParser統合、参照形式サポート
5. `decompiler_spec.rb` (37テスト): Decompiler機能、QMK→エイリアス変換、YAML生成
   - **+8テスト**: KeycodeParser統合、レガシー→name-basedアップグレード
6. **`validator_spec.rb` (82テスト)**: 設定ファイル妥当性検証
   - **+8テスト**: 修飾キー表現検証（Modifier Expression System）
   - **+15テスト**: KeycodeParser統合、参照形式検証、関数パース、キーコードパース
   - **+2テスト**: position_mapシンボル文字検証（2026-03-09）
   - 既存検証: レイヤーインデックス、名前の一意性、レイヤー参照（57テスト）
7. **`file_renamer_spec.rb` (57テスト)**: ファイルリネーム機能
   - ファイルリネーム、YAML内容更新、バックアップ/ロールバック（44テスト）
   - **+13テスト**: レイヤー参照自動更新（name-based, index-based, legacy処理）
8. `keycode_resolver_spec.rb` (21テスト): エイリアス⇔QMK双方向変換
9. `position_map_spec.rb` (17テスト): 物理位置マッピング
10. **`integration_spec.rb` (17テスト)**: Compile→Decompile→Compileのフルラウンドトリップ
    - **+2テスト**: 修飾キー表現統合（Modifier Expression System）
    - **+9テスト**: 参照システム統合（name/index/legacy形式、アップグレード、混合ラウンドトリップ）
    - 既存ラウンドトリップ（6テスト）

**実行方法**:
```bash
# 全テスト実行（493テスト）
bundle exec rspec

# 詳細出力
bundle exec rspec --format documentation

# 特定のファイル
bundle exec rspec spec/modifier_expression_compiler_spec.rb
```

**Modifier Expression System テストカバレッジ**:
- 修飾キー表現パース（23テスト）: パターン検出、unparse、round-trip、クォート柔軟性
- QMKショートカット自動検出（52テスト）: 全20+組み合わせ、順序無関係
- Compiler統合（8テスト）: 全形式コンパイル可能
- Validator統合（8テスト）: 修飾キー名検証、キー検証
- Integration（2テスト）: round-trip、QMK形式保持

**Reference System テストカバレッジ**:
- 参照形式パース（name-based, index-based, legacy）
- 参照解決（name↔index↔QMK）
- キャッシング（lazy loading, performance）
- Compiler統合（全形式コンパイル可能）
- Decompiler統合（レガシー→name-basedアップグレード）
- Validator統合（name-based検証、index-based範囲チェック）
- FileRenamer統合（name-based自動更新、index/legacy保持）
- ラウンドトリップ整合性（混合形式での完全一致）

**既存テストカバレッジ**:
- キーコード変換ロジック（エイリアス⇔QMK）
- レイヤー番号の保持 (MO(3) → MO(3))
- 修飾キー引数の変換 (LSFT(1) → LSFT(KC_1))
- ネストされた関数呼び出し (LT(1, Space) → LT(1, KC_SPACE))
- ラウンドトリップでのデータ整合性
- エッジケース（nil, 空文字列, 範囲外値）
- エラーハンドリング
- 設定ファイルの包括的な妥当性検証

**推奨**: Round-trip check とRSpec、そして `bin/validate` を併用して検証

### FileRenamer の使い方

**基本的な使い方**:

```bash
# 単一ファイルのリネーム（dry-run）
ruby bin/rename_file \
  --old-path config/macros/03_macro.yml \
  --new-basename 03_end_of_line.yml \
  --name "End of Line" \
  --description "Jump to end of line" \
  --dry-run

# 実行（バックアップ自動作成）
ruby bin/rename_file \
  --old-path config/macros/03_macro.yml \
  --new-basename 03_end_of_line.yml \
  --name "End of Line"

# バッチリネーム（JSON経由）
ruby bin/rename_file --batch tmp/rename_plans.json

# バッチリネーム＋成功時にバックアップ削除
ruby bin/rename_file --batch tmp/rename_plans.json --cleanup-backup
```

**JSON計画ファイル形式** (`tmp/rename_plans.json`):

```json
[
  {
    "old_path": "config/macros/03_macro.yml",
    "new_basename": "03_end_of_line.yml",
    "content_updates": {
      "name": "End of Line",
      "description": "Jump to end of line with Cmd+Right"
    }
  }
]
```

**推奨ワークフロー（Skill経由）**:

```bash
# LLMによる内容解析とリネーム提案
claude /rename
```

**推奨ワークフロー（cornix rename）**:

```bash
# インタラクティブなリネーム（推奨）
cornix rename

# 実行フロー：
# 1. 現在の設定をコンパイル（ベースライン）
# 2. マクロ/タップダンスを解析してリネーム提案
# 3. 各提案にy/n/editで応答
# 4. リネーム実行（自動バックアップ）
# 5. コンパイル検証（構造比較）
# 6. 一時ファイル削除
```

**重要な機能**:

1. **インデックスプレフィックス保持**: `03_macro.yml` → `03_end_of_line.yml` （`03_`を維持）
2. **事前検証**: ファイル存在、インデックス一致、重複チェック
3. **自動バックアップ**: `config.backup_<timestamp>/` に全体をバックアップ
4. **トランザクション型**: バッチ処理は全成功 or 全ロールバック
5. **コンパイル検証**: リネーム後に `Compiler` で妥当性確認
6. **自動ロールバック**: エラー時は自動的に元の状態に復元

### Validator の使い方

**基本的な使い方**:

```bash
# 設定ファイルを検証
ruby bin/validate

# 成功時
✓ All validations passed

# 失敗時
✗ Validation failed:
  Error: Layer 0_base.yaml, symbol 'LT1': Invalid keycode 'InvalidKeycode'
  Error: Layer 1_symbols.yaml: Unknown position symbol 'UnknownSymbol'
```

**推奨ワークフロー**:

```bash
# 1. 設定を編集
vim config/layers/0_base.yaml

# 2. 検証
ruby bin/validate

# 3. コンパイル（検証成功後のみ）
ruby bin/compile
```

**Phase 1 実装済み検証項目**:

1. **YAML構文の正当性** (`validate_yaml_syntax`)
   - 全YAMLファイルのパースエラーを検出
   - ユーザーフレンドリーなエラーメッセージ
   - YAMLエラーのあるファイルは以降の検証をスキップ（多重エラー防止）

2. **メタデータの妥当性** (`validate_metadata`)
   - `metadata.yaml`の存在チェック
   - 必須フィールド: `keyboard`, `version`, `uid`, `vial_protocol`, `via_protocol`
   - `vendor_product_id`の形式チェック（`0xXXXX`）
   - `matrix`の型・範囲チェック（`rows`, `cols`は正の整数）

3. **Position Map の妥当性** (`validate_position_map`)
   - `position_map.yaml`内のシンボルが一意であることを検証
   - 同じシンボルが複数の物理位置に割り当てられている場合はエラー
   - 左手・右手間での重複も検出
   - nil や空文字列は無視
   - **NEW (2026-03-09)**: シンボル名がYAMLクォート不要な文字のみで構成されているかチェック
     - 許可: 英数字、アンダースコア、ハイフン（`[a-zA-Z0-9_-]+`）
     - 不許可: `'`, `;`, 単独の `-` 等のYAML特殊文字

4. **キーコードの妥当性** (`validate_keycodes`)
   - レイヤー内の全キーコードを検証
   - QMKキーコード（`KC_*`）、エイリアス（`Tab`, `Space`）をサポート
   - 関数形式のキーコードも検証（`MO(1)`, `LSFT(A)`, `LT(2, Space)`）
   - 関数引数も再帰的に検証（ネストされた関数にも対応）
   - `KeycodeResolver`を活用してエイリアス解決

5. **Position Map参照の整合性** (`validate_position_references`)
   - レイヤーで使用される全シンボル（`LT1`, `RT1`等）を検証
   - `position_map.yaml`に定義されていないシンボルを検出
   - `position_map.yaml`が存在しない場合は警告（エラーではない）
   - `PositionMap`クラスを活用して全シンボルを抽出

**既存の検証項目**（Phase 0実装済み）:

5. **レイヤーインデックスの妥当性** (`validate_layer_indices`)
6. **マクロ名の一意性** (`validate_macro_names`)
7. **タップダンス名の一意性** (`validate_tap_dance_names`)
8. **コンボ名の一意性** (`validate_combo_names`)
9. **レイヤー内の参照妥当性** (`validate_layer_references`)

**未実装（Phase 2以降の候補）**:

- マクロシーケンス構文の妥当性
- タップダンスアクションの妥当性
- コンボトリガー数の妥当性
- QMK Settings の型・範囲チェック
- エンコーダー設定の妥当性
- Index フィールドの存在チェック

**重要な実装詳細**:

```ruby
# validator.rb の初期化
def initialize(config_dir)
  @config_dir = config_dir
  @errors = []
  @warnings = []

  # KeycodeResolverの初期化
  aliases_path = File.join(File.dirname(__FILE__), 'keycode_aliases.yaml')
  @keycode_resolver = KeycodeResolver.new(aliases_path)

  # YAMLパースエラーがあったファイルを記録（多重エラー防止）
  @failed_yaml_files = []
end

# キーコード検証の例
def valid_keycode?(keycode)
  # 関数形式のキーコード（例: MO(3), LSFT(A), LT(1, Space)）
  if keycode.match?(/^(\w+)\((.+)\)$/)
    function_name = $1
    args = $2

    # 関数名が有効なキーコードまたはエイリアスか確認
    return false unless valid_simple_keycode?(function_name)

    # 引数を検証（カンマ区切りをサポート）
    args.split(',').each do |arg|
      arg = arg.strip
      # 数値引数は常に許容（レイヤー番号、インデックス等）
      next if arg.match?(/^\d+$/)

      # 引数が有効なキーコードか再帰的にチェック
      return false unless valid_keycode?(arg)
    end

    return true
  end

  # シンプルなキーコード
  valid_simple_keycode?(keycode)
end

# Position Map シンボル重複検証の例
def validate_position_map
  position_map_data = YAML.load_file(position_map_path)
  symbol_locations = {}  # symbol => [locations]

  ['left_hand', 'right_hand'].each do |hand|
    position_map_data[hand].each do |row_key, row_data|
      row_data.each do |col, symbol|
        next if symbol.nil? || symbol.to_s.empty?

        symbol_str = symbol.to_s
        location = "#{hand}.#{row_key}[#{col}]"

        if symbol_locations[symbol_str]
          symbol_locations[symbol_str] << location
        else
          symbol_locations[symbol_str] = [location]
        end
      end
    end
  end

  # 重複しているシンボルを報告
  symbol_locations.each do |symbol, locations|
    if locations.size > 1
      @errors << "position_map.yaml: Duplicate symbol '#{symbol}' at: #{locations.join(', ')}"
    end
  end
end
```

## Troubleshooting

### keycode_aliases.yamlが見つからない

**症状**: `Warning: keycode_aliases.yaml not found`

**原因**: パス解決が正しくない

**解決**:
- compiler.rbで`File.join(__dir__, 'keycode_aliases.yaml')`を使用
- decompiler.rbでは参照不要（コピーしない）

### Round-trip checkが失敗する

**症状**: `=== ✗ FILES DIFFER ===`

**デバッグ手順**:
1. どのセクションで差分が発生しているか確認（Layer, Macro, etc.）
2. 該当するcompile/decompileロジックを確認
3. YAMLファイルの内容を手動で確認

### config/ディレクトリが生成されない

**原因**: `.decompile.lock`ファイルが存在する可能性

**解決**:
```bash
rm -rf config/.decompile.lock
ruby bin/decompile
```

## Code Style & Conventions

- Ruby 2.7+ を想定
- frozen_string_literal: true を使用
- モジュール構成: `Cornix::Compiler`, `Cornix::Decompiler`
- YAML読み込み: `YAML.load_file`
- ファイル書き込み: `File.write`

## References

- [QMK Keycodes Documentation](https://docs.qmk.fm/keycodes)
- [Vial Documentation](https://get.vial.today/)
- [QMK Firmware Documentation](https://docs.qmk.fm/)
