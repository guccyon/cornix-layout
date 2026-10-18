# Cornix Keyboard Layout Manager

Cornix キーボード用の、人が読み書きできるレイアウト設定管理ツールです。

Vial の `layout.vil` は直接編集しにくいため、YAML の設定ファイルで管理し、`layout.vil` との相互変換と、接続中のキーボードへの直接反映を行います。

[English README](README.en.md)

## 特徴

- 📝 **読みやすい YAML**: レイヤー・マクロ・タップダンス・コンボを個別のファイルで管理し、`#` でコメントも書けます
- 🔤 **エイリアス**: `KC_TAB` → `Tab`、`KC_TRNS` → `Trans`、`LSFT(KC_1)` → `!` のような読みやすい名前で書けます
- ⌨️ **修飾キー表現**: `Cmd + Q`、`Ctrl + Shift + F` のような VS Code 風の書き方ができます
- 🏷️ **名前で参照**: `Macro('Bracket Pair')`、`TapDance('Tab Escape')` のように名前でマクロ・タップダンスを指定できます
- 🔖 **名前付きショートカット**: `shortcuts.yaml` に `前のタブへ: Command + Shift + [` のように定義し、`Shortcut('前のタブへ')` で何か所でも使えます
- 🔄 **双方向変換**: `layout.vil` ⇔ YAML。decompile → compile で 16bit 値が元と一致します
- ✅ **検証**: compile の前に、YAML の構造とキーコード・参照・件数の上限などをすべて検査し、問題を「ファイル: 場所: 内容」でまとめて表示します
- 🔌 **キーボードへ直接反映**: Vial Web を使わずに CLI / MCP サーバーから差分だけを書き込めます（[詳細](#キーボードへの直接反映vial-web-不要)）

## インストール

Ruby（`Data.define` を使うので 3.2 以上。CI は 4.0 系）と Bundler が必要です。

```bash
git clone https://github.com/guccyon/cornix-layout.git
cd cornix-layout
bundle install
```

`bin/cornix` を PATH に通すか、`ruby bin/cornix <コマンド>` で実行します。以下では `cornix` と書きます。

```bash
cornix help             # コマンドの一覧
cornix help decompile   # コマンドごとの使い方
```

## 使い方

### 典型的な使い方

<details>
<summary><b>Use Case 1: Vial から書き出した layout.vil を YAML にする</b></summary>

```bash
# 1. Vial の "File > Export Layout" で layout.vil を書き出す（例: ~/Downloads/layout.vil）

# 2. decompile（引数を省略すると tmp/layout.vil を読む）
cornix decompile ~/Downloads/layout.vil

# 3. 生成された設定を確認・編集
ls config/
vim config/layers/0_layer.yaml

# 4. compile（自動で検証してから tmp/build/layout.vil を書く）
cornix compile

# 5. Vial の "File > Import Layout" で tmp/build/layout.vil を読み込む
#    または cornix apply でキーボードへ直接反映する
```

- すでに `config/` に設定があると decompile は止まります（上書き防止）

</details>

<details>
<summary><b>Use Case 2: キーボードから読み出し、設定を編集して反映する</b></summary>

```bash
cornix pull              # キーボードの状態を tmp/layout.vil に読み出して config/ にする（初回）
vim config/layers/1_symbol.yaml
cornix status            # compile して、キーボードとの差分を表示（書き込みなし）
cornix apply             # compile して、差分を確認してからキーボードへ書き込む
cornix restore           # 気に入らなければ直前の apply の前の状態に戻す
```

- `status` / `apply` は毎回 compile し、その出力（`tmp/build/layout.vil`）をそのまま使います
- 検証エラーがあると compile は中断し、キーボードには触れません
- 設定は git で管理することをおすすめします

</details>

<details>
<summary><b>Use Case 3: Claude によるファイル名の提案（cornix rename）</b></summary>

```bash
ls config/macros/
# 00_macro.yaml, 01_macro.yaml, ...（decompile が付けた既定の名前）

cornix rename
# Claude が内容を読んで名前を提案 → 1 件ずつ Y/n/e(dit) で選ぶ
# → まとめてリネーム（自動バックアップ・参照の書き換え・compile 結果が変わらないことの確認）

ls config/macros/
# 00_bracket_pair.yaml, 01_end_of_line.yaml, ...
```

- Claude Code CLI（`claude` コマンド）が必要です
- 失敗した場合は自動でバックアップから元に戻します

</details>

### 既存の layout.vil から設定ファイルを生成する

```bash
cornix decompile                       # tmp/layout.vil を読む
cornix decompile ~/Downloads/layout.vil
```

**上書き防止**: `config/layers/` か `config/macros/` にファイルがあると、decompile は何もせずに終了します。

```
⚠️  Error: config/ directory already contains configuration files.
```

その場合は既存の設定を退避するか、`cornix cleanup` で消してから実行します。

```bash
mv config config.backup                 # 退避する
cornix decompile ~/Downloads/layout.vil
```

decompile に成功すると `config/.decompile.lock`（元ファイルとチェックサム）を作ります。

**cleanup コマンド**:

```bash
cornix cleanup      # config/ と tmp/build/layout.vil を消す（ロックファイルがあれば消さずに止まる）
cornix cleanup -f   # ロックファイルがあっても、確認（y/N）してから消す
```

消すのはプロジェクトのルート（`bin/cornix` のあるリポジトリ）の `config/` と `tmp/build/layout.vil` です。どのディレクトリで実行しても同じ場所を対象にします。

#### 生成されるファイル

```
config/
├── .decompile.lock            # decompile の記録（cleanup の保護に使う）
├── metadata.yaml              # キーボードの情報（layout.vil の version / uid など）
├── position_map.yaml          # キーの名前と物理位置の対応
├── settings/
│   └── qmk_settings.yaml      # QMK Settings（tapping_term など）
├── shortcuts.yaml             # 名前付きショートカット（任意。decompile は作らず、自分で作る）
├── layers/
│   ├── 0_layer.yaml           # レイヤー 0
│   └── ...                    # レイヤー 1〜9
├── macros/
│   ├── 00_macro.yaml          # マクロ 0
│   └── ...
├── tap_dance/
│   ├── 00_tap_dance.yaml      # タップダンス 0
│   └── ...
└── combos/
    ├── 00_combo.yaml          # コンボ 0
    └── ...
```

**ファイル名の規則**（decompile が書く名前）:

- レイヤー: `{番号}_{名前}.yaml`（例: `0_layer.yaml`, `1_symbol.yaml`）
- マクロ / タップダンス / コンボ: `{番号 2 桁}_{名前}.yaml`（例: `00_macro.yaml`, `03_end_of_line.yaml`）
- `{名前}` は `name` を小文字・英数字と `_` にしたもの。既定の名前（`Layer 3`, `Macro 2`, `TapDance 4`, `Combo 1`）なら `layer` / `macro` / `tap_dance` / `combo`

拡張子は `.yaml` と `.yml` のどちらでも読みます。ファイル名は自由に変えられます。番号は YAML の `index` で決まり、レイヤーだけはファイル名の先頭の番号と `index` が一致している必要があります。

decompile が書く内容:

- キーコードはエイリアス（`Tab`, `Trans`, `!` など）、エイリアスのない修飾キー付きのキーは修飾キー表現（`Shift + Command + Enter`）
- マクロ・タップダンスの割り当ては名前参照（`Macro('Macro 7')`, `TapDance('TapDance 4')`）
- QMK Settings は名前（`keyboard.tapping_term` など）

**注意**:
- キーコードの表（`data/keycodes.yaml`）とエイリアスの表（`data/aliases.yaml`）はツールが持つファイルで、`config/` には生成しません
- `position_map.yaml` はテンプレート（`lib/cornix/position_map.yaml`）から `config/` に複写され、シンボル名を変えられます

### 設定ファイルに名前を付ける（cornix rename）

`cornix rename` は、Claude がマクロ・タップダンス・コンボ・レイヤーの内容を読んで、意味のある名前とファイル名を提案します。

```bash
cornix rename
```

**流れ**:

1. **設定の確認**: `config/` を検証します。問題があれば先に直すよう表示して終了します
2. **Claude による提案**: 既定の名前（`Macro N`, `TapDance N`, `Combo N`, `Layer N`）のファイルを Claude CLI に渡し、提案を `tmp/rename_plans.json` に受け取ります
   - マクロ: キーの並びから目的を推測（例: `[`, `]`, `Left` → "Bracket Pair"）
   - タップダンス: tap / hold / double tap の動作から推測
   - コンボ: トリガーと出力から推測
   - レイヤー: description や割り当てから推測
3. **提案の確認**: 1 件ずつ `Y`（承認）/ `n`（スキップ）/ `e`（ファイル名・名前・説明を編集）で選びます
4. **リネーム**: `config.backup_<日時>/` にバックアップを取り、ファイル名と `name` / `description` を変え、
   `config/` のすべての YAML にある名前参照 `Macro('旧名')` / `TapDance('旧名')` を新しい名前に書き換えます（テキストの置換なので、コンボの出力やエンコーダ、関数の引数の中にある参照も対象です）
5. **検証**: 変更の前後で設定を compile した結果（16bit 値）を比べ、違えばバックアップから元に戻します
6. **後片付け**: 一時ファイルを消し、バックアップを消すかどうかを尋ねます

**例**:

```
──────────────────────────────────────────────────────────────────────
1. MACRO: 00_macro.yaml

  Current:  00_macro.yaml
  Proposed: 00_bracket_pair.yaml

  Name:        Bracket Pair
  Description: Insert bracket pair [] with cursor positioning

  Reasoning:   Key sequence inserts left bracket, right bracket, then moves cursor left
  Confidence:  high

  Apply this rename? [Y/n/e(dit)]: y
  ✓ Added to rename queue
```

**安全のための仕組み**:
- 番号のプレフィックス（`00_`, `0_` など）は変えられません（変えようとするとエラー）
- まとめて実行し、1 件でも失敗したら全体を元に戻します
- 番号参照（`Macro(3)`, `M3`, `TD(2)`）は名前に依存しないので書き換えません

**Claude を使わずに実行する**（`bin/rename_file`）:

```bash
# 1 ファイル（--dry-run で確認だけ）
ruby bin/rename_file \
  --old-path config/macros/03_macro.yaml \
  --new-basename 03_end_of_line.yaml \
  --name "End of Line" \
  --description "Jump to end of line" \
  --dry-run

# JSON の計画でまとめて（成功したらバックアップを消す）
ruby bin/rename_file --batch tmp/rename_plans.json --cleanup-backup
```

計画ファイルの形式:

```json
[
  {
    "old_path": "config/macros/03_macro.yaml",
    "new_basename": "03_end_of_line.yaml",
    "content_updates": {
      "name": "End of Line",
      "description": "Jump to end of line with Cmd+Right"
    }
  }
]
```

結果は JSON で表示し、失敗したときは終了コード 1 です。Claude CLI が見つからない、または出力から JSON を取り出せないときは、`cornix rename` もこの形式の計画ファイルを手で書くよう案内します。

### 設定ファイルを編集する

レイヤーファイル（例: `config/layers/1_symbol.yaml`）:

```yaml
name: Symbol
description: 記号レイヤー
index: 1
mapping:
  left_hand:
    row0:
      tab: Escape
      Q: "!"                       # LSFT(KC_1)
      W: "@"
    row1:
      caps: Trans                  # 下のレイヤーのキーを使う
      A: Macro('Bracket Pair')     # マクロを名前で参照
    thumb_keys:
      middle: TapDance('Tab Escape')
  right_hand:
    row0:
      Y: Cmd + Space               # 修飾キー表現
  encoders:
    left:
      ccw: VolumeDown
      cw: VolumeUp
```

- `mapping` の下は `position_map.yaml` と同じ階層（`left_hand` / `right_hand` の `row0`〜`row3`・`thumb_keys`、`encoders` の `left` / `right`）です
- 書かなかったキーは割り当てなし（layout.vil では `-1`）になります。下のレイヤーを使うには `Trans` を書きます
- 書かなかったエンコーダの操作は `NoKey` になります

#### 注記（note）

キーを割り当てる場所（レイヤーのキー・エンコーダの操作、タップダンスの動作、コンボの `output_key`）には、
`key` と `note` のマッピングで注記を付けられます。

```yaml
mapping:
  left_hand:
    row0:
      tab:                         # 注記付き
        key: TapDance('Tab Escape')
        note: タップで Tab、長押しで Escape
      Q: "!"                       # 注記なし（キーだけの短い形）
  encoders:
    left:
      push: { key: Mute, note: ミュート }
```

- `note`（注記）は「何のための割り当てか」のメモです。layout.vil やキーボードには書き込まれず、設定ファイルにだけ残ります。
  注記を足したり変えたりしても compile の結果は変わりません
- `note` は省略でき、空の文字列は注記なしと同じです。`key` と `note` 以外のキーは検証エラーです
- `key` は省略できません（エンコーダやタップダンスで操作を省いて `NoKey` にするときは、値ごと書かないでください）
- タップダンスの `actions` とコンボの `output_key` にも同じ形で書けます（各ファイルの形は「[ファイル形式](#ファイル形式)」）
- decompile は注記を書きません（layout.vil に注記はありません）

マクロファイル（例: `config/macros/00_bracket_pair.yaml`）:

```yaml
name: Bracket Pair
description: "[] を入力してカーソルを中に戻す"
index: 0
sequence:
  - action: tap
    keys: ["[", "]", Left]
```

### マクロ・タップダンスの参照方法

キーの割り当て（レイヤーのキー・エンコーダ、タップダンスの動作、コンボのトリガーと出力）では、マクロとタップダンスを 3 つの書き方で参照できます。

| 書き方 | マクロ | タップダンス | 説明 |
|---|---|---|---|
| 名前（推奨） | `Macro('Bracket Pair')` | `TapDance('Tab Escape')` | ファイルの `name` で参照。`cornix rename` で自動的に書き換わる |
| 番号 | `Macro(0)` | `TapDance(2)` | `index` で参照 |
| QMK 形式 | `M0` | `TD(2)` | 従来の書き方 |

- どの書き方でも同じ layout.vil になります。decompile は常に名前の形で書きます
- 名前が見つからない、または番号のマクロ・タップダンスが定義されていないと検証エラーです
- `'` を含む名前は `"..."` で囲みます（`Macro("Rock'n Roll")`）
- `Combo(...)` は layout.vil のキーに割り当てられないので使えません（検証エラー）
- マクロの中（`sequence` の `keys`）では名前参照は使えません

### 名前付きショートカット（`shortcuts.yaml`）

同じショートカットを何か所でも使うときや、キーの組み合わせより意味で書きたいときは、`config/shortcuts.yaml` に名前を付けて定義し、`Shortcut('名前')` で参照します。

```yaml
# config/shortcuts.yaml
shortcuts:
  前のタブへ: Command + Shift + [
  次のタブへ: Command + Shift + ]
  ウインドウを左半分に: Ctrl + Option + Left
  括弧のペア: Macro('Bracket Pair')    # マクロ・タップダンスの名前参照も書ける
```

```yaml
# config/layers/0_base.yaml
mapping:
  left_hand:
    row0:
      Q: Shortcut('前のタブへ')
      W: Shortcut('次のタブへ')
  encoders:
    left: { push: Shortcut('ウインドウを左半分に'), ccw: VolumeDown, cw: VolumeUp }
```

- `Shortcut('名前')` は定義したキーコードそのものになります（layout.vil には直接書いたときと同じ値が入ります）
- レイヤーのキー・エンコーダ、タップダンスの動作、コンボのトリガーと出力で使えます。関数の引数の中でも使えます（`LT1(Shortcut('名前'))`）
- 定義にない名前を参照すると検証エラーです
- `shortcuts.yaml` の値には `Shortcut(...)` は書けません。マクロの中（`sequence` の `keys`）でも使えません
- `shortcuts.yaml` は任意です。decompile は作りません（layout.vil には名前がないため）
- 設定を保存し直すとき（`ConfigRepository#save`）は、値が `shortcuts.yaml` のどれか **1 つ** の定義と一致する位置を `Shortcut('名前')` の形で書き、
  `shortcuts.yaml` の値は同じキーコードなら元の書き方のまま残します

### layout.vil に変換する

```bash
cornix compile              # tmp/build/layout.vil に書く
cornix compile -o my.vil    # 出力先を指定する
```

compile は先に検証を行い、問題があれば .vil を書かずに終了します（終了コード 1）。検証だけを行うときは `cornix validate` を使います。生成した `tmp/build/layout.vil` は Vial で読み込むか、`cornix apply` で直接反映します（次の節）。`cornix device diff` / `device apply` もファイルを省略するとこの出力を使います（まだ compile していなければ、先に compile するよう案内して終了します）。`-o` の相対パスはカレントディレクトリからです。

コマンドの誤りや読めないファイルなどのエラーは、標準エラー出力に `エラー: …` の形で表示し、終了コード 1 で終わります。

## キーボードへの直接反映（Vial Web 不要）

Bluetooth / USB で接続中の Cornix に、Vial プロトコルで直接 `layout.vil` を反映できます（macOS のみ。初回に Xcode Command Line Tools の `swiftc` で小さな HID ブリッジ `tmp/cornix-hid` をビルドします）。

普段は次の 4 つを使います。`status` / `apply` は compile してから、その出力をそのまま使います。

```bash
cornix pull                     # キーボードの状態を tmp/layout.vil に読み出し、config/ にする（= device read + decompile）
cornix status                   # compile して、キーボードとの差分を表示（書き込みなし。= compile + device diff）
cornix apply                    # compile して、差分を表示し、確認後に書き込む（--yes で確認を省略。= compile + device apply）
cornix restore [BACKUP]         # バックアップ（既定は直前の apply の前の状態）に戻す（= device restore）
```

- `pull` は decompile と同じく、`config/` にすでに設定があると上書きせずに止まります（このときはキーボードを読まず、`tmp/layout.vil` も書き換えません）。設定がなければ `tmp/layout.vil` をキーボードの状態で上書きします
- `status` は差分があると終了コード 2 で終わります（差分がなければ 0、エラーは 1）

ファイルを指定して読み書きするときは `cornix device` を使います。

```bash
cornix device info              # 接続中のキーボードの情報（レイヤー数、ロック状態など）
cornix device read -o now.vil   # キーボードの現在の状態を layout.vil 形式で保存
cornix device backup            # tmp/device_backups/ に日時付きで保存
cornix device diff [FILE]       # .vil とキーボードの差分を表示（書き込みなし。FILE の既定は compile の出力）
cornix device apply [FILE]      # 差分を表示し、確認後に書き込む（--yes で確認を省略）
cornix device restore [BACKUP]  # 最後のバックアップ（直前の apply の前の状態）に戻す
```

`apply` は書き込みの前に自動でバックアップを取り、変更のあったキー・エンコーダ・タップダンス・コンボ・マクロ・設定だけを書き込み、読み戻して一致を確認します。

元に戻すときは `cornix restore`（`cornix device restore` と同じ）を実行します。最後に取ったバックアップとの差分を表示し、確認後に書き込みます。古いバックアップに戻したいときは `cornix restore tmp/device_backups/<日時>.vil` のようにファイルを指定します。`restore` も書き込み前に現在の状態をバックアップするので、続けてもう一度 `restore` すると復元前の状態に戻ります。

### キーボードが接続されていないとき

`cornix device` の各コマンドと MCP の各ツールは、最初にキーボードを探して接続します。見つからない場合は何も書き込まずにエラーで終了します（CLI は標準エラー出力に表示して終了コード 1、MCP はエラー応答）。

```
エラー: Cornix が見つかりません。Mac と Bluetooth（または USB）で接続されているか、スリープしていないか、別の機器に接続先が切り替わっていないかを確認してください
```

- **Bluetooth が切れている・キーボードの電源が切れている**: 上のエラーになります。キーを 1 回押してスリープを解除するか、Mac との接続を確認してから再実行してください。
- **キーボードが別の機器（BT1 / BT2 など）に切り替わっている**: Mac からは見えないので同じエラーになります。Mac に接続しているチャンネルに切り替えてください。
- **読み出しや書き込みの途中で接続が切れた**: 1 秒以内に応答がないと「キーボードから応答がありません」というエラーで中断します。書き込み中だった場合は、何件目まで書き込んだかと反映前のバックアップのパスを表示するので、再接続してから `cornix device apply` をやり直すか、`cornix device restore` で反映前に戻してください（どちらも差分だけを書き込みます）。

### MCP サーバー

`cornix mcp` で MCP サーバー（stdio）を起動できます。AI エージェントから「キーボードの今の設定を読んで」「この layout.vil を反映して」といった操作ができます。

#### セットアップ

- **Claude Code**: リポジトリ直下の `.mcp.json` に `cornix-device` として登録済みです。このディレクトリで Claude Code を開き、初回に表示される MCP サーバーの承認で許可してください。
- **その他のクライアント**（Claude Desktop など）: 次のように絶対パスで登録します。`ruby` が見つからない場合（mise / rbenv など）は `command` に Ruby の絶対パスを指定してください。

```json
{
  "mcpServers": {
    "cornix-device": {
      "command": "ruby",
      "args": ["/path/to/cornix-layout/bin/cornix", "mcp"]
    }
  }
}
```

`cornix mcp` は環境変数 `LANG` が未設定でも UTF-8 で入出力し、応答の JSON は非 ASCII 文字を `\uXXXX` にエスケープして返すので、クライアント側のロケールに関係なく読み取れます。

#### ツール

| ツール | 内容 |
|---|---|
| `keyboard_info` | キーボードの情報（読み取りのみ） |
| `read_keymap` | 現在の状態を layout.vil 形式で返す・保存する（読み取りのみ） |
| `backup` / `list_backups` | バックアップの保存と一覧 |
| `apply_layout` | 既定は dry run で差分と `confirm_token` を返す。`dry_run: false` と `confirm_token` を付けたときだけ書き込む |
| `restore_backup` | 最後のバックアップ（`backup_path` で指定も可）に戻す。dry run と `confirm_token` の扱いは `apply_layout` と同じ |

キーボードが接続されていない場合、どのツールもエラー応答を返し、何も書き込みません。

#### 反映の流れ

1. `cornix compile` で `tmp/build/layout.vil` を生成する（`apply_layout` の `vil_path` の既定）
2. `apply_layout`（dry run）で差分と `confirm_token` を受け取り、内容を確認する
3. 同意したら `apply_layout` を `dry_run: false` と `confirm_token` を付けて呼ぶ。自動バックアップ → 差分のみ書き込み → 読み戻し検証が行われる
4. 元に戻すときは `restore_backup` を同じく dry run → `confirm_token` 付きの順で呼ぶ（古いバックアップは `list_backups` で選んで `backup_path` に指定）

確認後に差分が変わっていた場合（キーボード側やファイルが変更された場合）、トークンが一致しないため書き込みは拒否されます。

#### マクロ変更時の承認操作（アンロック）について

Vial（Web / GUI）はマクロの保存時と `QK_BOOT` の割り当て時に、指定の 2 キーを長押しする「アンロック」を求めます。これは Vial アプリ側の動作で、Cornix のファームウェア（RMK 0.8 系）はマクロの書き込みにロック状態を確認していません。そのため `cornix device` / MCP ではアンロック操作は不要です（`QK_BOOT` などの boot 系キーコードはそもそも書き込めないようにしています）。

### 安全性について

Cornix のファームウェアは RMK 0.8 系で、vial-qmk と違ってロックや範囲検査がほとんどありません（bootloader 移行や EEPROM リセットがロックなしで実行され、範囲外の書き込みではファームウェアがパニックします）。そのため次のようにしています。

- HID ブリッジ（`ext/cornix_hid/main.swift`）は許可リストにあるコマンドしか送りません。bootloader 移行・EEPROM リセット・全消去・アンロック・キーマップ一括書き込み（RMK 0.8 にバグあり）は送れません（`tmp/cornix-hid --self-test` で確認できます）。
- キーは Vial GUI と同じ 1 キーずつの書き込みだけを使い、layer / row / col・マクロのオフセット・各エントリ番号はすべて送信前に範囲を検査します。
- `QK_BOOT` などの boot 系キーコード（`data/dangerous_keycodes.yaml`）は書き込みません。

## 設定ファイルの検証

```bash
cornix validate
```

```
# 成功時
✓ All validations passed

# 失敗時（終了コード 1）
✗ Validation failed:
  Error: layers/1_symbol.yaml: mapping.left_hand.row0.tab: キーコード「Spce」を解釈できません: 「Spce」は不明なキーコードです
  Error: layers/1_symbol.yaml: mapping.left_hand.row1.capz: position_map の left_hand.row1 にないキーです（使えるキー: caps, A, S, D, F, G）
  Error: macros/01_macro.yaml: name: マクロの名前が重複しています: Bracket Pair
```

問題は 1 件ずつ止まらずにすべて集め、「ファイル: キーの位置: 内容」で表示します。`cornix compile` も同じ検証を先に行います。警告（`⚠  Warning: …`）だけなら compile は続行します。

検証は 2 段階です。

<details>
<summary><b>1. ファイルの構造（読み込み時）</b></summary>

- **YAML**: 構文エラー、キーの重複、YAML のエイリアス（`&` / `*`）はエラー。`metadata.yaml` などで `.yaml` と `.yml` の同名ファイルが両方あるとエラー
- **項目**: 必須の項目（レイヤーの `name` / `index` / `mapping` など）があるか、知らない項目がないか、型が正しいか。
  引用符のない `1` が整数に、`yes` / `no` / `on` / `off` が真偽値になるといった YAML の落とし穴は、書き直し方つきで表示します
- **metadata.yaml**: `keyboard` と `version` が必須。`uid` などは 0 以上の整数
- **position_map.yaml**: 各グループのキーの数、シンボルの形式、同じグループ内での重複
- **キーの名前**: レイヤーのキーが `position_map.yaml` のそのグループにあるか
- **キーコード**: すべての割り当てが解釈できるか（エイリアス・QMK 名・関数形式・修飾キー表現・参照。関数の引数も含む）
- **番号**: レイヤー 0〜9、マクロ・タップダンス・コンボの番号の範囲。レイヤーのファイル名の番号と `index` の一致
- **マクロ**: `action` は `tap` / `down` / `up` / `delay` / `text`（`beep` は対応していません）
- **QMK Settings**: 設定名と値の型・幅

</details>

<details>
<summary><b>2. 設定全体の整合性</b></summary>

- **件数の上限**: レイヤー 10、マクロ 32、タップダンス 32、コンボ 32、コンボのトリガー 4 キー
- **重複**: レイヤー・マクロ・タップダンス・コンボの番号、マクロ・タップダンス・コンボの名前
- **参照先**: `Macro(...)` / `M3` / `TapDance(...)` / `TD(2)` の参照先が定義されているか
- **レイヤー番号**: `MO(n)` / `LT(n, ...)` などのレイヤー番号がレイヤー数を超えていないか（エラー）、定義されていないレイヤーを指していないか（警告）
- **レイヤーの抜け**: 番号が飛んでいるレイヤー（警告）

</details>

## ファイル形式

### レイヤーファイル

[設定ファイルを編集する](#設定ファイルを編集する) を参照してください。ファイル名は `{番号}_{名前}.yaml` で、先頭の番号は `index` と同じにします。

レイヤー番号を変えるときは、ファイル名と `index` の両方を変え、他のファイルの `MO(2)`, `LT2(...)` などを手で書き換えます。

### マクロファイル

```yaml
name: Curly Bracket Pair
description: "{} を入力してカーソルを中に戻す"
index: 1
sequence:
  - action: down
    keys: LShift
  - action: tap
    keys: ["[", "]"]
  - action: up
    keys: LShift
  - action: tap
    keys: Left
```

### タップダンスファイル

```yaml
name: Tab Escape
description: タップで Tab、長押しで Escape
index: 0
actions:
  on_tap: Tab
  on_hold: Escape
  on_double_tap: NoKey
  on_tap_hold: NoKey
tapping_term: 200        # ミリ秒（省略すると 250）
```

省略した動作は `NoKey` です。

### コンボファイル

```yaml
name: Left Click
description: ← + ↓ で左クリック
index: 6
trigger_keys:
  - Left
  - Down
output_key: MouseButton1
```

`trigger_keys`（最大 4 キー）と `output_key` には、レイヤーと同じくエイリアス（`Left`, `MouseButton1`）も QMK 名（`KC_LEFT`, `KC_BTN1`）も書けます。`output_key` には `Macro('名前')` などの参照も書けます。

マクロ・タップダンス・コンボの `enabled` は読み飛ばします（書いてもエラーにはなりません）。

### QMK Settings

```yaml
# config/settings/qmk_settings.yaml
keyboard:
  oneshot_timeout: 1000
  tapping_term: 180
  tap_code_delay: 20
  tap_hold_caps_delay: 20
  permissive_hold: false
  hold_on_other_key_press: true
  chordal_hold: true
  flow_tap: 120
vial:
  combo_timing_window: 50
```

使える名前と幅は `data/qmk_settings.yaml` にあります。以前の decompile が書いた QSID の番号の形（`'7': 180`）も読めます。

## 修飾キー表現（VS Code 風）

`Cmd + Q` のように書くと、修飾キー付きのキーコードになります。

```yaml
Q: Cmd + Q               # LGUI(KC_Q)
W: Shift + W             # LSFT(KC_W)
E: Ctrl + C              # LCTL(KC_C)
R: Alt + Tab             # LALT(KC_TAB)
T: Shift + Cmd + Q       # SGUI(KC_Q)
Y: Ctrl + Shift + F      # C_S(KC_F)
U: Ctrl + Shift + Alt + Cmd + Y   # HYPR(KC_Y)
```

- 修飾キーの順序と `+` の前後の空白は自由です（`Cmd + Shift + W` = `Shift+Cmd+W`）
- キーにはエイリアスも QMK 名も書けます（`Cmd + Space`, `Alt + KC_ESCAPE`, `Cmd + "+"`）
- 修飾キーの組み合わせは layout.vil に Vial が読める形で書きます。Vial に名前のある組み合わせはその名前（`C_S`, `SGUI`, `LCA`, `LSA`, `MEH`, `LCG`, `LAG`, `LCAG`, `HYPR`, `RCG` など）、名前のない組み合わせ（`Ctrl + Shift + Cmd` など）は 16bit 値（`0x0B17` など）です
- 右側の修飾キーは `RShift` / `RCtrl` / `RAlt` / `RCmd` などで書きます。**左右の修飾キーを混ぜるとエラー**です（例: `Shift + RCmd + A`。QMK の値で表せないため）
- 修飾できるのは基本キーだけです（`Cmd + LT(1, Space)` はエラー）

### 修飾キーの名前

| 書き方 | 左右 | 修飾キー |
|---|---|---|
| `Shift`, `LShift` | 左 | Shift |
| `Ctrl`, `LCtrl`, `Control`, `LControl` | 左 | Ctrl |
| `Alt`, `LAlt`, `Option`, `LOption` | 左 | Alt / Option |
| `Cmd`, `LCmd`, `Command`, `LCommand`, `Win`, `LWin`, `Gui`, `LGui` | 左 | GUI / Command |
| `RShift` | 右 | Shift |
| `RCtrl`, `RControl` | 右 | Ctrl |
| `RAlt`, `ROption` | 右 | Alt / Option |
| `RCmd`, `RCommand`, `RWin`, `RGui` | 右 | GUI / Command |

### 関数形式

QMK の関数形式もそのまま書けます。

```yaml
Q: LGUI(KC_Q)
W: LSFT(1)               # 引数はエイリアスでもよい（LSFT(KC_1)）
E: LCS(KC_F)             # C_S(KC_F) と同じ
R: LCTL_T(A)             # 長押しで Ctrl、タップで A
T: LT(1, Space)          # LT1(Space) とも書ける
```

### decompile の書き方

decompile は修飾キー付きのキーを次の順で書きます。

1. エイリアスがあればエイリアス（`LSFT(KC_1)` → `!`、`LSFT(KC_9)` → `(`）
2. なければ修飾キー表現（`Ctrl, Option, Shift, Command` の順。右側は `RCtrl, ROption, RShift, RCommand`）
   - `LGUI(KC_Q)` → `Command + Q`、`HYPR(KC_LEFT)` → `Ctrl + Option + Shift + Command + Left`

そのため `Cmd + Q` と書いた設定を compile → decompile すると `Command + Q` になります（値は同じです）。

## キーコードエイリアス

キーコードの名前は 2 つの表で決まります。どちらもツールが持つファイルで、`config/` には生成しません。

- **`data/keycodes.yaml`**: Cornix（Vial プロトコル 6）の名前付きキーコードと 16bit 値。layout.vil に書く名前（Vial GUI が保存する名前）と、受け付ける別の QMK 名
- **`data/aliases.yaml`**: 人が読む別名。`QMK 名: [正規名, 別名...]` の形で、先頭が decompile で書く名前です。別名と QMK 名は全体で一意です

```yaml
# data/aliases.yaml（抜粋）
special:
  KC_NO: [NoKey, None, Nop]
  KC_TRNS: [Trans, Transparent, ___]
basic:
  KC_A: [A]
  KC_ESCAPE: [Escape, Esc]
  KC_ENTER: [Enter, Return, Ent]
  KC_LGUI: [LGui, LCmd, LWin]
  KC_VOLU: [VolumeUp, VolUp]
  KC_BTN1: [MouseButton1, MouseBtn1]
quantum:
  QK_BOOT: [Reset, Boot]
modified:
  "LSFT(KC_1)": ["!", Exclaim]
  "LSFT(KC_SCOLON)": [":", Colon]
```

- 設定ファイルにはエイリアス・QMK 名（`KC_TAB`, `KC_LSHIFT`）・Vial 名のどれでも書けます
- `MO(n)` / `LT(n, kc)` / `LSFT(kc)` / `TD(n)` / `M0` など引数付きのキーコードは表に持たず、組み立てて値にします
- 表で表せない値は `0xHHHH` で書けます（decompile も解釈できない値はこの形で書きます）

## Position Map（物理位置マッピング）

`position_map.yaml` は、キーの物理位置とシンボル名の対応です。レイヤーファイルでは `left_hand.row0.Q` のようにシンボルでキーを指定します。

- **テンプレート**: `lib/cornix/position_map.yaml`（ツールが持つ既定値）
- **ユーザー設定**: `config/position_map.yaml`（decompile がテンプレートから作る。シンボル名を自由に変えられる。compile はこちらを読む）

```yaml
left_hand:
  row0: [tab, Q, W, E, R, T]           # 6 キー
  row1: [caps, A, S, D, F, G]          # 6 キー
  row2: [lshift, Z, X, C, V, B]        # 6 キー
  row3: [lctrl, command, option]       # 3 キー
  thumb_keys: [left, middle, right]    # 親指 3 キー
right_hand:
  row0: [Y, U, I, O, P, backspace]
  row1: [H, J, K, L, colon, enter]
  row2: [N, M, comma, dot, up, rshift]
  row3: [left, down, right]
  thumb_keys: [left, middle, right]
encoders:
  left:
    push: push
    ccw: ccw
    cw: cw
  right:
    push: push
    ccw: ccw
    cw: cw
```

- 左手・右手とも、キーは**物理的に左から右**の順に並べます（右手 row0 は `Y`（左端）→ … → `backspace`（右端））
- シンボルは同じ手・同じグループの中で一意であればよく、グループが違えば同じ名前を使えます（右手の `row3` と `thumb_keys` の `left` / `right` など）。シンボルに使える文字は英数字・`_`・`-` です
- 親指キーは物理的には row3 の後半にありますが、`thumb_keys` として独立に書きます
- エンコーダのプッシュはキーマトリクス上のキー、回転（`ccw` / `cw`）は layout.vil の `encoder_layout` に書かれます

```yaml
# シンボル名を変える例（config/position_map.yaml）
right_hand:
  row0: [y, u, i, o, p, bs]
```

## マクロで使えるアクション

```yaml
- action: tap            # 順にタップ
  keys: [A, B, C]
- action: tap
  keys: A                # 1 キーなら文字列でもよい
- action: down           # 押し下げる（複数なら同時に）
  keys: [LCmd, LShift]
- action: up             # 離す
  keys: LShift
- action: text           # 文字列を入力（ASCII のみ）
  content: "function ()"
- action: delay          # 待つ（ミリ秒）
  duration: 100
```

`keys` にはキーコード（エイリアス・QMK 名・修飾キー表現）を書きます。`beep` は対応していません。

## 開発

### 構成

内部は層に分かれていて、設定ファイル・layout.vil・HID のバイト列はすべて外側の表現として扱い、内側では型のある値（ドメインモデル）だけを扱います。

```
Interface       CLI（bin/cornix → Interface::Cli::Main）・MCP サーバー
Application     ユースケース（Compile / Decompile / Validate / Cleanup / RenameFiles / Device*）と Environment
Mapping         キーコードの表記と値の変換（KeycodeNotation / VialNotation / KeycodeCodec）、Profile ⇄ DeviceImage（ProfileMapper）
Planning        DeviceImage どうしの差分と書き込み計画
Domain          Profile と値オブジェクト（Keycode, Layer, Macro, TapDance, Combo, PositionMap ...）
Image           DeviceImage（layout.vil / 実機の状態を 16bit 値のまま持つ）
Storage         config/*.yaml（ConfigRepository）・layout.vil（VilFile）・バックアップ
Device          HID ブリッジとの通信、実機の読み出し・書き込み
```

```
compile    config/ → Profile → DeviceImage → layout.vil
decompile  layout.vil → DeviceImage → Profile → config/
device     layout.vil → DeviceImage（目標）と 実機 → DeviceImage（現在）の差分を書き込み、読み直して検証
```

方針・依存の向き・コード規約は [docs/architecture.md](docs/architecture.md)、主なクラスの公開メソッドは [docs/tasks.md](docs/tasks.md) にあります。

### ディレクトリ構造

```
cornix-layout/
├── bin/
│   ├── cornix                # CLI（Interface::Cli::Main）
│   ├── diff_layouts          # 2 つの layout.vil を 16bit 値で比べる
│   └── rename_file           # リネームを直接実行する（JSON で結果を表示）
├── data/
│   ├── keycodes.yaml         # 名前付きキーコードの表（Vial プロトコル 6）
│   ├── aliases.yaml          # キーコードの別名（QMK 名: [正規名, 別名...]）
│   ├── qmk_settings.yaml     # QMK Settings の QSID・名前・幅
│   └── dangerous_keycodes.yaml # 実機に書き込まないキーコード
├── lib/
│   ├── cornix.rb             # すべてのファイルを層の順に読み込む
│   └── cornix/
│       ├── domain/ image/ mapping/ planning/ storage/ device/ application/ interface/
│       ├── errors.rb         # Cornix::Error 系の例外
│       └── position_map.yaml # position_map のテンプレート
├── ext/cornix_hid/main.swift # raw HID ブリッジ（許可リスト付き、tmp/cornix-hid にビルド）
├── spec/                     # RSpec（lib と同じ層の構成。spec/README.md）
├── docs/                     # architecture.md・tasks.md
├── .mcp.json                 # Claude Code 用の MCP サーバー登録
├── config/                   # 設定ファイル（生成物）
└── tmp/                      # 生成物（git 管理外）
    ├── build/layout.vil      # compile の出力（status / apply が使う）
    ├── layout.vil            # decompile の既定の入力（pull がキーボードの状態を書く）
    └── device_backups/       # apply / restore の前のバックアップ
```

### テスト

```bash
LANG=ja_JP.UTF-8 bundle exec rspec                       # すべて
LANG=ja_JP.UTF-8 bundle exec rspec spec/mapping          # 層ごと
LANG=ja_JP.UTF-8 bundle exec rspec spec/end_to_end_spec.rb
```

- spec は lib と同じ層の構成（`spec/domain`, `spec/mapping`, ... `spec/interface`）です
- `spec/end_to_end_spec.rb` は `spec/fixtures/test_config` と作者のキーマップ（`spec/fixtures/authors_config`）を compile し、保存してある layout.vil と 16bit 値で一致すること、decompile → compile で元に戻ることを確かめます
- `spec/architecture_spec.rb` は層の依存の向きを検査します
- 実機の代わりに RMK 0.8 の応答を模した `FakeRmkDevice` を使うので、キーボードなしで実行できます

詳細は [spec/README.md](spec/README.md) を参照してください。GitHub Actions でも push / pull request ごとに RSpec を実行します。

### Round-trip チェック

手元の layout.vil で decompile → compile が元に戻るかを確かめる手順です。

```bash
mv config config.backup          # 既存の設定を退避
cp ~/Downloads/layout.vil tmp/layout.vil
cornix decompile                 # tmp/layout.vil → config/
cornix compile                   # config/ → tmp/build/layout.vil
ruby bin/diff_layouts            # tmp/layout.vil と tmp/build/layout.vil を比べる
# 期待結果: === ✓ FILES ARE IDENTICAL ===
```

`bin/diff_layouts [FILE1 FILE2]` は 2 つの layout.vil を読み込み、キー・エンコーダ・マクロ・タップダンス・コンボ・設定を 16bit 値で比べます。同じ値の別表記（`KC_PGDN` と `KC_PGDOWN` など）は同じとみなします。違えば場所を表示して終了コード 1 です。

## トラブルシューティング

<details>
<summary><b>よくある問題</b></summary>

### 1. decompile がブロックされる

```
⚠️  Error: config/ directory already contains configuration files.
```

`config/` に設定があるためです。`mv config config.backup` で退避するか `cornix cleanup` で消してから、もう一度 decompile します。cleanup が `Protected: config/ directory has an active lock file` で止まる場合は `cornix cleanup -f` を使います。

### 2. キーコードを解釈できない

```
Error: layers/0_base.yaml: mapping.left_hand.row0.Q: キーコード「Spce」を解釈できません: 「Spce」は不明なキーコードです
```

タイプミスです（`Spce` → `Space`）。使える名前は `data/aliases.yaml` と `data/keycodes.yaml` にあります。

### 3. position_map にないキー

```
Error: layers/0_base.yaml: mapping.left_hand.row1.capz: position_map の left_hand.row1 にないキーです（使えるキー: caps, A, S, D, F, G）
```

`config/position_map.yaml` のそのグループにあるシンボルを使うか、`position_map.yaml` を変えます。

### 4. 番号や名前の重複

```
Error: layers/2_layer.yaml: index: レイヤーの番号が重複しています: 2
Error: macros/01_macro.yaml: name: マクロの名前が重複しています: Bracket Pair
```

どちらかのファイルの `index` / `name` を変えます。

### 5. 存在しないマクロ・タップダンスの参照

```
Error: layers/0_base.yaml: mapping.left_hand.row0.Q: キーコード「Macro('Unknown')」を解釈できません: マクロ「Unknown」が見つかりません
```

`config/macros/*.yaml` の `name` を確認し、参照を直します（`grep '^name:' config/macros/*.yaml`）。

### 6. 左右の修飾キーの混在

```
キーコード「Shift + RCmd + A」を解釈できません: 左右の修飾キーは混在できません（例: Shift と RCmd）
```

QMK の修飾キー付きキーコードは左右どちらか一方しか表せません。どちらかにそろえます。

### 7. Round-trip チェックが失敗する

`ruby bin/diff_layouts` の出力で、どのレイヤー・行・項目が違うかを確認します。元の layout.vil と生成した layout.vil を添えて issue を作成してください。

### 8. Claude Code CLI（`claude` コマンド）が見つからない

```
  ❌ Error: Claude CLI not found
```

`cornix rename` には Claude Code CLI が必要です。https://claude.ai/download からインストールし、`claude --version` で確認します。

### 9. YAML の構文エラー・型の誤り

エラーメッセージのファイルを確認します。よくある原因はインデントの誤り、タブの混在、引用符が必要な文字列（`"!"`, `"["`, `"1"` など）です。引用符のない `1` が整数として読まれた場合などは、書き直し方をメッセージに表示します。

</details>

## Tips

- **名前参照を使う**: `Macro('End of Line')` は `M5` より読みやすく、`cornix rename` で自動的に書き換わります
- **修飾キー表現を使う**: `Cmd + Q`、`Ctrl + Shift + F` は `LGUI(KC_Q)`、`C_S(KC_F)` より読みやすく、decompile も修飾キー表現で書きます
- **git で管理する**: `config/` を git で管理すると、変更の確認や取り消しが簡単です
- **番号のプレフィックスを保つ**: ファイル名を変えるときは `03_` などのプレフィックスを残します（レイヤーはファイル名の番号と `index` が一致している必要があります）
- **小さく変えて確かめる**: 変更のたびに `cornix compile`（自動検証つき）を実行すると、問題の場所がすぐ分かります

## コントリビューション

プルリクエスト歓迎です！

1. このリポジトリをフォーク
2. フィーチャーブランチを作成 (`git checkout -b feature/amazing-feature`)
3. `LANG=ja_JP.UTF-8 bundle exec rspec` がすべて通ることを確認
4. コミットしてプッシュ
5. プルリクエストを作成

## ライセンス

MIT License

## 参考リンク

- [Vial Documentation](https://get.vial.today/)
- [QMK Firmware Documentation](https://docs.qmk.fm/)
- [QMK Keycodes](https://docs.qmk.fm/keycodes_basic)

---

## Appendix

### 主なキーコード

完全な一覧は `data/aliases.yaml`（別名）と `data/keycodes.yaml`（QMK / Vial 名）を参照してください。

<details>
<summary><b>主なキーコードのカテゴリ</b></summary>

**基本キー**:
- 文字 `A`〜`Z`、数字 `"0"`〜`"9"`、ファンクションキー `F1`〜`F24`
- 移動: `Up`, `Down`, `Left`, `Right`, `Home`, `End`, `PageUp`, `PageDown`
- 編集: `Enter`, `Escape`, `Backspace`, `Tab`, `Space`, `Delete`
- 修飾キー: `LShift`, `RShift`, `LCtrl`, `RCtrl`, `LAlt`, `RAlt`, `LGui`（`LCmd`）, `RGui`（`RCmd`）
- 記号: `"-"`, `"="`, `"["`, `"]"`, `"\\"`, `";"`, `"'"`, `` "`" ``, `","`, `"."`, `"/"`
- Shift 付きの記号: `"!"`, `"@"`, `"#"`, `"("`, `")"`, `":"` など

**レイヤー操作**:
- `MO(n)`（押している間）、`TG(n)`（トグル）、`TO(n)`（切り替え）、`TT(n)`（タップでトグル）、`DF(n)`（デフォルト）、`OSL(n)`（1 回だけ）
- `LT(n, key)` / `LTn(key)`: 長押しでレイヤー、タップでキー
- 引数は数値です（`MO(KC_3)` はエラー）

**修飾キー**:
- Mod-Tap: `LCTL_T(key)`, `LSFT_T(key)`, `LALT_T(key)`, `LGUI_T(key)`, `MEH_T(key)` など、`MT(MOD_LCTL|MOD_LSFT, key)`
- One Shot: `OSM(MOD_LSFT)`
- 修飾キー付き: `LSFT(key)`, `C(key)`, `S(key)`, `A(key)`, `G(key)` と組み合わせ（`C_S`, `SGUI`, `MEH`, `HYPR` など）
- `LM(n, MOD_LCTL)`

**メディア・マウス**:
- `VolumeUp`, `VolumeDown`, `Mute`, `MediaPlayPause` など
- `MouseUp`, `MouseDown`, `MouseLeft`, `MouseRight`, `MouseButton1`〜, `MouseWheelUp` など

**特殊キー**:
- `Trans`（`Transparent`, `___`）: 下のレイヤーを使う
- `NoKey`: 無効
- `Reset`（`QK_BOOT`）: 設定ファイルには書けますが、`cornix device` では書き込みません

</details>

### 修飾キーの関数と修飾キー表現

| 関数 | 修飾キー表現 | layout.vil の表記 |
|---|---|---|
| `LCTL` / `C` | `Ctrl + key` | `LCTL(...)` |
| `LSFT` / `S` | `Shift + key` | `LSFT(...)` |
| `LALT` / `A` | `Alt + key` | `LALT(...)` |
| `LGUI` / `G` | `Cmd + key` | `LGUI(...)` |
| `LCS` / `C_S` | `Ctrl + Shift + key` | `C_S(...)` |
| `LCA` | `Ctrl + Alt + key` | `LCA(...)` |
| `LCG` | `Ctrl + Cmd + key` | `LCG(...)` |
| `LSA` | `Shift + Alt + key` | `LSA(...)` |
| `LSG` / `SGUI` | `Shift + Cmd + key` | `SGUI(...)` |
| `LAG` | `Alt + Cmd + key` | `LAG(...)` |
| `MEH` | `Ctrl + Shift + Alt + key` | `MEH(...)` |
| `LCSG` | `Ctrl + Shift + Cmd + key` | 16bit 値（`0x0Bxx`） |
| `LCAG` | `Ctrl + Alt + Cmd + key` | `LCAG(...)` |
| `LSAG` | `Shift + Alt + Cmd + key` | 16bit 値（`0x0Exx`） |
| `HYPR` | `Ctrl + Shift + Alt + Cmd + key` | `HYPR(...)` |

右側（`RCTL`, `RSFT`, `RALT`, `RGUI`, `RCS`, `RCA`, `RCG`, `RSA`, `RSG`, `RAG`, `RCSG`, `RCAG`, `RSAG`）も同じように書けます。Vial に名前のない組み合わせは layout.vil に 16bit 値で書かれます。

### サンプル設定

ブランチを切り替えると、サンプルの設定を使えます。

<details>
<summary><b>利用できるサンプル設定</b></summary>

#### 1. 公式の初期キーマップ（推奨）

```bash
git checkout cornix-default-keymap
ls config/
cornix compile
```

Cornix の標準的なレイアウトです。初めての方におすすめです。

#### 2. 作者のキーマップ

```bash
git checkout authors-keymap
ls config/
cornix compile
```

実際に使っているキーマップで、名前参照・修飾キー表現・コンボなどの使用例があります。

#### 3. 自分の layout.vil から作る

```bash
git checkout main
cornix decompile ~/Downloads/my_layout.vil
vim config/layers/0_layer.yaml
cornix compile
```

#### ブランチの切り替え方

```bash
mv config config.my_backup             # 今の設定を退避
git checkout cornix-default-keymap
# ...
git checkout main
mv config.my_backup config             # 元に戻す
```

</details>

サンプル設定の提供も歓迎します（新しいブランチで共有し、プルリクエストを作成してください）。

---

Made with ❤️ for the Cornix keyboard community
