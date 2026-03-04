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

### 既存のlayout.vilから設定ファイルを生成

```bash
# デフォルト（tmp/layout.vil）を使用
ruby bin/decompile

# または、任意のファイルパスを指定
ruby bin/decompile ~/Downloads/layout.vil
ruby bin/decompile /path/to/custom.vil
```

**安全機能**: 既に`config/`ディレクトリに設定ファイルが存在する場合、デコンパイルは自動的にブロックされます。

```bash
# 既存の設定を上書きしたい場合は、まずバックアップ
mv config config.backup

# 新しいlayout.vilをデコンパイル
ruby bin/decompile ~/Downloads/layout.vil
```

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

**注意**: キーコードエイリアス(`keycode_aliases.yaml`)は`lib/cornix/`ディレクトリに固定ファイルとして配置されており、`config/`ディレクトリには生成されません。

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

  # マクロを参照（インデックスで指定）
  A: MACRO(0)

  # タップダンスを参照
  fn: TD(0)
```

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

```bash
ruby bin/compile
```

生成された`layout.vil`をVialでインポートしてキーボードに書き込みます。

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

## position_map.yaml

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
│       └── position_map.rb
├── config/                     # 設定ファイル
└── layout.vil                  # 生成されるファイル
```

### テスト

```bash
# RSpecでテスト実行（今後実装予定）
bundle install
bundle exec rspec
```

## トラブルシューティング

### コンパイルエラー

```bash
# 設定ファイルの検証（今後実装予定）
ruby bin/validate
```

よくあるエラー：

- **レイヤー番号の重複**: 同じ番号のレイヤーファイルが複数存在
- **マクロ名の重複**: 同じ名前のマクロファイルが複数存在
- **存在しない参照**: `MACRO(unknown_macro)`など、存在しないマクロを参照

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
