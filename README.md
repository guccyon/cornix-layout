# Cornix Keyboard Layout Manager

cornixキーボード用のヒューマンリーダブルなレイアウト設定管理システムです。

Vialの`layout.vil`ファイルは直接編集が困難なため、YAMLベースの直感的な設定ファイルシステムを提供します。

## 特徴

- 📝 **ヒューマンリーダブル**: YAMLで読みやすく書きやすい設定ファイル
- 🔤 **エイリアス対応**: `KC_TAB` → `Tab`, `KC_TRNS` → `Trans` など、読みやすいエイリアスを自動使用
- 🗂️ **モジュール化**: レイヤー、マクロ、タップダンス、コンボを個別のファイルで管理
- 🏷️ **名前管理**: レイヤー、マクロ、タップダンスに意味のある名前を付けられる
- 📊 **差分管理**: 上位レイヤーはLayer 0からの差分のみ記述
- 💬 **コメント対応**: `#`でコメントを記述可能
- 🔄 **双方向変換**: `layout.vil` ⇔ YAML設定ファイル

## インストール

```bash
git clone https://github.com/yourusername/cornix-layout.git
cd cornix-layout
```

## 使い方

### 典型的な使い方

Cornixの主な使用パターンを3つのユースケースで説明します。

<details>
<summary><b>Use Case 1: 任意の場所からのlayout.vilをデコンパイル</b></summary>

**シナリオ**: Vialでエクスポートした`layout.vil`をYAML形式に変換して編集したい

**手順**:
```bash
# 1. layout.vilをダウンロード（例：~/Downloads/layout.vil）
# Vialから "File > Export Layout" でエクスポート

# 2. Cornixプロジェクトに移動
cd ~/work/cornix

# 3. デコンパイル（任意のパスを指定可能）
cornix decompile ~/Downloads/layout.vil

# 4. 生成された設定を確認
ls -la config/
# config/layers/     - レイヤーファイル
# config/macros/     - マクロファイル
# config/tap_dance/  - タップダンスファイル
# config/combos/     - コンボファイル

# 5. 設定を編集
vim config/layers/0_base.yaml

# 6. コンパイル（自動検証付き）
cornix compile

# 7. 生成されたlayout.vilをVialでインポート
# Vial: "File > Import Layout" → layout.vil を選択
```

**ポイント**:
- `cornix decompile`は任意のパスの`layout.vil`を受け付けます
- デフォルト（引数なし）の場合は`tmp/layout.vil`を使用
- 既存の`config/`がある場合はロック保護により自動ブロック

</details>

<details>
<summary><b>Use Case 2: 既存設定の編集とコンパイル</b></summary>

**シナリオ**: 既に`config/`ディレクトリがあり、設定を編集してコンパイルしたい

**手順**:
```bash
# 1. 現在の設定を確認
ls config/layers/

# 2. レイヤーファイルを編集
vim config/layers/1_symbol.yaml

# 3. 検証（オプション、compileで自動実行される）
cornix validate

# 4. コンパイル（自動検証付き）
cornix compile

# 5. 変更を確認（オプション）
git diff layout.vil

# 6. Vialでインポート
```

**ポイント**:
- `cornix compile`は自動的に検証を実行します
- 検証エラーがある場合、コンパイルは中断されます
- バージョン管理（git）の使用を推奨

</details>

<details>
<summary><b>Use Case 3: LLMによるインテリジェントリネーム</b></summary>

**シナリオ**: 汎用名（"Macro 0", "Tap Dance 1"）を持つファイルを意味のある名前にリネームしたい

**手順**:
```bash
# 1. 現在の設定を確認
ls config/macros/
# 00_macro.yml, 01_macro.yml, ...（汎用名）

# 2. インタラクティブリネーム（Claude CLI必須）
cornix rename

# 3. Claude AIによる解析と提案
# 各ファイルの内容を解析して意味のある名前を提案

# 4. 提案を確認してy/n/editで応答
# y: 承認
# n: スキップ
# e: 手動編集

# 5. リネーム実行（自動バックアップ）
# config.backup_<timestamp>/ にバックアップ作成

# 6. コンパイル検証
# 構造が保持されていることを自動確認

# 7. 結果確認
ls config/macros/
# 00_bracket_pair.yml, 01_end_of_line.yml, ...（意味のある名前）
```

**ポイント**:
- Claude Code CLI (`claude`コマンド) が必要
- マクロのキーシーケンスから目的を深く推測
- トランザクション型処理（全成功 or 全ロールバック）
- Name-based参照のみ自動更新（Index-based/Legacyは保持）

</details>

**Claude Code使用時のTips**:

`claude`コマンドでClaude AIと対話しながら設定を編集する場合：

1. **編集前に検証**: `cornix validate`で現在の設定を確認
2. **修飾キー表現を推奨**: QMK構文より`Cmd + Q`形式の方が読みやすい
3. **Name-based参照を推奨**: `Macro('name')`形式でマクロ/タップダンスを参照
4. **編集後に検証**: `cornix compile`で自動検証とコンパイル
5. **Skills活用**: `/rename`スキルでインテリジェントリネーム

### 既存のlayout.vilから設定ファイルを生成

```bash
# デフォルト（tmp/layout.vil）を使用
cornix decompile

# または、任意のファイルパスを指定
cornix decompile ~/Downloads/layout.vil
cornix decompile /path/to/custom.vil
```

**⚠️ 重要 - ロック保護機能**: 既に`config/`ディレクトリに設定ファイルが存在する場合、デコンパイルは自動的にブロックされます。これは意図しない上書きを防ぐための安全機能です。

**エラーメッセージ例**:
```
⚠️  Error: config/ directory already contains configuration files.
```

**対処方法**:
```bash
# オプション1: cleanupコマンドで既存設定を削除
cornix cleanup
cornix decompile ~/Downloads/layout.vil

# オプション2: 手動でバックアップしてから削除
mv config config.backup
cornix decompile ~/Downloads/layout.vil
```

**背景**: この機能により、既存の設定を誤って上書きする事故を防ぎます。新しい`layout.vil`をデコンパイルする前に、必ず既存の設定をバックアップまたは削除してください。

**cleanupコマンド**:

`cornix cleanup`コマンドを使用すると、生成されたファイルを安全に削除できます：

```bash
# 通常のクリーンアップ（lockファイルがある場合は保護される）
cornix cleanup

# 強制クリーンアップ（確認プロンプトでlockファイルも削除）
cornix cleanup -f
```

- 通常実行時、`.decompile.lock`ファイルが存在する場合は処理が停止します
- `-f`オプションで強制実行する場合は、確認プロンプトが表示されます
- 削除対象: `config/`ディレクトリ、`layout.vil`ファイル

`config/`ディレクトリ以下に以下のファイルが生成されます：

```
config/
├── metadata.yaml              # キーボード基本情報
├── position_map.yaml          # 物理位置とシンボルのマッピング
├── settings/
│   └── qmk_settings.yaml      # QMK設定
├── layers/
│   ├── 0_layer.yml            # レイヤー0（ベース）
│   ├── 1_layer.yml            # レイヤー1
│   └── ...                    # レイヤー2-9
├── macros/
│   ├── 00_macro.yml           # マクロ0
│   ├── 01_macro.yml           # マクロ1
│   └── ...
├── tap_dance/
│   ├── 00_tap_dance.yml       # タップダンス0
│   ├── 01_tap_dance.yml       # タップダンス1
│   └── ...
└── combos/
    ├── 00_combo.yml           # コンボ0
    ├── 01_combo.yml           # コンボ1
    └── ...
```

**ファイル名の命名規則**:
- **Layers**: `{index}_layer.yml` (例: `0_layer.yml`, `1_layer.yml`)
- **Macros**: `{index:02d}_macro.yml` (例: `00_macro.yml`, `01_macro.yml`)
- **Tap Dance**: `{index:02d}_tap_dance.yml` (例: `00_tap_dance.yml`, `01_tap_dance.yml`)
- **Combos**: `{index:02d}_combo.yml` (例: `00_combo.yml`, `01_combo.yml`)

**ファイル名のカスタマイズ**:
生成されたファイルは汎用的な名前で作成されますが、自由にリネーム可能です：

```bash
# レイヤーファイル名を意味のある名前に変更
mv config/layers/1_layer.yml config/layers/1_symbol.yml
mv config/layers/2_layer.yml config/layers/2_number.yml

# マクロファイル名を機能に応じた名前に変更
mv config/macros/00_macro.yml config/macros/00_bracket_pair.yml
mv config/macros/01_macro.yml config/macros/01_curly_bracket_pair.yml
```

**重要**: Compilerはファイル名に依存しません（レイヤーのインデックスプレフィックスを除く）。YAML内の`index`フィールドを使用してインデックスを管理します。

### 設定ファイルのインテリジェントリネーム

`cornix rename`コマンドを使用すると、Claude AIがマクロ、タップダンス、コンボ、レイヤーの内容を解析して、意味のある名前に自動リネームできます。

#### 動作モード

**Interactive Mode（推奨）**: ユーザー確認付きのインタラクティブモード

```bash
cornix rename
```

このモードでは、Claude AIが各ファイルを解析してリネーム提案を表示し、ユーザーが`y`/`n`/`e`(dit)で応答します。最も安全で推奨される方法です。

**Advanced Mode（上級者向け）**: `bin/rename_file`コマンドで直接制御

```bash
# 単一ファイルのリネーム（dry-run）
ruby bin/rename_file \
  --old-path config/macros/03_macro.yml \
  --new-basename 03_end_of_line.yml \
  --name "End of Line" \
  --description "Jump to end of line" \
  --dry-run

# バッチリネーム（JSON経由）
ruby bin/rename_file --batch tmp/rename_plans.json
```

Advanced Modeは、スクリプトやCIパイプラインでの自動化に適していますが、通常は**Interactive Mode**を推奨します。

#### LLM統合の仕組み

`cornix rename`は、Claude AIとRuby実行部分を連携させた**ハイブリッドアーキテクチャ**です：

**1. LLM部分（Claude AI Skill）**:
- ファイル内容の深い解析
- キーシーケンスからの意図推測
- 意味のある名前の生成
- パターン検出（brackets, copy, function template等）
- 信頼度レベル付き提案（high/medium/low）

**2. Ruby部分（静的実行）**:
- ファイル操作（リネーム、YAML更新）
- 自動バックアップ/ロールバック
- コンパイル検証
- トランザクション処理

**3. JSON連携**:
```json
// tmp/rename_plans.json
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

Claude AIが提案を生成 → JSON保存 → Ruby実行で安全に適用

**前提条件**：
- Claude Code CLI (`claude`コマンド) がインストールされている必要があります
- インストールされていない場合はエラーメッセージとともに処理が中断されます

**実行フロー**：

1. **現在の設定をコンパイル**: リネーム前の状態をベースラインとして保存
2. **Claude AIによる解析**:
   - マクロ: キーシーケンスから目的を深く推測（例：`[, ], Left` → "Bracket Pair"）
   - タップダンス: tap/hold/double-tap アクションを分析（例：`MO(1)` → "Layer 1 Switch"）
   - コンボ: トリガーキーと出力から機能を判定
   - レイヤー: descriptionフィールドやoverridesから意図を推測
3. **リネーム提案を表示**: 各ファイルに対して提案を表示
4. **ユーザー確認**: 各提案に対して`y`/`n`/`e`(dit)で応答
5. **リネーム実行**: 自動バックアップ作成後、ファイルリネームとYAML内容更新
6. **コンパイル検証**: layout.vilの構造が保持されていることを確認
7. **一時ファイル削除**: ログや一時ファイルを自動削除

**例**：

```
──────────────────────────────────────────────────────────────────────
1. MACRO: 00_macro.yml

  Current:  00_macro.yml
  Proposed: 00_bracket_pair.yml

  Name:        Bracket Pair
  Description: Insert bracket pair [] with cursor positioning

  Reasoning:   Key sequence inserts left bracket, right bracket, then moves cursor left
  Confidence:  high

  Apply this rename? [Y/n/e(dit)]: y
  ✓ Added to rename queue
```

**Claude AIの解析能力**：
- 複雑なキーシーケンスの意図を理解
- 修飾キー（Shift, Cmd, Ctrl）の組み合わせを考慮
- カーソル移動パターンから操作の目的を推測
- コンテキストを考慮した命名（例：`function ()` + Left → "Function Template"）

**安全機能**：
- 自動バックアップ作成（`config.backup_<timestamp>/`）
- トランザクション型処理（全成功 or 全ロールバック）
- コンパイル検証（構造保持確認）
- インデックスプレフィックス保持（`00_`, `01_`, `0_`, `1_` 等）
- レイヤー参照の整合性保証（indexベース）
- エラー時の自動ロールバック

**リネーム対象**：
- マクロ: 汎用名（"Macro N"）を持つファイル
- タップダンス: 汎用名（"Tap Dance N"）を持つファイル
- コンボ: 汎用名（"Combo N"）を持つファイル
- レイヤー: 汎用名（"Layer N"）を持つファイル

**バックアップのクリーンアップ**：
リネーム完了後、バックアップディレクトリの削除を確認するプロンプトが表示されます。

**注意**:
- **キーコードエイリアス** (`keycode_aliases.yaml`): `lib/cornix/`に固定配置、`config/`には生成されません（QMK標準定義のため編集不要）
- **Position Map** (`position_map.yaml`): `lib/cornix/`のテンプレートから`config/`に生成され、シンボル名をカスタマイズできます

### 設定ファイルを編集

`decompile`で生成されたレイヤーファイルは、読みやすいエイリアス形式で記述されています。

レイヤーファイル（例：`config/layers/1_layer.yml`）：

```yaml
name: Layer 1
description: Layer 1

# Layer 0と異なるキーのみ記述
overrides:
  Q: LSFT(1)         # ! を入力（Shift+1）
  W: LSFT(2)         # @ を入力（Shift+2）
  E: LSFT(3)         # # を入力（Shift+3）

  lshift: Trans      # 透過（下のレイヤーのキーを使用）
  D: NoKey           # 無効化

  # マクロを参照（名前で指定）- 推奨
  A: Macro('Bracket Pair')

  # タップダンスを参照（名前で指定）- 推奨
  fn: TapDance('Layer Switch')
```

#### マクロ・タップダンス・コンボの参照方法

Cornixは3つの参照形式をサポートしています：

**1. Name-based形式（推奨）**：名前で参照する最も読みやすい形式
```yaml
# マクロを名前で参照
A: Macro('Bracket Pair')

# タップダンスを名前で参照
fn: TapDance('Layer Switch')

# コンボを名前で参照
combo1: Combo('Escape Alternative')
```

**メリット**：
- 設定ファイルが自己文書化され、可読性が高い
- ファイルをリネームしても参照が自動更新される（`cornix rename`使用時）
- 編集時にマクロ/タップダンスの機能が一目で分かる

**2. Index-based形式（明示的）**：インデックスで参照する形式
```yaml
# マクロをインデックスで参照
A: Macro(0)

# タップダンスをインデックスで参照
fn: TapDance(2)
```

**メリット**：
- インデックスを明示的に管理したい場合に便利
- 既存の設定からの移行が簡単

**3. QMK Legacy形式（後方互換）**：従来のQMK形式
```yaml
# マクロ（Mプレフィックス）
A: M0

# タップダンス（TD関数）
fn: TD(2)
```

**メリット**：
- QMKに慣れている場合は親しみやすい
- 既存の設定を変更せずそのまま使える

**推奨**：新規作成時は**Name-based形式**を使用してください。`cornix decompile`は自動的にName-based形式で生成します。

**注意**：
- すべての形式が同じ`layout.vil`にコンパイルされます（Vial互換）
- `cornix rename`でファイルをリネームすると、Name-based参照のみ自動更新されます
- Index-based / Legacy形式は後方互換性のため保持されますが、自動更新されません

**注**: ファイル名や内部の`name`フィールドは自由に変更できます。インデックスはYAML内の`index`フィールド（マクロ・タップダンス・コンボ）またはファイル名のプレフィックス（レイヤー）で管理されます。

**エイリアスの利点**:
- `KC_TRNS` → `Trans` （より簡潔）
- `KC_NO` → `NoKey` （意味が明確）
- `LSFT(KC_1)` → `LSFT(1)` （関数内部も変換）
- `KC_TAB` → `Tab` （読みやすい）

マクロファイル（例：`config/macros/00_macro.yml`）：

```yaml
name: Macro 0
description: Macro 0
enabled: true
index: 0

sequence:
  - action: tap
    keys: ["[", "]", Left]
```

**注**: ファイル名は自由に変更できます（例: `00_bracket_pair.yml`）。Compilerは`index`フィールドを使用してマクロのインデックスを決定します。

### layout.vilに変換

**重要**: コンパイル時に自動的に設定ファイルの検証が実行されます。

```bash
cornix compile
```

検証エラーがある場合、コンパイルは自動的に中断されます。検証のみを実行したい場合は：

```bash
cornix validate
```

生成された`layout.vil`をVialでインポートしてキーボードに書き込みます。

## 設定ファイルの検証

`cornix validate`コマンドで、コンパイル前に設定ファイルの妥当性を検証できます。

```bash
# 設定ファイルを検証
cornix validate

# 成功時
✓ All validations passed

# 失敗時
✗ Validation failed:
  Error: Layer 0_base.yaml, symbol 'LT1': Invalid keycode 'InvalidKeycode'
  Error: Layer 1_symbols.yaml: Unknown position symbol 'UnknownSymbol'
```

**重要**: `cornix compile`は自動的に検証を実行するため、通常は明示的な`validate`呼び出しは不要です。

### Phase 1実装済み検証項目

以下の検証項目が実装されています（Phase 1完了）：

<details>
<summary><b>1. YAML構文の正当性</b></summary>

- 全YAMLファイルの構文エラーを検出
- パースエラーのある場合、ユーザーフレンドリーなエラーメッセージを表示
- YAMLエラーのあるファイルは以降の検証をスキップ（多重エラー防止）

**検出例**:
```
Error: config/layers/0_base.yaml: Invalid YAML syntax - mapping values are not allowed here
```

</details>

<details>
<summary><b>2. メタデータの妥当性</b></summary>

- `metadata.yaml`の存在チェック
- 必須フィールド検証: `keyboard`, `version`, `uid`, `vial_protocol`, `via_protocol`
- `vendor_product_id`の形式チェック（`0xXXXX`形式）
- `matrix`設定の型・範囲チェック（`rows`, `cols`は正の整数）

**検出例**:
```
Error: metadata.yaml: Missing required field 'keyboard'
Error: metadata.yaml: Invalid vendor_product_id format (expected 0xXXXX)
```

</details>

<details>
<summary><b>3. Position Map の妥当性</b></summary>

- `position_map.yaml`内のシンボルが一意であることを検証
- 同じシンボルが複数の物理位置に割り当てられている場合はエラー
- 左手・右手間での重複も検出
- nil や空文字列は無視

**検出例**:
```
Error: position_map.yaml: Duplicate symbol 'Q' at: left_hand.row0[1], right_hand.row0[2]
```

</details>

<details>
<summary><b>4. キーコードの妥当性</b></summary>

- レイヤー内の全キーコードが有効なQMKキーコードまたはエイリアスか検証
- 関数形式のキーコード（`MO(1)`, `LSFT(A)`, `LT(2, Space)`等）の引数も検証
- 関数内部の引数も再帰的に検証（ネストされた関数にも対応）
- 修飾キー表現（`Cmd + Q`等）の検証
- タイプミスの早期発見

**検出例**:
```
Error: Layer 0_base.yaml, symbol 'Q': Invalid keycode 'Spce' (did you mean 'Space'?)
Error: Layer 1_symbol.yaml, symbol 'W': Invalid function argument in 'LSFT(InvalidKey)'
```

</details>

<details>
<summary><b>5. Position Map参照の整合性</b></summary>

- レイヤーで使用されるシンボル（`LT1`, `RT1`等）が`position_map.yaml`に定義されているか検証
- 未定義のポジションシンボル参照を検出
- `position_map.yaml`が存在しない場合は警告（エラーではない）

**検出例**:
```
Error: Layer 0_base.yaml: Unknown position symbol 'UnknownKey' (not defined in position_map.yaml)
```

</details>

<details>
<summary><b>6. レイヤーインデックスの妥当性</b></summary>

- レイヤーファイル名が数字で始まること（例: `0_base.yaml`）
- レイヤーインデックスが0-9の範囲内
- 重複するレイヤーインデックスがないこと

**検出例**:
```
Error: Layer file 'base.yaml' must start with layer index (e.g., 0_base.yaml)
Error: Duplicate layer index 1: 1_symbol.yaml, 1_number.yaml
```

</details>

<details>
<summary><b>7. マクロ/タップダンス/コンボ名の一意性</b></summary>

- 各ファイルに`name`フィールドが存在
- 名前がファイル間で一意

**検出例**:
```
Error: Duplicate macro name 'Bracket Pair' in files: 00_bracket.yml, 01_bracket_copy.yml
```

</details>

<details>
<summary><b>8. レイヤー内の参照妥当性</b></summary>

- Name-based参照（`Macro('name')`, `TapDance('name')`）が実在する名前を指していること
- Index-based参照（`Macro(0)`, `TapDance(2)`）は範囲チェックのみ（0-31）
- Legacy参照（`M0`, `TD(2)`）は範囲チェックのみ

**検出例**:
```
Error: Layer 0_base.yaml, symbol 'Q': Macro 'Unknown Macro' not found
Error: Layer 1_symbol.yaml, symbol 'W': Macro index 99 out of range (0-31)
```

</details>

### Phase 2未実装項目

以下の検証は将来のPhase 2で実装予定です：

- マクロシーケンス構文の妥当性
- タップダンスアクション構文の妥当性
- コンボトリガー数の妥当性
- QMK Settings の型・範囲チェック
- エンコーダー設定の妥当性

### 推奨ワークフロー

```bash
# 設定を編集
vim config/layers/0_base.yaml

# コンパイル（自動検証付き）
cornix compile
```

検証エラーがある場合、コンパイルは自動的に中断されます。

## ファイル構造

### レイヤーファイル

レイヤーファイルは`{index}_{name}.yaml`形式で命名します。

- `index`: レイヤー番号（0-9）
- `name`: 任意の説明的な名前

**例：** `0_base.yaml`, `1_symbol_mac.yaml`, `2_number.yaml`

レイヤー番号の変更：

```bash
# 2_number.yaml を 5_number.yaml に変更する場合
mv config/layers/2_number.yaml config/layers/5_number.yaml

# 他のレイヤーファイル内のMO(2), LT(2, ...)等を手動でMO(5), LT(5, ...)に変更
```

### マクロ・タップダンス・コンボファイル

これらは`{name}.yaml`形式で命名します（番号不要）。

**ファイル名の辞書順でインデックスが決まります。**

#### マクロファイルの例

```yaml
name: curly_bracket_pair
description: {}を挿入してカーソルを左に移動
enabled: true

sequence:
  - action: down
    key: LShift

  - action: tap
    keys: ["[", "]"]

  - action: up
    key: LShift

  - action: tap
    key: Left
```

#### タップダンスファイルの例

```yaml
name: screenshot_combo
description: タップでCmd+Shift+4、ダブルタップでCmd+Shift+5
enabled: true

actions:
  on_tap: "LCmd+LShift+[4]"
  on_double_tap: "LCmd+LShift+[5]"
  on_hold: "-"
  on_tap_hold: "-"

tapping_term: 250
```

#### コンボファイルの例

```yaml
name: left_bracket
description: D+F で [ を入力
enabled: true

trigger:
  - D
  - F

output: "["
```

### レイヤーでの参照方法

```yaml
# config/layers/1_symbol.yaml
overrides:
  # マクロを名前で参照（推奨）
  A: MACRO(bracket_pair)

  # タップダンスを名前で参照（推奨）
  fn: TD(layer_switch)

  # インデックス参照も可能（非推奨）
  B: MACRO(0)  # どのマクロか分かりにくい
```

## 柔軟な参照システム（Flexible Reference System）

Cornixは、マクロ、タップダンス、コンボへの参照を3つの形式でサポートしています。それぞれに利点があり、用途に応じて使い分けることができます。

### 3つの参照形式

#### 1. Name-based形式（推奨）

**最も読みやすく、自己文書化された形式**です。名前で参照するため、設定ファイルを見ただけで何をするマクロ/タップダンス/コンボかが一目で分かります。

```yaml
# レイヤーファイル内
mapping:
  Q: Macro('End of Line')           # マクロを名前で参照
  W: TapDance('Escape or Layer')    # タップダンスを名前で参照
  E: Combo('Bracket Pair')          # コンボを名前で参照
```

**メリット**:
- **可読性が高い**: `M3`より`Macro('End of Line')`の方が機能が明確
- **自己文書化**: コメント不要で設定ファイルが理解できる
- **自動更新**: `cornix rename`でファイル名を変更すると、参照も自動更新される

**使用場面**:
- 新規レイヤー作成時（推奨）
- チーム開発での設定共有
- 長期的にメンテナンスする設定

#### 2. Index-based形式（明示的）

**インデックスを明示的に指定する形式**です。数値（0-31の範囲）で参照します。

```yaml
# レイヤーファイル内
mapping:
  Q: Macro(0)           # マクロをインデックスで参照
  W: TapDance(2)        # タップダンスをインデックスで参照
  E: Combo(1)           # コンボをインデックスで参照
```

**メリット**:
- **明示的**: インデックスを直接管理したい場合に便利
- **安定性**: リネーム時に参照が変更されない
- **柔軟性**: ファイルが存在しなくても参照可能（後でファイル追加予定の場合）

**使用場面**:
- プログラムで動的に生成する設定
- インデックスを固定したい場合
- リネーム自動追従が不要な場合

#### 3. QMK Legacy形式（後方互換）

**従来のQMK標準形式**です。既存のQMK設定との互換性を保ちます。

```yaml
# レイヤーファイル内
mapping:
  Q: M0           # レガシーマクロ形式
  W: TD(2)        # レガシータップダンス形式
```

**メリット**:
- **後方互換性**: 既存のQMK設定がそのまま動作
- **QMK標準**: QMKに慣れている場合は親しみやすい
- **移行不要**: 既存の設定を変更せず使える

**使用場面**:
- 既存のQMK設定からの移行
- QMK標準形式を維持したい場合

### 各形式の動作の違い

| 機能 | Name-based | Index-based | Legacy |
|-----|-----------|------------|--------|
| **可読性** | ⭐⭐⭐ | ⭐ | ⭐ |
| **Decompile出力** | ✅ 常にこの形式 | ❌ Name-basedに変換 | ❌ Name-basedに変換 |
| **Rename自動更新** | ✅ 自動更新 | ❌ 保持 | ❌ 保持 |
| **Validator検証** | ✅ ファイル存在確認 | ⚠️ 範囲チェックのみ | ⚠️ 範囲チェックのみ |
| **ファイル不要** | ❌ 必要 | ✅ 不要（0-31範囲内） | ✅ 不要 |

### 推奨事項

**新規作成時**: Name-based形式を使用してください。`cornix decompile`は自動的にName-based形式で生成します。

**既存設定**: すべての形式が完全にサポートされており、移行は不要です。既存のレガシー形式はそのまま動作します。

### Decompilerの動作

`cornix decompile`は、常に**Name-based形式**でYAMLファイルを生成します。これは可読性を最大化するための設計です。

```yaml
# layout.vil（QMK形式）
M5, TD(2), COMBO(1)

# ↓ decompile後（YAML）
mapping:
  Q: Macro('End of Line')      # Name-based形式
  W: TapDance('Escape')        # Name-based形式
  E: Combo('Bracket')          # Name-based形式
```

**注意**: Index-basedやLegacy形式で記述していた場合でも、decompile後はName-based形式に変換されます。これは意図的な設計です（より読みやすい形式への統一）。

### FileRenamerの動作（選択的更新）

`cornix rename`でファイルをリネームすると、**Name-based参照のみ**が自動更新されます。

```yaml
# リネーム前
config/macros/03_macro.yml: name: "Old Name"

# レイヤーファイル内
mapping:
  Q: Macro('Old Name')    # ✅ 自動更新される
  W: Macro(3)             # ❌ 変更されない（Index-based）
  E: M3                   # ❌ 変更されない（Legacy）

# リネーム後（cornix rename実行）
config/macros/03_end_of_line.yml: name: "End of Line"

# レイヤーファイル内
mapping:
  Q: Macro('End of Line') # ✅ 自動更新された
  W: Macro(3)             # ❌ そのまま（意図的）
  E: M3                   # ❌ そのまま（意図的）
```

**設計理由**: ユーザーの選択を尊重し、予測可能性を保つため。Name-based形式を選んだユーザーは自動更新を期待し、Index-based/Legacy形式を使うユーザーは安定性を重視していると考えられます。

### Round-trip整合性

すべての形式で、layout.vilへのコンパイルとround-trip整合性が保証されています。

```bash
# どの形式を使用しても同じlayout.vilが生成される
cornix compile  # → layout.vil（QMK形式）

# round-trip check
mv config config.backup
cornix decompile  # Name-based形式で生成
cornix compile
ruby bin/diff_layouts  # ✓ FILES ARE IDENTICAL
```

## 修飾キー表現（VS Code風）

Cornixは、VS CodeやIDEのキーバインディングのような読みやすい修飾キー表現をサポートしています。`Cmd + Q`のように記述すると、自動的にQMK形式（`LGUI(KC_Q)`）にコンパイルされます。

### 基本的な使い方

```yaml
# config/layers/0_base.yaml
mapping:
  Q: Cmd + Q              # → LGUI(KC_Q)
  W: Shift + W            # → LSFT(KC_W)
  E: Ctrl + C             # → LCTL(KC_C)
  R: Alt + Tab            # → LALT(KC_TAB)
```

### QMKショートカット自動検出

複数の修飾キーを組み合わせると、QMKのショートカット関数が自動的に使用されます：

```yaml
mapping:
  # 2修飾キー
  Q: Shift + Cmd + Q          # → LSG(KC_Q)
  W: Ctrl + Shift + W         # → LCS(KC_W)
  E: Ctrl + Alt + E           # → LCA(KC_E)

  # 3修飾キー
  R: Ctrl + Shift + Alt + R   # → MEH(KC_R)
  T: Ctrl + Shift + Cmd + T   # → LCSG(KC_T)

  # 4修飾キー（HYPR）
  Y: Ctrl + Shift + Alt + Cmd + Y  # → HYPR(KC_Y)
```

### 順序無関係

修飾キーの順序は関係ありません。どちらも同じQMKコードにコンパイルされます：

```yaml
Q: Shift + Cmd + Q    # → LSG(KC_Q)
W: Cmd + Shift + W    # → LSG(KC_W)  # 順序が違っても同じ
```

### サポートする修飾キー

#### 左側修飾キー（デフォルト）

| 記述 | QMK関数 | 説明 |
|-----|---------|------|
| `Shift` | `LSFT` | 左Shift |
| `Ctrl`, `Control` | `LCTL` | 左Ctrl |
| `Alt`, `Option` | `LALT` | 左Alt/Option |
| `Cmd`, `Command`, `Win`, `Gui` | `LGUI` | 左Cmd/Win |

#### 右側修飾キー（明示的）

| 記述 | QMK関数 | 説明 |
|-----|---------|------|
| `RShift` | `RSFT` | 右Shift |
| `RCtrl`, `RControl` | `RCTL` | 右Ctrl |
| `RAlt`, `ROption` | `RALT` | 右Alt/Option |
| `RCmd`, `RCommand`, `RWin`, `RGui` | `RGUI` | 右Cmd/Win |

### QMKショートカット一覧

Cornixは以下のQMKショートカットを自動検出します：

#### 2修飾キー

| 組み合わせ | QMK | 組み合わせ | QMK |
|----------|-----|----------|-----|
| Ctrl + Shift | LCS | RCtrl + RShift | RCS |
| Ctrl + Alt | LCA | RCtrl + RAlt | RCA |
| Ctrl + Cmd | LCG | RCtrl + RCmd | RCG |
| Shift + Alt | LSA | RShift + RAlt | RSA |
| Shift + Cmd | LSG | RShift + RCmd | RSG |
| Alt + Cmd | LAG | RAlt + RCmd | RAG |

#### 3修飾キー

| 組み合わせ | QMK | 説明 |
|----------|-----|------|
| Ctrl + Shift + Alt | MEH | MEHキー |
| Ctrl + Shift + Cmd | LCSG | 左3修飾 |
| Ctrl + Alt + Cmd | LCAG | 左3修飾 |
| Shift + Alt + Cmd | LSAG | 左3修飾 |

#### 4修飾キー

| 組み合わせ | QMK | 説明 |
|----------|-----|------|
| Ctrl + Shift + Alt + Cmd | HYPR | HYPRキー |

### スペースの柔軟性

スペースの有無は自由です：

```yaml
Q: Cmd + Q      # 推奨（読みやすい）
W: Cmd+W        # これも可能
E: Cmd  +  E    # これも可能
```

### キーエイリアスとの併用

キーにはエイリアスも使用できます：

```yaml
mapping:
  Q: Cmd + Space      # → LGUI(KC_SPACE)
  W: Shift + Tab      # → LSFT(KC_TAB)
  E: Ctrl + Enter     # → LCTL(KC_ENTER)
  R: Alt + KC_ESCAPE  # → LALT(KC_ESCAPE)
```

### 使用例

#### アプリケーション操作

```yaml
mapping:
  Q: Cmd + Q          # アプリ終了
  W: Cmd + W          # ウィンドウを閉じる
  N: Cmd + N          # 新規ウィンドウ
  T: Cmd + T          # 新規タブ
```

#### エディタショートカット

```yaml
mapping:
  C: Cmd + C          # コピー
  V: Cmd + V          # ペースト
  X: Cmd + X          # カット
  Z: Cmd + Z          # アンドゥ
  S: Cmd + S          # 保存
```

#### 高度な組み合わせ

```yaml
mapping:
  F: Ctrl + Shift + F     # → LCS(KC_F) - プロジェクト検索
  R: Ctrl + Shift + R     # → LCS(KC_R) - リファクタリング
  P: Ctrl + Shift + P     # → LCS(KC_P) - コマンドパレット
```

### エスケープハッチ

QMK関数構文を直接記述することも可能です：

```yaml
mapping:
  Q: LGUI(KC_Q)           # QMK構文で直接記述
  W: Cmd + W              # 修飾キー表現（推奨）
```

### Decompile時の動作

**⚠️ 重要 - 不可逆変換**: `cornix decompile`コマンドは、修飾キー表現を自動的に元に戻しません。QMK形式のまま保持されます。

```yaml
# compile前（元のYAML）
mapping:
  Q: Cmd + Q

# layout.vil（コンパイル後）
# → LGUI(KC_Q)

# decompile後（YAML）
mapping:
  Q: LGUI(Q)    # 修飾キー表現には戻らない
```

**理由**: layout.vilファイルにはQMK形式のみが含まれており、元の記述方法（修飾キー表現 vs QMK構文）の情報は失われます。また、QMK関数は様々な方法で記述できるため（`LGUI(KC_Q)`、`Cmd + Q`、`LGUI_T(KC_Q)`など）、元の記述方法を正確に復元することは困難です。

**影響**:
- **初回decompile**: layout.vilから生成されたYAMLは常にQMK形式（例: `LGUI(Q)`）
- **編集後のround-trip**: 修飾キー表現（`Cmd + Q`）で記述 → compile → decompile → QMK形式（`LGUI(Q)`）に変換される
- **手動維持**: 修飾キー表現を使い続けたい場合は、YAMLファイルを手動で編集する必要があります

**ベストプラクティス**:
1. **バージョン管理を使用**: `git`等でYAMLファイルをバージョン管理し、decompile後に`git diff`で確認
2. **Round-trip後は手動修正**: 必要に応じてQMK形式を修飾キー表現に戻す
3. **混在も可能**: 同じレイヤー内でQMK形式と修飾キー表現を混在させることができます

**Round-trip整合性**:
修飾キー表現は元に戻りませんが、QMK形式としてのround-trip整合性は完全に保証されています：

```bash
# 1. 修飾キー表現を使用したYAML作成
echo "Q: Cmd + Q" > config/layers/0_base.yaml

# 2. Compile
cornix compile  # → layout.vilに LGUI(KC_Q)

# 3. Decompile
mv config config.backup
cornix decompile  # → config/layers/*.yamlに LGUI(Q)

# 4. Recompile
cornix compile

# 5. 検証
ruby bin/diff_layouts  # ✓ FILES ARE IDENTICAL（QMK形式として完全一致）
```

### 制限事項

1. **プラス記号をキーとして使用**: `Shift + +`は構文解析できません。代わりに`LSFT(KC_PLUS)`を使用してください。

2. **関数をキーとして使用**: `Cmd + LT(1, Space)`は構文解析できません。代わりに`LGUI(LT(1, Space))`を使用してください。

3. **修飾キーをキーとして使用**: 可能ですが、明示的に記述してください：
   ```yaml
   Q: Shift + Shift    # → LSFT(KC_LSHIFT)（スティッキーShift）
   ```

## キーコードエイリアス

キーコードエイリアスは`lib/cornix/keycode_aliases.yaml`に固定ファイルとして配置されています。このファイルは、QMK公式ドキュメント([https://docs.qmk.fm/keycodes](https://docs.qmk.fm/keycodes))に基づいた包括的なキーコード定義を提供します。

**重要**: このファイルはシステムが提供する参照ファイルであり、`config/`ディレクトリには生成されません。コンパイル時に自動的に参照されます。

### 対応しているキーコード

`lib/cornix/keycode_aliases.yaml`には以下の内容が網羅されています：

- **Basic Keycodes**: 文字、数字、記号、ファンクションキー、ナビゲーションキー、修飾キー
- **Layer Switching**: `MO()`, `DF()`, `TG()`, `TO()`, `TT()`, `OSL()`, `LT()`
- **Modifiers**: Mod-Tap (`MT`, `LCTL_T`, etc.), One Shot Modifiers (`OSM`), 修飾キー組み合わせ (`C()`, `S()`, `A()`, `G()`)
- **Media Keys**: 音量調整、再生/停止、メディアコントロール
- **Mouse Keys**: マウス移動、ボタン、ホイール操作
- **Backlight/RGB**: バックライトとRGB制御
- **Quantum Keys**: リセット、デバッグ、EEPROM操作

### エイリアスの例

```yaml
aliases:
  # 基本キー
  A: KC_A
  Space: KC_SPACE
  Enter: KC_ENTER
  Escape: KC_ESCAPE

  # 修飾キー
  LShift: KC_LSHIFT
  LCmd: KC_LGUI
  LCtrl: KC_LCTRL

  # 記号（そのまま使用可能）
  "-": KC_MINUS
  "=": KC_EQUAL
  "[": KC_LBRACKET
  "]": KC_RBRACKET

  # メディアキー
  VolumeUp: KC_VOLU
  VolumeDown: KC_VOLD
  Mute: KC_MUTE

  # 特殊キー
  Transparent: KC_TRNS
  Trans: KC_TRNS
  ___: KC_TRNS
  NoKey: KC_NO
```

### レイヤーファイルでの使用例

```yaml
# config/layers/1_symbol.yaml
overrides:
  # 基本的なキー
  Q: LShift
  W: Space

  # レイヤー切り替え
  fn: MO(1)                    # 押している間レイヤー1
  raise: TG(2)                 # レイヤー2をトグル

  # Mod-Tap (長押しで修飾キー、タップで通常キー)
  A: LCTL_T(A)                # 長押しでCtrl、タップでA

  # レイヤータップ
  space: LT(1, Space)         # 長押しでレイヤー1、タップでSpace

  # 透過キー（下のレイヤーを通す）
  B: Trans                    # または Transparent, ___
```

**注意**: `decompile`で生成されるファイルは自動的にエイリアス形式を使用しますが、手動で`KC_A`や`Transparent`などを記述しても動作します（compile時に同等に扱われます）。

## Position Map（物理位置マッピング）

`position_map.yaml`は、キーボードの物理位置とシンボル名のマッピングを定義します。このファイルにより、レイヤーファイルで`Q`や`A`などの直感的な名前でキーを参照できます。

### ファイルの配置と生成

**システムテンプレート**: `lib/cornix/position_map.yaml`
- システムが提供するデフォルトテンプレート（Cornixの標準レイアウト）
- ユーザーは直接編集しません

**ユーザー設定**: `config/position_map.yaml`
- `cornix decompile`実行時に`lib/cornix/position_map.yaml`から自動生成
- **ユーザーがカスタマイズ可能**（シンボル名を自由に変更できます）
- `cornix compile`実行時に読み込まれます

**動作フロー**:
```
1. cornix decompile
   → lib/cornix/position_map.yaml（テンプレート）を読み込み
   → config/position_map.yaml を生成

2. ユーザーがシンボル名をカスタマイズ（任意）
   → config/position_map.yaml を編集

3. cornix compile
   → config/position_map.yaml（ユーザー版）を読み込み
   → layout.vil を生成
```

**重要な設計原則**:
- `lib/cornix/position_map.yaml`: **再構築不要**のテンプレート（layout.vilの実データではない）
- `config/position_map.yaml`: **ユーザー専用**のカスタマイズ可能なファイル

### ファイル形式

物理位置とシンボル名のマッピングを定義します。

```yaml
left_hand:
  row0: [tab, Q, W, E, R, T]
  row1: [lctrl, A, S, D, F, G]
  row2: [lshift, Z, X, C, V, B]
  row3: [caps, fn, option, command, space, esc]

right_hand:
  row0: [Y, U, I, O, P, backspace]
  row1: [H, J, K, L, colon, backslash]
  row2: [N, M, comma, dot, up, rshift]
  row3: [enter, raise, lang, left, down, right]

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

### キーの配列順序

- **left_hand**: 左手側のキーは**物理的に左から右**へ `col0`, `col1`, `col2`, ... と並びます
- **right_hand**: 右手側のキーも**物理的に左から右**へ `col0`, `col1`, `col2`, ... と並びます
  - 例：`row0` は `Y` (左端) → `U` → `I` → `O` → `P` → `backspace` (右端)

各行には6つのキーが含まれます。ロータリーエンコーダーのプッシュボタンは `encoders` セクションで別途定義されます。

このマッピングにより、レイヤーファイルで `Q` や `A` などの直感的な名前でキーを参照できます。

## マクロで使用可能なアクション

```yaml
# キーをタップ
- action: tap
  key: A              # 単一キー

- action: tap
  keys: [A, B, C]     # 複数キーを順番にタップ

# キーを押し下げたまま
- action: down
  key: LShift

- action: down
  keys: [LCmd, LShift]  # 複数キー同時押し下げ

# キーを離す
- action: up
  key: LShift

# テキストを入力
- action: text
  content: "function ()"

# 遅延
- action: delay
  duration: 100  # ms
```

## ライブラリ機能（コミュニティマクロ）

`library/`ディレクトリにコミュニティが作成したマクロやタップダンスを配置できます。

```yaml
# config/metadata.yaml
library:
  enabled: true

  macros:
    - name: vscode_shortcuts
      enabled: true
    - name: emacs_keybinds
      enabled: false
```

⚠️ **セキュリティ注意**: ライブラリマクロを使用する際は、必ず内容を確認してから有効化してください。

## 開発

### bin/アーキテクチャ

Cornixのコマンドラインインターフェースは、メンテナンス性を重視したクリーンな構造になっています。

#### ディレクトリ構造

```
bin/
├── cornix                    # メインCLIディスパッチャー（~62行）
├── subcommands/              # サブコマンド実装
│   ├── compile.rb           # 自動検証付きコンパイル
│   ├── decompile.rb         # ロック保護付きデコンパイル
│   ├── validate.rb          # 検証専用
│   ├── cleanup.rb           # 安全なクリーンアップ
│   └── rename.rb            # RenameCommandラッパー
├── diff_layouts              # Round-tripチェックツール
└── rename_file               # ファイルリネームCLI（上級者向け）
```

#### Delegation Pattern（委譲パターン）

`bin/cornix`はシンプルなディスパッチャーとして機能し、実際の処理は各サブコマンドに委譲します。

```ruby
# bin/cornix の抜粋
case command
when 'compile'
  load File.expand_path('subcommands/compile.rb', __dir__)
when 'decompile'
  load File.expand_path('subcommands/decompile.rb', __dir__)
when 'validate'
  load File.expand_path('subcommands/validate.rb', __dir__)
# ...
end
```

**利点**:
- **コードの重複排除**: 100%の重複を削減、全コマンドが`cornix`ディスパッチャーを経由
- **一貫性**: 全サブコマンドで共通の初期化処理
- **メンテナンス性**: 各サブコマンドは独立したファイルで管理

#### 自動検証機能

`cornix compile`は自動的に検証を実行します。これはユーザーが明示的に`validate`を呼び出す必要がないようにするためです。

```ruby
# bin/subcommands/compile.rb の抜粋
# 1. 検証を実行
validator = Cornix::Validator.new(config_dir)
unless validator.validate
  puts validator.errors
  exit 1
end

# 2. コンパイルを実行
compiler = Cornix::Compiler.new(config_dir)
compiler.compile
```

#### CLI共通ヘルパー（CliHelpers）

全サブコマンドで共有されるユーティリティ関数を提供します。

```ruby
# lib/cornix/cli_helpers.rb
module Cornix
  module CliHelpers
    # config/ディレクトリの既存ファイル保護
    def self.check_config_lock(config_dir)
      # ...
    end

    # config/ディレクトリの存在確認
    def self.ensure_config_exists(config_dir)
      # ...
    end

    # 生成ファイルの安全な削除
    def self.cleanup(config_dir, layout_path)
      # ...
    end
  end
end
```

#### Data Flow（データフロー）

```
ユーザー入力
    ↓
cornix [command] [args]
    ↓
bin/cornix（ディスパッチャー）
    ↓
    ├─ compile.rb → Validator → Compiler → layout.vil
    ├─ decompile.rb → CliHelpers.check_config_lock → Decompiler → config/
    ├─ validate.rb → Validator → エラー/成功
    ├─ cleanup.rb → CliHelpers.cleanup → ファイル削除
    └─ rename.rb → RenameCommand → FileRenamer → config/
```

### ディレクトリ構造

```
cornix-layout/
├── README.md                   # 日本語README
├── README.en.md                # 英語README
├── bin/
│   ├── compile                 # コンパイラ
│   ├── decompile               # デコンパイラ
│   └── verify                  # 検証スクリプト
├── lib/
│   └── cornix/
│       ├── compiler.rb
│       ├── decompiler.rb
│       ├── keycode_resolver.rb
│       ├── keycode_aliases.yaml # システム提供のキーコードエイリアス
│       ├── position_map.yaml    # デフォルトの物理位置マップテンプレート
│       └── position_map.rb
├── config/                     # 設定ファイル
└── layout.vil                  # 生成されるファイル
```

### テスト

プロジェクトには包括的なRSpecテストスイートが含まれています。

```bash
# 全テストを実行
bundle exec rspec

# 特定のテストファイルを実行
bundle exec rspec spec/compiler_spec.rb
bundle exec rspec spec/decompiler_spec.rb
bundle exec rspec spec/keycode_resolver_spec.rb
bundle exec rspec spec/position_map_spec.rb
bundle exec rspec spec/validator_spec.rb
bundle exec rspec spec/integration_spec.rb

# 詳細な出力で実行
bundle exec rspec --format documentation
```

#### テストスイート詳細

**総テストケース数**: 479テスト（全成功）
**総行数**: 5,400行以上
**実行時間**: 約1.8秒

<details>
<summary><b>テストファイル別内訳</b></summary>

| テストファイル | テスト数 | 内容 |
|--------------|---------|------|
| `keycode_parser_spec.rb` | 106 | KeycodeParser機能（参照形式パース、関数パース、修飾キー表現パース、unparse） |
| `modifier_expression_compiler_spec.rb` | 52 | ModifierExpressionCompiler機能（QMKショートカット自動検出、修飾キーエイリアス） |
| `compiler_spec.rb` | 48 | Compiler機能（キーコード変換、レイヤー/マクロ/タップダンス/コンボのコンパイル） |
| `reference_resolver_spec.rb` | 44 | ReferenceResolver機能（名前⇔インデックス解決、キャッシング、検証） |
| `file_renamer_spec.rb` | 57 | FileRenamer機能（リネーム、YAML更新、バックアップ/ロールバック、レイヤー参照更新） |
| `decompiler_spec.rb` | 37 | Decompiler機能（QMK→エイリアス変換、YAML生成、レガシー→name-basedアップグレード） |
| `validator_spec.rb` | 73 | Validator機能（Phase 1全検証項目、修飾キー表現検証） |
| `keycode_resolver_spec.rb` | 21 | KeycodeResolver機能（エイリアス⇔QMK双方向変換） |
| `position_map_spec.rb` | 17 | PositionMap機能（物理位置マッピング） |
| `integration_spec.rb` | 17 | 統合テスト（フルラウンドトリップ、参照システム統合、修飾キー表現統合） |

</details>

<details>
<summary><b>テストカバレッジ詳細</b></summary>

**Flexible Reference System**（参照システム）:
- Name-based参照のパース・解決
- Index-based参照のパース・解決
- Legacy参照の後方互換性
- Decompilerによる自動アップグレード（Legacy → Name-based）
- FileRenamerによる選択的更新（Name-basedのみ自動更新）
- Validatorによる差別的検証（Name-based: 存在確認、Index-based: 範囲のみ）
- ラウンドトリップ整合性（全形式で完全一致）

**Modifier Expression System**（修飾キー表現）:
- 修飾キー表現のパース（`Cmd + Q`等）
- QMKショートカット自動検出（LCS, LSG, MEH, HYPR等）
- 順序無関係マッチング（`Cmd + Shift` = `Shift + Cmd`）
- 修飾キーエイリアス解決（Command, Win, Option等）
- ネスト関数フォールバック
- Validatorによる検証（修飾キー名、キー名）
- ラウンドトリップ整合性（QMK形式として完全一致）

**Compiler**:
- キーコード解決（エイリアス → QMK形式）
- 関数引数処理（レイヤー番号保持、修飾キー引数変換）
- レイヤー構造コンパイル
- マクロ/タップダンス/コンボのコンパイル
- 参照システム統合
- 修飾キー表現統合

**Decompiler**:
- QMK → エイリアス変換（逆解決）
- YAML生成（読みやすいフォーマット）
- レガシー形式の自動アップグレード
- Position Mapテンプレート生成
- ラウンドトリップ整合性

**Validator**:
- Phase 1全検証項目（8項目）
- 参照形式検証（Name-based、Index-based、Legacy）
- 修飾キー表現検証
- エラーメッセージの明瞭性

**FileRenamer**:
- ファイルリネーム（インデックスプレフィックス保持）
- YAML内容更新（name、descriptionフィールド）
- バックアップ/ロールバック（トランザクション型）
- レイヤー参照自動更新（Name-basedのみ）
- コンパイル検証

**Integration**:
- Compile → Decompile → Compile フルラウンドトリップ
- 全参照形式での整合性
- 修飾キー表現のQMK形式保持
- データ損失なし

</details>

**Round-trip Check** (手動検証):
```bash
# 1. 既存configをバックアップ
mv config config.backup

# 2. オリジナルからdecompile
cornix decompile  # tmp/layout.vil を使用

# 3. 生成された設定からcompile
cornix compile

# 4. 比較
ruby bin/diff_layouts
# 期待結果: === ✓ FILES ARE IDENTICAL ===
```

## トラブルシューティング

よくある問題と解決方法をまとめました。

<details>
<summary><b>よくある問題</b></summary>

### 1. Decompileがブロックされる

**症状**:
```
⚠️  Error: config/ directory already contains configuration files.
```

**原因**: 既存の`config/`ディレクトリが存在するため、ロック保護機能が作動しています。

**解決方法**:
```bash
# オプション1: cleanupコマンドを使用
cornix cleanup

# オプション2: 手動でバックアップ
mv config config.backup

# 再度デコンパイル
cornix decompile
```

---

### 2. コンパイルエラー: Invalid keycode

**症状**:
```
Error: Layer 0_base.yaml, symbol 'Q': Invalid keycode 'Spce'
```

**原因**: キーコードのタイプミス（`Spce` → 正しくは `Space`）

**解決方法**:
```bash
# 1. エラーメッセージから該当ファイルと行を特定
vim config/layers/0_base.yaml

# 2. タイプミスを修正
# Spce → Space

# 3. 検証
cornix validate

# 4. 再コンパイル
cornix compile
```

**よくあるタイプミス**:
- `Spce` → `Space`
- `Entr` → `Enter`
- `Backspce` → `Backspace`
- `Trans` → `Transparent`（どちらも正しいが`Trans`が推奨）

---

### 3. 未定義のポジションシンボル

**症状**:
```
Error: Layer 0_base.yaml: Unknown position symbol 'UnknownKey'
```

**原因**: `position_map.yaml`に定義されていないシンボルを参照しています。

**解決方法**:
```bash
# 1. position_map.yamlを確認
cat config/position_map.yaml

# 2. レイヤーファイルで使用しているシンボルを確認
grep "UnknownKey" config/layers/*.yaml

# 3. オプションA: position_map.yamlにシンボルを追加
vim config/position_map.yaml

# 3. オプションB: レイヤーファイルのシンボルを修正
vim config/layers/0_base.yaml
```

---

### 4. レイヤー番号の重複

**症状**:
```
Error: Duplicate layer index 1: 1_symbol.yaml, 1_number.yaml
```

**原因**: 同じレイヤーインデックス（`1_`）を持つファイルが複数存在します。

**解決方法**:
```bash
# どちらかのファイルのレイヤー番号を変更
mv config/layers/1_number.yaml config/layers/2_number.yaml
```

---

### 5. マクロ名の重複

**症状**:
```
Error: Duplicate macro name 'Bracket Pair' in files: 00_bracket.yml, 01_bracket_copy.yml
```

**原因**: 同じ`name`フィールドを持つマクロファイルが複数存在します。

**解決方法**:
```bash
# どちらかのファイルの名前を変更
vim config/macros/01_bracket_copy.yml
# name: "Bracket Pair" → "Bracket Pair Alt"
```

---

### 6. 存在しないマクロ/タップダンスを参照

**症状**:
```
Error: Layer 0_base.yaml, symbol 'Q': Macro 'Unknown Macro' not found
```

**原因**: Name-based参照で存在しない名前を指定しています。

**解決方法**:
```bash
# 1. 存在するマクロ名を確認
ls config/macros/
cat config/macros/*.yml | grep "^name:"

# 2. レイヤーファイルの参照を修正
vim config/layers/0_base.yaml
# Macro('Unknown Macro') → Macro('Existing Macro')
```

---

### 7. Round-trip checkが失敗する

**症状**:
```
=== ✗ FILES DIFFER ===
Layer 0: ...
```

**原因**: Compile/Decompileプロセスでデータの不整合が発生しています。

**解決方法**:
```bash
# 1. どのセクションで差分が発生しているか確認
ruby bin/diff_layouts

# 2. バグレポート用に詳細情報を収集
cp tmp/layout.vil tmp/layout.original.vil
cp layout.vil tmp/layout.recompiled.vil

# 3. GitHubでissue報告
# https://github.com/anthropics/claude-code/issues
```

---

### 8. 修飾キー表現がDecompile後に消える

**症状**: `Cmd + Q`で記述したが、decompile後は`LGUI(Q)`になっている。

**原因**: 仕様です。Decompilerは修飾キー表現を自動的に元に戻しません。

**説明**:
- layout.vilにはQMK形式のみが保存されます
- 元の記述方法（修飾キー表現 vs QMK構文）の情報は失われます
- 詳細は「修飾キー表現 > Decompile時の動作」セクションを参照

**対処方法**:
- バージョン管理（git）を使用して手動で修飾キー表現を維持
- QMK形式を受け入れて使用（機能的には同等）

---

### 9. Claude Code CLI (`claude`コマンド) が見つからない

**症状**:
```
Error: claude command not found. Please install Claude Code CLI.
```

**原因**: `cornix rename`コマンドに必要なClaude Code CLIがインストールされていません。

**解決方法**:
```bash
# Claude Code CLIをインストール
# https://claude.ai/download

# インストール確認
claude --version
```

---

### 10. YAML構文エラー

**症状**:
```
Error: config/layers/0_base.yaml: Invalid YAML syntax - mapping values are not allowed here
```

**原因**: YAMLの構文エラー（インデント不正、不正な文字等）

**解決方法**:
```bash
# 1. エラーメッセージから該当ファイルを確認
vim config/layers/0_base.yaml

# 2. よくある原因
# - インデントがスペースとタブ混在
# - キーの後のコロン忘れ
# - 文字列に特殊文字が含まれている（クォートが必要）

# 3. YAMLバリデーターで確認（オプション）
ruby -ryaml -e "YAML.load_file('config/layers/0_base.yaml')"
```

</details>

### 設定ファイルの検証

コンパイル前に設定ファイルの妥当性を検証することを強く推奨します：

```bash
# 設定ファイルを検証
cornix validate

# 検証に成功した場合
✓ All validations passed

# 検証に失敗した場合
✗ Validation failed:
  Error: Layer 0_base.yaml, symbol 'LT1': Invalid keycode 'InvalidKeycode'
  Error: Layer 1_symbols.yaml: Unknown position symbol 'UnknownSymbol'
```

**検証内容**（Phase 1実装済み）:

1. **YAML構文の正当性**
   - 全YAMLファイルの構文エラーを検出
   - パースエラーのある場合、分かりやすいエラーメッセージを表示

2. **メタデータの妥当性**
   - `metadata.yaml`の存在チェック
   - 必須フィールド（`keyboard`, `version`, `uid`, `vial_protocol`, `via_protocol`）の検証
   - `vendor_product_id`の形式チェック（`0xXXXX`）
   - `matrix`設定の型・範囲チェック

3. **Position Map の妥当性**
   - `position_map.yaml`内のシンボルが一意であることを検証
   - 同じシンボルが複数の物理位置に割り当てられている場合はエラー
   - 左手・右手間での重複も検出

4. **キーコードの妥当性**
   - レイヤー内の全キーコードが有効なQMKキーコードまたはエイリアスか検証
   - 関数形式のキーコード（`MO(1)`, `LSFT(A)`, `LT(2, Space)`等）の引数も検証
   - タイプミスの早期発見

5. **Position Map参照の整合性**
   - レイヤーで使用されるシンボル（`LT1`, `RT1`等）が`position_map.yaml`に定義されているか検証
   - 未定義のポジションシンボル参照を検出

6. **レイヤーインデックスの妥当性**
   - レイヤーファイル名が数字で始まること（例: `0_base.yaml`）
   - レイヤーインデックスが0-9の範囲内
   - 重複するレイヤーインデックスがないこと

7. **マクロ/タップダンス/コンボ名の一意性**
   - 各ファイルに`name`フィールドが存在
   - 名前がファイル間で一意

8. **レイヤー内の参照妥当性**
   - `MACRO(name)`, `TD(name)`参照が実在する名前を指していること

**推奨ワークフロー**:

```bash
# 設定を編集
vim config/layers/0_base.yaml

# 検証＆コンパイル（自動検証）
cornix compile
```

### コンパイルエラー

よくあるエラー：

- **YAML構文エラー**: インデント不正、不正な文字
- **無効なキーコード**: タイプミス（`Spce` → 正しくは `Space`）
- **未定義のポジションシンボル**: `position_map.yaml`に存在しないシンボルを参照
- **レイヤー番号の重複**: 同じ番号のレイヤーファイルが複数存在
- **マクロ名の重複**: 同じ名前のマクロファイルが複数存在
- **存在しない参照**: `MACRO(unknown_macro)`など、存在しないマクロを参照

詳細は「トラブルシューティング」セクションを参照してください。

## Tips & Best Practices

Cornixを効果的に使うためのヒントとベストプラクティスをまとめました。

### Configuration Management（設定管理）

**1. Name-based参照を推奨**

```yaml
# ✅ 推奨: Name-based形式
Q: Macro('End of Line')
W: TapDance('Escape or Layer')

# ❌ 非推奨: Index-based/Legacy形式（可読性が低い）
Q: Macro(5)
W: TD(2)
```

**理由**:
- 設定ファイルが自己文書化され、可読性が高い
- `cornix rename`でファイル名変更時に自動更新される
- チーム開発で分かりやすい

**2. 修飾キー表現を活用**

```yaml
# ✅ 推奨: 修飾キー表現（読みやすい）
Q: Cmd + Q
W: Ctrl + Shift + F

# ❌ 非推奨: QMK構文（機能的には同等だが読みにくい）
Q: LGUI(KC_Q)
W: LCS(KC_F)
```

**注意**: Decompile後は自動的にQMK形式に戻ります。バージョン管理で維持してください。

**3. バージョン管理を使用**

```bash
# Gitで設定ファイルを管理
git init
git add config/
git commit -m "Initial keyboard configuration"

# 変更後に差分確認
vim config/layers/0_base.yaml
git diff config/

# コミット
git commit -am "Update base layer: add Cmd+Q shortcut"
```

**理由**:
- 設定の履歴が追跡できる
- 誤った変更を簡単にロールバックできる
- Decompile後の修飾キー表現を手動で復元しやすい

**4. 定期的な検証**

```bash
# 編集前
cornix validate

# 編集
vim config/layers/0_base.yaml

# 編集後（自動検証付き）
cornix compile
```

### File Naming（ファイル命名）

**1. 説明的なファイル名を使用**

```bash
# ✅ 良い例
config/layers/0_base.yaml
config/layers/1_symbol.yaml
config/layers/2_number.yaml
config/macros/00_bracket_pair.yml
config/macros/01_end_of_line.yml

# ❌ 悪い例（汎用的すぎる）
config/layers/0_layer.yaml
config/layers/1_layer.yaml
config/macros/00_macro.yml
config/macros/01_macro.yml
```

**理由**:
- ファイル名だけで内容が推測できる
- `cornix rename`で自動リネーム可能

**2. インデックスプレフィックスを保持**

```bash
# リネーム時にインデックスを保持
mv config/macros/03_macro.yml config/macros/03_end_of_line.yml
# ✅ 正しい: 03_ を保持

mv config/macros/03_macro.yml config/macros/05_end_of_line.yml
# ❌ 間違い: インデックスを変更すると参照が壊れる
```

**理由**:
- インデックスはlayout.vilでの順序を決定する
- 変更するとレイヤーからの参照が不整合になる

### Claude Code Integration

**1. 編集前後の検証**

```bash
# Claude Codeで編集する前
cornix validate

# Claude Codeセッション
claude

# セッション内でファイル編集
# ...

# 編集後
cornix compile  # 自動検証付き
```

**2. Skillsを活用**

```bash
# インテリジェントリネーム
claude
> /rename

# カスタムスキルがあれば活用
> /compile
> /validate
```

**3. 段階的な変更**

```yaml
# ❌ 悪い例: 一度に大量の変更
Q: Cmd + Q
W: Cmd + W
E: Cmd + E
# ... 50行の変更

# ✅ 良い例: 小さな変更を繰り返す
Q: Cmd + Q
# コンパイル & テスト

W: Cmd + W
# コンパイル & テスト
```

**理由**: エラーが発生した際に原因を特定しやすい

### Common Mistakes to Avoid（よくある間違い）

<details>
<summary><b>1. レイヤー番号を数値で指定してしまう</b></summary>

```yaml
# ❌ 間違い
Q: MO(KC_3)    # レイヤー3への切り替え

# ✅ 正しい
Q: MO(3)       # 数値をそのまま指定
```

**理由**: レイヤー番号は数値のまま保持される（`KC_3`はキーコードの「3」キー）

</details>

<details>
<summary><b>2. 修飾キーの引数を変換しない</b></summary>

```yaml
# ❌ 間違い
Q: LSFT(1)     # これは「Shift+1」ではなくエラー

# ✅ 正しい（自動変換される）
Q: LSFT(1)     # コンパイル時に自動的にLSFT(KC_1)に変換

# または明示的に
Q: LSFT(KC_1)
```

**注**: Compilerは自動的に修飾キー関数の数値引数を`KC_*`形式に変換します。

</details>

<details>
<summary><b>3. すべての参照形式が自動更新されると期待</b></summary>

```yaml
# リネーム前
config/macros/03_macro.yml: name: "Old Name"

# レイヤー内
Q: Macro('Old Name')  # ✅ 自動更新される
W: Macro(3)           # ❌ 更新されない
E: M3                 # ❌ 更新されない

# リネーム後（cornix rename実行）
Q: Macro('New Name')  # ✅ 自動更新された
W: Macro(3)           # ❌ そのまま（意図的）
E: M3                 # ❌ そのまま（意図的）
```

**理由**: Name-based参照のみが自動更新されます。Index-based/Legacy形式はユーザーの選択を尊重して保持されます。

</details>

<details>
<summary><b>4. Decompile後に修飾キー表現が戻ると期待</b></summary>

```yaml
# Compile前
Q: Cmd + Q

# layout.vil（コンパイル後）
# LGUI(KC_Q)

# Decompile後
Q: LGUI(Q)    # ❌ 修飾キー表現には戻らない
```

**理由**: layout.vilにはQMK形式のみが保存され、元の記述方法の情報は失われます。

**対処**: バージョン管理（git）で手動維持、またはQMK形式を受け入れる。

</details>

<details>
<summary><b>5. インデックスプレフィックスを変更してしまう</b></summary>

```bash
# ❌ 間違い
mv config/macros/03_macro.yml config/macros/05_macro.yml
# インデックスが03→05に変更され、レイヤーからの参照が壊れる

# ✅ 正しい
mv config/macros/03_macro.yml config/macros/03_end_of_line.yml
# インデックス03を保持、ファイル名のみ変更
```

**理由**: インデックスはlayout.vilでの順序を決定し、レイヤーから参照されます。

</details>

### パフォーマンスと効率

**1. ReferenceResolverのキャッシング**

ReferenceResolverは初回参照時にYAMLファイルをキャッシュします（約7KB、100ms）。2回目以降は即座に解決されます。

**2. Validatorの活用**

コンパイル前に`cornix validate`を実行することで、エラーを早期発見できます。ただし、`cornix compile`は自動的に検証を実行するため、通常は不要です。

**3. バッチリネーム**

大量のファイルをリネームする場合は、`cornix rename`のバッチモードを使用すると効率的です（トランザクション型処理）。

## コントリビューション

プルリクエスト歓迎です！

1. このリポジトリをフォーク
2. フィーチャーブランチを作成 (`git checkout -b feature/amazing-feature`)
3. コミット (`git commit -m 'Add amazing feature'`)
4. プッシュ (`git push origin feature/amazing-feature`)
5. プルリクエストを作成

## ライセンス

MIT License

## 参考リンク

- [Vial Documentation](https://get.vial.today/)
- [QMK Firmware Documentation](https://docs.qmk.fm/)
- [QMK Keycodes](https://docs.qmk.fm/keycodes_basic)

---

Made with ❤️ for the Cornix keyboard community

---

## Appendix

### Complete Keycode List

Cornixは337個のQMK公式キーコードエイリアスをサポートしています。完全なリストは`lib/cornix/keycode_aliases.yaml`を参照してください。

<details>
<summary><b>主要なキーコードカテゴリー</b></summary>

**Basic Keycodes（基本キー）**:
- 文字: `A`-`Z`
- 数字: `0`-`9`
- ファンクションキー: `F1`-`F24`
- ナビゲーション: `Up`, `Down`, `Left`, `Right`, `Home`, `End`, `PageUp`, `PageDown`
- 編集: `Enter`, `Escape`, `Backspace`, `Tab`, `Space`, `Delete`
- 修飾キー: `LShift`, `RShift`, `LCtrl`, `RCtrl`, `LAlt`, `RAlt`, `LCmd` (LGUI), `RCmd` (RGUI)

**記号キー**:
```yaml
"-": KC_MINUS
"=": KC_EQUAL
"[": KC_LBRACKET
"]": KC_RBRACKET
"\\": KC_BSLASH
";": KC_SCOLON
"'": KC_QUOTE
"`": KC_GRAVE
",": KC_COMMA
".": KC_DOT
"/": KC_SLASH
```

**Layer Switching（レイヤー切り替え）**:
- `MO(layer)`: Momentary（押している間）
- `TG(layer)`: Toggle（トグル）
- `TO(layer)`: To（切り替え）
- `TT(layer)`: Tap Toggle（タップでトグル、長押しでMO）
- `DF(layer)`: Default（デフォルトレイヤー変更）
- `OSL(layer)`: One Shot Layer（1回だけ）
- `LT(layer, key)`: Layer Tap（長押しでレイヤー、タップでキー）

**Modifiers（修飾キー）**:
- Mod-Tap: `LCTL_T(key)`, `LSFT_T(key)`, `LALT_T(key)`, `LGUI_T(key)`
- One Shot Modifiers: `OSM(mod)`
- 修飾キー組み合わせ: `C(key)`, `S(key)`, `A(key)`, `G(key)`
- QMKショートカット: `LCS`, `LSG`, `MEH`, `HYPR`（詳細は「QMK Modifier Shortcuts」参照）

**Media Keys（メディアキー）**:
- `VolumeUp`, `VolumeDown`, `Mute`
- `MediaPlayPause`, `MediaNextTrack`, `MediaPrevTrack`, `MediaStop`
- `MediaFastForward`, `MediaRewind`, `MediaEject`

**Mouse Keys（マウスキー）**:
- 移動: `MouseUp`, `MouseDown`, `MouseLeft`, `MouseRight`
- ボタン: `MouseBtn1`-`MouseBtn8`
- ホイール: `MouseWheelUp`, `MouseWheelDown`, `MouseWheelLeft`, `MouseWheelRight`
- 加速: `MouseAccel0`-`MouseAccel2`

**Special Keys（特殊キー）**:
- `Transparent` / `Trans` / `___`: 透過（下のレイヤーを通す）
- `NoKey`: 無効化
- `Reset`: キーボードリセット
- `Debug`: デバッグモード

**Backlight/RGB**:
- バックライト: `BL_ON`, `BL_OFF`, `BL_TOGG`, `BL_INC`, `BL_DEC`
- RGB: `RGB_TOG`, `RGB_MOD`, `RGB_HUI`, `RGB_SAI`, `RGB_VAI`

</details>

### QMK Modifier Shortcuts

Cornixは20+のQMK修飾キーショートカットを自動検出します。

<details>
<summary><b>全ショートカット一覧</b></summary>

#### 左側修飾キー（L prefix）

**2修飾キー組み合わせ**:
| QMK | 組み合わせ | 説明 |
|-----|----------|------|
| `LCS` | Ctrl + Shift | Left Ctrl + Shift |
| `LCA` | Ctrl + Alt | Left Ctrl + Alt |
| `LCG` | Ctrl + Cmd | Left Ctrl + GUI |
| `LSA` | Shift + Alt | Left Shift + Alt |
| `LSG` | Shift + Cmd | Left Shift + GUI |
| `LAG` | Alt + Cmd | Left Alt + GUI |

**3修飾キー組み合わせ**:
| QMK | 組み合わせ | 説明 |
|-----|----------|------|
| `MEH` | Ctrl + Shift + Alt | MEHキー |
| `LCSG` | Ctrl + Shift + Cmd | Left Ctrl + Shift + GUI |
| `LCAG` | Ctrl + Alt + Cmd | Left Ctrl + Alt + GUI |
| `LSAG` | Shift + Alt + Cmd | Left Shift + Alt + GUI |

#### 右側修飾キー（R prefix）

**2修飾キー組み合わせ**:
| QMK | 組み合わせ | 説明 |
|-----|----------|------|
| `RCS` | RCtrl + RShift | Right Ctrl + Shift |
| `RCA` | RCtrl + RAlt | Right Ctrl + Alt |
| `RCG` | RCtrl + RCmd | Right Ctrl + GUI |
| `RSA` | RShift + RAlt | Right Shift + Alt |
| `RSG` | RShift + RCmd | Right Shift + GUI |
| `RAG` | RAlt + RCmd | Right Alt + GUI |

**3修飾キー組み合わせ**:
| QMK | 組み合わせ | 説明 |
|-----|----------|------|
| `RCSG` | RCtrl + RShift + RCmd | Right Ctrl + Shift + GUI |
| `RCAG` | RCtrl + RAlt + RCmd | Right Ctrl + Alt + GUI |
| `RSAG` | RShift + RAlt + RCmd | Right Shift + Alt + GUI |

#### 特殊組み合わせ

**4修飾キー**:
| QMK | 組み合わせ | 説明 |
|-----|----------|------|
| `HYPR` | Ctrl + Shift + Alt + Cmd | HYPRキー（4修飾キー全て） |

**使用例**:
```yaml
# Cornixで記述
Q: Ctrl + Shift + Alt + Cmd + Q

# 自動的に変換
# → HYPR(KC_Q)
```

</details>

### Position Map Template

`lib/cornix/position_map.yaml`のデフォルトテンプレート構造です。

<details>
<summary><b>テンプレート構造</b></summary>

```yaml
left_hand:
  row0: [tab, Q, W, E, R, T]
  row1: [lctrl, A, S, D, F, G]
  row2: [lshift, Z, X, C, V, B]
  row3: [caps, fn, option, command, space, esc]

right_hand:
  row0: [Y, U, I, O, P, backspace]
  row1: [H, J, K, L, colon, backslash]
  row2: [N, M, comma, dot, up, rshift]
  row3: [enter, raise, lang, left, down, right]

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

**構造**:
- `left_hand` / `right_hand`: 各行（row0-row3）に6キーずつ配置
- `encoders`: ロータリーエンコーダーの設定（push, ccw, cw）

**配列順序**:
- 左手・右手とも**物理的に左から右**へ配列
- 右手の`row0`は`Y`（左端）→ `U` → `I` → `O` → `P` → `backspace`（右端）

**カスタマイズ**:
`config/position_map.yaml`を編集してシンボル名を自由に変更できます。

```yaml
# カスタム例
left_hand:
  row0: [tab, q, w, e, r, t]  # 小文字に変更
  # ...

right_hand:
  row0: [y, u, i, o, p, bs]   # 'backspace' → 'bs' に短縮
  # ...
```

</details>

### Sample Configuration

Cornixでは、ブランチを切り替えることで異なるサンプル設定を利用できます。

<details>
<summary><b>利用可能なサンプル設定</b></summary>

#### 1. 公式の初期キーマップ（推奨）

Cornix公式の初期キーマップをベースに編集したい場合：

```bash
# cornix-default-keymapブランチをチェックアウト
git checkout cornix-default-keymap

# config/ディレクトリを確認
ls config/

# 設定を編集
vim config/layers/0_base.yaml

# コンパイル
cornix compile
```

**特徴**:
- Cornixの標準的なレイアウト
- 初心者に推奨
- ドキュメントと整合性のある設定

#### 2. 作者のキーマップ

作者（プロジェクトメンテナー）のキーマップを参考にしたい場合：

```bash
# authors-keymapブランチをチェックアウト
git checkout authors-keymap

# config/ディレクトリを確認
ls config/

# 設定を閲覧・編集
vim config/layers/0_base.yaml

# コンパイル
cornix compile
```

**特徴**:
- 実際の使用例
- 高度な機能の活用例
- カスタマイズのヒント

#### 3. 自分のlayout.vilから生成

自分のVial設定をベースにする場合：

```bash
# mainブランチに戻る
git checkout main

# 自分のlayout.vilをデコンパイル
cornix decompile ~/Downloads/my_layout.vil

# 生成されたconfig/を編集
vim config/layers/0_base.yaml

# コンパイル
cornix compile
```

#### ブランチの切り替え方

**既存のconfig/がある場合**:

```bash
# 現在の設定をバックアップ
mv config config.my_backup

# ブランチを切り替え
git checkout cornix-default-keymap

# サンプル設定を確認
ls config/
```

**元のブランチに戻る**:

```bash
# mainブランチに戻る
git checkout main

# バックアップを復元
mv config.my_backup config
```

</details>

#### コミュニティ貢献

サンプル設定の提供を歓迎します：
- 新しいブランチで独自のサンプル設定を共有
- プルリクエストで貢献
- `examples/`ディレクトリにドキュメント追加

詳細は「コントリビューション」セクションを参照してください。

