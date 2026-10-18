# Cornix Keyboard Layout Manager

[English](README.md) | 日本語

Cornix キーボードのキーマップ（レイヤー・エンコーダ・マクロ・タップダンス・コンボ・QMK Settings）を
人が読み書きできる YAML ファイルで管理し、Vial の `layout.vil` との相互変換と、接続中のキーボードへの直接反映を行うツールです。

- キーボードから設定を読み出して YAML にする（`pull`）
- YAML を編集して、キーボードとの差分を確認する（`status`）
- 差分だけをキーボードに書き込む（`apply`）。書く前に必ずバックアップを取り、書いたあとに読み直して確かめる
- 気に入らなければ、バックアップから戻す（`restore`）
- Vial を使うなら、YAML から `layout.vil` を作り（`compile`）、Vial で書き出した `layout.vil` を YAML にする（`decompile`）

設定ファイルは Git で管理できるので、変更の履歴を残したり、用途ごとに設定を切り替えたりできます。
MCP サーバーとしても動くので、Claude などの AI アシスタントからキーボードの設定を読んだり変えたりすることもできます。

YAML では次のような書き方ができます。

- **エイリアス**: `KC_TAB` → `Tab`、`KC_TRNS` → `Trans`、`LSFT(KC_1)` → `!`
- **修飾キー表現**: `Cmd + Q`、`Ctrl + Shift + F` のような VS Code 風の書き方
- **名前で参照**: `Macro('Bracket Pair')`、`TapDance('Tab Escape')`
- **名前付きショートカット**: `shortcuts.yaml` に `前のタブへ: Command + Shift + [` と定義し、`Shortcut('前のタブへ')` で何か所でも使う
- **注記**: `{ key: Mute, note: ミュート }` のように、割り当ての目的を設定ファイルに残す
- **コメント**: `#` で自由に書ける

decompile → compile で 16bit 値が元と一致するので、Vial で作った設定をそのまま移せます。

> **非公式のツールです。** Cornix の開発元とは関係ありません。
> キーボードへの直接反映は、実機での検証と Vial / RMK の公開されているソースをもとにしています。使用は自己責任でお願いします。

## 目次

- [対応しているもの](#対応しているもの)
- [必要なもの](#必要なもの)
- [はじめ方](#はじめ方)
- [コマンドの一覧](#コマンドの一覧)
- [設定ファイルの書き方](#設定ファイルの書き方)
- [キーの書き方](#キーの書き方)
- [YAML の注意](#yaml-の注意)
- [設定ファイルの検証](#設定ファイルの検証)
- [設定ファイルに名前を付ける（rename）](#設定ファイルに名前を付けるrename)
- [Vial の layout.vil と変換する](#vial-の-layoutvil-と変換する)
- [バックアップと元に戻す](#バックアップと元に戻す)
- [設定の置き場所と利用の形](#設定の置き場所と利用の形)
- [MCP サーバーとして使う](#mcp-サーバーとして使う)
- [安全のための仕組み](#安全のための仕組み)
- [トラブルシューティング](#トラブルシューティング)
- [開発者向け](#開発者向け)

## 対応しているもの

| 項目 | 対応 |
|---|---|
| キーボード | Cornix |
| ファームウェア | RMK 0.8 系（Vial プロトコル 6） |
| OS | キーボードとの通信（`pull` / `status` / `apply` / `restore` / `device` / `mcp`）は macOS のみ。`compile` / `decompile` / `validate` などは Ruby が動けばどこでも |
| 接続 | Bluetooth または USB |

## 必要なもの

- **Ruby 3.2 以上**（`Data.define` を使うため。CI は 4.0 系）と **Bundler**
- **Xcode Command Line Tools**（キーボードとの通信に使います。`swiftc` がなければ `xcode-select --install`）
  - キーボードとの通信には、小さな Swift のプログラム（`ext/cornix_hid/main.swift`）を使います。初めて使うときに自動でビルドされ、`tmp/cornix-hid` に置かれます
- **Claude Code CLI**（`claude` コマンド。`cornix rename` を使うときだけ）

## はじめ方

### 1. 取得する

```bash
git clone https://github.com/guccyon/cornix-layout.git   # 自分のフォークを clone してもよい
cd cornix-layout
bundle install
```

設定を GitHub に置いて複数のマシンで使うなら、フォークするのがおすすめです
（[設定の置き場所と利用の形](#設定の置き場所と利用の形)）。

`cornix` コマンドとして使いたいときは、`bin/cornix` への symlink を PATH の通ったディレクトリに置きます（`ruby bin/cornix <コマンド>` でも実行できます）。

```bash
mkdir -p ~/.local/bin && ln -s "$PWD/bin/cornix" ~/.local/bin/cornix   # ~/.local/bin が PATH にない場合は PATH に足す
cornix help             # コマンドの一覧
cornix help init        # コマンドごとの使い方
```

以下では `cornix` と書きます。

### 2. 設定を作る（`init`）

Cornix を Mac と Bluetooth（または USB）でつないでから実行します。

```bash
cornix init                                # キーボードの今の設定を profiles/default/ に書き出す
cornix init --from ~/Downloads/layout.vil  # キーボードの代わりに、Vial で書き出した layout.vil から作る
cornix init --no-pull                      # 空の設定ディレクトリだけを作る
```

次のものが作られます。

- `profiles/default/` … 設定ファイル一式。キーボードにつながっていれば、今の設定が YAML で書き出されます
- `.cornix.yml` … 使う設定の指定（`profile: default`）。以降のコマンドはこれを見て `profiles/default/` を使います

ほかに次の点に気をつけてください。

- 設定ディレクトリにすでにファイルがあると、上書きせずに止まります
- キーボードにつながらなかったときは空の設定ディレクトリだけを作るので、つないでから `cornix pull` を実行してください
- `cornix init --profile work` のように名前を付けると `profiles/work/` に作ります。複数の設定を使い分けるときや、
  設定を別のリポジトリに置くときは [設定の置き場所と利用の形](#設定の置き場所と利用の形) を見てください
- 以前のようにこのリポジトリの `config/` に置いた設定も、`.cornix.yml` がなければそのまま使えます
  （[以前の `config/` を使っている場合](#以前の-config-を使っている場合)）

初めに作られるレイヤーやマクロの名前は `Layer 0`・`Macro 0` のようになっています。わかりやすい名前を付けるには `cornix rename`
（[設定ファイルに名前を付ける（rename）](#設定ファイルに名前を付けるrename)）が便利です。

### 3. 設定を編集する

`profiles/default/` の YAML をエディタで編集します。書き方は [設定ファイルの書き方](#設定ファイルの書き方) を見てください。
少しずつ変えて、そのたびに `validate` や `status` で確かめると、問題の場所がすぐわかります。

書き方に誤りがないかは、キーボードなしで確かめられます。

```bash
cornix validate
```

### 4. 差分を見る（`status`）

```bash
cornix status
```

設定を compile し（出力は `tmp/profiles/default/build/layout.vil`）、キーボードの今の状態と比べて、書き込まれる変更を表示します（書き込みはしません）。
差分がなければ終了コード 0、差分があれば 2 で終わります。

### 5. 書き込む（`apply`）

```bash
cornix apply           # 差分を表示し、[y/N] で確認してから書き込む
cornix apply --yes     # 確認を省略する
```

書き込みの前に、その時点のキーボードの状態を `tmp/profiles/default/device_backups/` にバックアップします。
変更のあったキー・エンコーダ・タップダンス・コンボ・マクロ・設定だけを書き込み、最後に読み直して一致を確かめます。
検証エラーがあると compile の段階で止まり、キーボードには触れません。

### 6. 元に戻したいとき（`restore`）

```bash
cornix restore         # 直前の apply の前の状態に戻す（差分を表示し、確認してから書き込む）
```

詳しくは [バックアップと元に戻す](#バックアップと元に戻す)。

## コマンドの一覧

```
cornix <コマンド> [オプション]
```

| コマンド | キーボード | 書き込み | 内容 |
|---|---|---|---|
| `init [DIR] [--from FILE] [--no-pull]` | 使う（`--from` / `--no-pull` なら使わない） | しない | 設定ディレクトリ（既定は `profiles/default/`）と `.cornix.yml` を作り、キーボード（か `--from` の .vil）から設定を書く。既存の設定は上書きしない |
| `pull` | 使う | しない | キーボードの状態を `<tmp>/layout.vil` に読み出し、設定ディレクトリの YAML にする。設定がすでにあれば止まる |
| `status` | 使う | しない | compile して、キーボードとの差分を表示する。差分があれば終了コード 2 |
| `apply [--yes]` | 使う | する（確認のあと） | compile して、差分を確認してからキーボードへ書き込む |
| `restore [BACKUP] [--yes]` | 使う | する（確認のあと） | バックアップ（既定は直前の apply の前の状態）に戻す |
| `compile [-o FILE]` | 使わない | しない | 設定を検証して .vil を書く（既定は `<tmp>/build/layout.vil`） |
| `decompile [FILE]` | 使わない | しない | layout.vil を設定ディレクトリの YAML にする（既定は `<tmp>/layout.vil`）。設定がすでにあれば止まる |
| `validate` | 使わない | しない | 設定ファイルを検証する |
| `rename` | 使わない | しない | Claude の提案を確認しながら、設定ファイルに意味のある名前を付ける |
| `cleanup [-f]` | 使わない | しない | 設定ディレクトリと compile の出力を消す |
| `device <サブコマンド>` | 使う | `apply` / `restore` だけ | ファイルを指定してキーボードを読み書きする（下の表） |
| `mcp` | 使う | ツールによる | MCP サーバーとして起動する（[MCP サーバーとして使う](#mcp-サーバーとして使う)） |

`cornix device` のサブコマンド:

| サブコマンド | 内容 |
|---|---|
| `device info` | 接続中のキーボードの情報（レイヤー数、ロック状態など） |
| `device read [-o FILE]` | キーボードの今の状態を layout.vil 形式で出力する |
| `device backup` | キーボードの状態を `<tmp>/device_backups/` に日時付きで保存する |
| `device diff [FILE]` | .vil とキーボードの差分を表示する（書き込みなし。`FILE` の既定は compile の出力） |
| `device apply [FILE] [--yes]` | 差分を表示し、確認後に書き込む（`FILE` の既定は compile の出力） |
| `device restore [BACKUP] [--yes]` | 最後のバックアップ（直前の apply の前の状態）に戻す |

`pull` は `device read` と `decompile` を、`status` は `compile` と `device diff` を、`apply` は `compile` と `device apply` を続けて行うものです。
`restore` は `device restore` と同じです。

共通のオプション（どのコマンドにも、コマンド名の前にも後にも付けられます）:

| オプション | 内容 |
|---|---|
| `--config DIR` | 設定ディレクトリを直接指定する |
| `--profile NAME` | `profiles/NAME/` の設定を使う |
| `--root DIR` | `tmp/` と `profiles/` を置く場所（既定は `.cornix.yml` のあるディレクトリ、なければこのリポジトリ） |

ふだんは `cornix init` が作った `.cornix.yml` で決まるので、付ける必要はありません（[設定の置き場所と利用の形](#設定の置き場所と利用の形)）。

この README の `<tmp>` は、使っている設定の作業用ディレクトリです。`profiles/NAME/` の設定なら `tmp/profiles/NAME/`、
以前の `config/` の設定なら `tmp/` です（`tmp/` は Git の管理外です）。

終了コード: `0` = 成功、`1` = エラー、`2` = 差分がある（`status` のみ）。
コマンドの誤りや読めないファイルなどのエラーは、標準エラー出力に `エラー: …` の形で表示します。

### `pull` が止まるとき

設定ディレクトリにすでに設定（`layers/` か `macros/` のファイル）があると、`pull` と `decompile` は編集した内容を上書きしないよう、何もせずに止まります。
このとき `pull` はキーボードを読まず、`<tmp>/layout.vil` も書き換えません。

```
⚠️  Error: config/ directory already contains configuration files.
```

（設定ディレクトリが `profiles/` の下にあっても、この表示は `config/` のままです。）

キーボードの状態で設定を作り直したいときは、今の設定を退避するか、`cornix cleanup -f` で消してから実行します（init や decompile で作った設定には `.decompile.lock` があるので、`-f` なしの cleanup は止まります）。

```bash
mv profiles/default profiles/default.backup     # 退避する
cornix pull
```

## 設定ファイルの書き方

### ファイル構成

設定ディレクトリ（ここでは `cornix init` が作る `profiles/default/`）の中は次のようになります。

```
profiles/default/
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

ファイル名の規則（decompile が書く名前）:

- レイヤー: `{番号}_{名前}.yaml`（例: `0_layer.yaml`, `1_symbol.yaml`）
- マクロ / タップダンス / コンボ: `{番号 2 桁}_{名前}.yaml`（例: `00_macro.yaml`, `03_end_of_line.yaml`）
- `{名前}` は `name` を小文字・英数字と `_` にしたもの。既定の名前（`Layer 3`, `Macro 2`, `TapDance 4`, `Combo 1`）なら `layer` / `macro` / `tap_dance` / `combo`

拡張子は `.yaml` と `.yml` のどちらでも読みます。ファイル名は自由に変えられます。番号は YAML の `index` で決まり、レイヤーだけはファイル名の先頭の番号と `index` が一致している必要があります。
レイヤー番号を変えるときは、ファイル名と `index` の両方を変え、他のファイルの `MO(2)`, `LT2(...)` などを手で書き換えます。

decompile が書く内容:

- キーコードはエイリアス（`Tab`, `Trans`, `!` など）、エイリアスのない修飾キー付きのキーは修飾キー表現（`Shift + Command + Enter`）
- マクロ・タップダンスの割り当ては名前参照（`Macro('Macro 7')`, `TapDance('TapDance 4')`）
- QMK Settings は名前（`keyboard.tapping_term` など）
- キーコードの表（`data/keycodes.yaml`）とエイリアスの表（`data/aliases.yaml`）はツールが持つファイルで、設定ディレクトリには作りません

### レイヤー

```yaml
# profiles/default/layers/1_symbol.yaml
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
    row2:                          # 割り当てのないグループも書く（中身は空でよい）
    row3:
    thumb_keys:
      middle: TapDance('Tab Escape')
  right_hand:
    row0:
      Y: Cmd + Space               # 修飾キー表現
    row1:
    row2:
    row3:
    thumb_keys:
  encoders:
    left:
      ccw: VolumeDown
      cw: VolumeUp
```

- `mapping` の下は `position_map.yaml` と同じ階層（`left_hand` / `right_hand` の `row0`〜`row3`・`thumb_keys`、`encoders` の `left` / `right`）です
- 各手の `row0`〜`row3`・`thumb_keys` はすべて書きます（中身は空でかまいません）
- グループの中で書かなかったキーは割り当てなし（layout.vil では `-1`）になります。下のレイヤーを使うには `Trans` を書きます
- 書かなかったエンコーダの操作は `NoKey` になります

### 注記（`note`）

キーを割り当てる場所（レイヤーのキー・エンコーダの操作、タップダンスの動作、コンボの `output_key`）には、
`key` と `note` のマッピングで注記を付けられます。

```yaml
# レイヤーファイルの抜粋
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
- タップダンスの `actions` とコンボの `output_key` にも同じ形で書けます
- decompile は注記を書きません（layout.vil に注記はありません）

### マクロ

```yaml
# profiles/default/macros/01_curly_bracket_pair.yaml
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

使えるアクション:

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

### タップダンス

```yaml
# profiles/default/tap_dance/00_tab_escape.yaml
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

### コンボ

```yaml
# profiles/default/combos/06_left_click.yaml
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
# profiles/default/settings/qmk_settings.yaml
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

使える名前と幅は [data/qmk_settings.yaml](data/qmk_settings.yaml) にあります。以前の decompile が書いた QSID の番号の形（`'7': 180`）も読めます。

### マクロ・タップダンスの参照

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

同じショートカットを何か所でも使うときや、キーの組み合わせより意味で書きたいときは、`profiles/default/shortcuts.yaml` に名前を付けて定義し、`Shortcut('名前')` で参照します。

```yaml
# profiles/default/shortcuts.yaml
shortcuts:
  前のタブへ: Command + Shift + [
  次のタブへ: Command + Shift + ]
  ウインドウを左半分に: Ctrl + Option + Left
  括弧のペア: Macro('Bracket Pair')    # マクロ・タップダンスの名前参照も書ける
```

```yaml
# profiles/default/layers/0_base.yaml（抜粋）
mapping:
  left_hand:
    row0:
      Q: Shortcut('前のタブへ')
      W: Shortcut('次のタブへ')
  encoders:
    left: { push: Shortcut('ウインドウを左半分に'), ccw: VolumeDown, cw: VolumeUp }
```

- `Shortcut('名前')` は定義したキーコードそのものになります（layout.vil には直接書いたときと同じ値が入ります）
- レイヤーのキー・エンコーダ、タップダンスの動作、コンボのトリガーと出力で使えます。関数の引数の中でも使えます（`LT1(Shortcut('名前'))`。ただしその場所に書けるキーを定義したときだけで、`LT1(...)` なら基本キー）
- 定義にない名前を参照すると検証エラーです
- `shortcuts.yaml` の値には `Shortcut(...)` は書けません。マクロの中（`sequence` の `keys`）でも使えません
- `shortcuts.yaml` は任意です。decompile は作らず、読みも変えもしません（layout.vil には名前がないため）
- `cornix rename` でマクロ・タップダンスの名前を変えると、`shortcuts.yaml` の中の `Macro('名前')` / `TapDance('名前')` も書き換わります

### キーの位置（`position_map.yaml`）

`position_map.yaml` は、キーの物理位置とシンボル名の対応です。レイヤーファイルでは `left_hand.row0.Q` のようにシンボルでキーを指定します。

- **テンプレート**: `lib/cornix/position_map.yaml`（ツールが持つ既定値）
- **利用者の設定**: `profiles/default/position_map.yaml`（decompile がテンプレートから作る。シンボル名を自由に変えられる。compile はこちらを読む）

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
# シンボル名を変える例（profiles/default/position_map.yaml）
right_hand:
  row0: [y, u, i, o, p, bs]
```

## キーの書き方

キーには、エイリアス・QMK 名・Vial 名・修飾キー表現・関数形式・参照のどれでも書けます。大文字・小文字は区別します。

| 種類 | 書き方の例 | 説明 |
|---|---|---|
| エイリアス | `A` `Tab` `Enter` `Escape` `Space` `Left` `F5` | 使える名前は [data/aliases.yaml](data/aliases.yaml) にあります |
| QMK 名・Vial 名 | `KC_TAB` `KC_LSHIFT` `KC_BTN1` | [data/keycodes.yaml](data/keycodes.yaml) |
| Shift 付きの記号 | `"!"` `"@"` `"("` `":"` | 記号 1 文字で書くときは引用符で囲みます |
| 何もしない / 下のレイヤーへ | `NoKey` / `Trans` | `Trans` は「透過」（下のレイヤーの割り当てを使う） |
| 修飾キー表現 | `Cmd + Q` `Ctrl + Shift + F` | [修飾キー表現](#修飾キー表現vs-code-風) |
| 関数形式 | `LGUI(KC_Q)` `LT(1, Space)` `LCTL_T(A)` | [関数形式](#関数形式) |
| レイヤー操作 | `MO(1)` `TG(2)` `TO(0)` `LT1(Space)` | 番号はレイヤーの `index` |
| マクロ・タップダンスの参照 | `Macro('Bracket Pair')` `TapDance(2)` `M0` `TD(2)` | [マクロ・タップダンスの参照](#マクロタップダンスの参照) |
| 名前付きショートカット | `Shortcut('前のタブへ')` | [名前付きショートカット](#名前付きショートカットshortcutsyaml) |
| 生の値 | `0x7E00` | 表で表せない値（decompile も解釈できない値はこの形で書きます） |

### エイリアス

キーコードの名前は 2 つの表で決まります。どちらもツールが持つファイルで、設定ディレクトリには作りません。

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

- `MO(n)` / `LT(n, kc)` / `LSFT(kc)` / `TD(n)` / `M0` など引数付きのキーコードは表に持たず、組み立てて値にします
- 表で表せない値は `0xHHHH` で書けます

### 修飾キー表現（VS Code 風）

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

修飾キーの名前:

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

修飾キーの関数と修飾キー表現の対応:

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

### 主なキーコード

完全な一覧は [data/aliases.yaml](data/aliases.yaml)（別名）と [data/keycodes.yaml](data/keycodes.yaml)（QMK / Vial 名）にあります。

- **基本キー**: 文字 `A`〜`Z`、数字 `"0"`〜`"9"`、ファンクションキー `F1`〜`F24`
  - 移動: `Up`, `Down`, `Left`, `Right`, `Home`, `End`, `PageUp`, `PageDown`
  - 編集: `Enter`, `Escape`, `Backspace`, `Tab`, `Space`, `Delete`
  - 修飾キー: `LShift`, `RShift`, `LCtrl`, `RCtrl`, `LAlt`, `RAlt`, `LGui`（`LCmd`）, `RGui`（`RCmd`）
  - 記号: `"-"`, `"="`, `"["`, `"]"`, `"\\"`, `";"`, `"'"`, `` "`" ``, `","`, `"."`, `"/"`
  - Shift 付きの記号: `"!"`, `"@"`, `"#"`, `"("`, `")"`, `":"` など
- **レイヤー操作**: `MO(n)`（押している間）、`TG(n)`（トグル）、`TO(n)`（切り替え）、`TT(n)`（タップでトグル）、`DF(n)`（デフォルト）、`OSL(n)`（1 回だけ）
  - `LT(n, key)` / `LTn(key)`: 長押しでレイヤー、タップでキー
  - 引数は数値です（`MO(KC_3)` はエラー）
- **修飾キー**:
  - Mod-Tap: `LCTL_T(key)`, `LSFT_T(key)`, `LALT_T(key)`, `LGUI_T(key)`, `MEH_T(key)` など、`MT(MOD_LCTL|MOD_LSFT, key)`
  - One Shot: `OSM(MOD_LSFT)`
  - 修飾キー付き: `LSFT(key)`, `C(key)`, `S(key)`, `A(key)`, `G(key)` と組み合わせ（`C_S`, `SGUI`, `MEH`, `HYPR` など）
  - `LM(n, MOD_LCTL)`
- **メディア・マウス**: `VolumeUp`, `VolumeDown`, `Mute`, `MediaPlayPause` など。`MouseUp`, `MouseDown`, `MouseLeft`, `MouseRight`, `MouseButton1`〜, `MouseWheelUp` など
- **特殊キー**: `Trans`（`Transparent`, `___`）は下のレイヤーを使う、`NoKey` は無効。`Reset`（`QK_BOOT`）は設定ファイルには書けますが、キーボードへの直接反映では書き込みません

### decompile の書き方

decompile は修飾キー付きのキーを次の順で書きます。

1. エイリアスがあればエイリアス（`LSFT(KC_1)` → `!`、`LSFT(KC_9)` → `(`）
2. なければ修飾キー表現（`Ctrl, Option, Shift, Command` の順。右側は `RCtrl, ROption, RShift, RCommand`）
   - `LGUI(KC_Q)` → `Command + Q`、`HYPR(KC_LEFT)` → `Ctrl + Option + Shift + Command + Left`

そのため `Cmd + Q` と書いた設定を compile → decompile すると `Command + Q` になります（値は同じです）。

## YAML の注意

YAML は引用符のない値の型を自動で決めるので、次のものは **必ず引用符で囲みます**。

| 書きたいもの | 正しい書き方 | 引用符がないと |
|---|---|---|
| 数字のキー `1` | `"1"` | 整数の 1 になる |
| 記号のキー `!` `[` `]` `-` など | `"!"` `"["` | YAML の文法として解釈されてエラーになる |
| `yes` `no` `on` `off` | 引用符で囲む | 真偽値になる |

`Command + Shift + [` のように、記号が文字列の途中にあるときは引用符なしでも書けます（YAML の文法上、行頭の `[` `{` `!` などだけが問題になります）。
ただし `{ push: ..., ccw: ... }` のような 1 行のマッピングの中では、`[` `]` `,` などを含む値は引用符で囲みます。

ほかにも、インデントの誤りやタブの混在がよくある原因です。
このような誤りは `cornix validate`（や `compile`）が「ファイル: 位置: 内容」の形で、書き直し方とあわせて教えてくれます。

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
```

問題は 1 件ずつ止まらずにすべて集め、「ファイル: キーの位置: 内容」で表示します（下の 1 段目の問題が残っていると、2 段目の検査はそれを直したあとで行います）。`cornix compile`（と `status` / `apply`）も同じ検証を先に行います。警告（`⚠  Warning: …`）だけなら compile は続行します。

検証は 2 段階です。

1. **ファイルの構造（読み込み時）**
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
2. **設定全体の整合性**
   - **件数の上限**: レイヤー 10、マクロ 32、タップダンス 32、コンボ 32、コンボのトリガー 4 キー
   - **重複**: レイヤー・マクロ・タップダンス・コンボの番号、マクロ・タップダンス・コンボの名前
   - **参照先**: `Macro(...)` / `M3` / `TapDance(...)` / `TD(2)` / `Shortcut(...)` の参照先が定義されているか
   - **レイヤー番号**: `MO(n)` / `LT(n, ...)` などのレイヤー番号がレイヤー数を超えていないか（エラー）、定義されていないレイヤーを指していないか（警告）
   - **レイヤーの抜け**: 番号が飛んでいるレイヤー（警告）

## 設定ファイルに名前を付ける（`rename`）

`cornix rename` は、Claude がマクロ・タップダンス・コンボ・レイヤーの内容を読んで、意味のある名前とファイル名を提案します。Claude Code CLI（`claude` コマンド）が必要です。

```bash
ls profiles/default/macros/
# 00_macro.yaml, 01_macro.yaml, ...（decompile が付けた既定の名前）

cornix rename

ls profiles/default/macros/
# 00_bracket_pair.yaml, 01_end_of_line.yaml, ...
```

流れ:

1. **設定の確認**: 設定を検証します。問題があれば先に直すよう表示して終了します
2. **Claude による提案**: 既定の名前（`Macro N`, `TapDance N`, `Combo N`, `Layer N`）のファイルを Claude CLI に渡し、提案を `<tmp>/rename_plans.json` に受け取ります
   - マクロ: キーの並びから目的を推測（例: `[`, `]`, `Left` → "Bracket Pair"）
   - タップダンス: tap / hold / double tap の動作から推測
   - コンボ: トリガーと出力から推測
   - レイヤー: description や割り当てから推測
3. **提案の確認**: 1 件ずつ `Y`（承認）/ `n`（スキップ）/ `e`（ファイル名・名前・説明を編集）で選びます
4. **リネーム**: 設定ディレクトリの隣（`profiles/default.backup_<日時>/` など）にバックアップを取り、ファイル名と `name` / `description` を変え、
   設定のすべての YAML にある名前参照 `Macro('旧名')` / `TapDance('旧名')` を新しい名前に書き換えます（テキストの置換なので、コンボの出力やエンコーダ、関数の引数、`shortcuts.yaml` の中にある参照も対象です）
5. **検証**: 変更の前後で設定を compile した結果（16bit 値）を比べ、違えばバックアップから元に戻します
6. **後片付け**: 一時ファイルを消し、バックアップを消すかどうかを尋ねます

提案の例:

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

安全のための仕組み:

- 番号のプレフィックス（`00_`, `0_` など）は変えられません（変えようとするとエラー）
- まとめて実行し、1 件でも失敗したら全体を元に戻します
- 番号参照（`Macro(3)`, `M3`, `TD(2)`）は名前に依存しないので書き換えません

### Claude を使わずに実行する（`bin/rename_file`）

```bash
# 1 ファイル（--dry-run で確認だけ）
ruby bin/rename_file --config-dir profiles/default \
  --old-path profiles/default/macros/03_macro.yaml \
  --new-basename 03_end_of_line.yaml \
  --name "End of Line" \
  --description "Jump to end of line" \
  --dry-run

# JSON の計画でまとめて（成功したらバックアップを消す）
ruby bin/rename_file --config-dir profiles/default --batch tmp/profiles/default/rename_plans.json --cleanup-backup
```

計画ファイルの形式:

```json
[
  {
    "old_path": "profiles/default/macros/03_macro.yaml",
    "new_basename": "03_end_of_line.yaml",
    "content_updates": {
      "name": "End of Line",
      "description": "Jump to end of line with Cmd+Right"
    }
  }
]
```

`bin/rename_file` は `.cornix.yml` を読まないので、`profiles/` の設定では `--config-dir` を必ず付けてください（既定はカレントディレクトリの `config`）。結果は JSON で表示し、失敗したときは終了コード 1 です。Claude CLI が見つからない、または出力から JSON を取り出せないときは、`cornix rename` もこの形式の計画ファイルを手で書くよう案内します。

## Vial の layout.vil と変換する

キーボードへ直接書き込まずに、Vial（Web / GUI）で読み書きすることもできます。

```bash
# 1. Vial の "File > Export Layout" で layout.vil を書き出す（例: ~/Downloads/layout.vil）
# 2. YAML にする（profiles/default/ と .cornix.yml を作る）
cornix init --from ~/Downloads/layout.vil
# 3. 設定を編集する
vim profiles/default/layers/0_layer.yaml
# 4. layout.vil にする（自動で検証してから <tmp>/build/layout.vil を書く）
cornix compile
cornix compile -o my.vil    # 出力先を指定する（相対パスはカレントディレクトリから）
# 5. Vial の "File > Import Layout" で <tmp>/build/layout.vil を読み込む
```

- compile は先に検証を行い、問題があれば .vil を書かずに終了します（終了コード 1）
- すでにある設定ディレクトリに layout.vil を書き出すときは `cornix decompile [FILE]` を使います（`FILE` の既定は `<tmp>/layout.vil`）。
  設定ディレクトリにすでに設定があると止まります（[`pull` が止まるとき](#pull-が止まるとき)と同じ）
- init / decompile に成功すると、設定ディレクトリに `.decompile.lock`（元ファイルとチェックサム）を作ります
- `cornix device diff` / `device apply` もファイルを省略すると compile の出力を使います（まだ compile していなければ、先に compile するよう案内して終了します）

### 生成したファイルを消す（`cleanup`）

```bash
cornix cleanup      # 設定ディレクトリと <tmp>/build/layout.vil を消す（ロックファイルがあれば消さずに止まる）
cornix cleanup -f   # ロックファイルがあっても、確認（y/N）してから消す
```

消すのは、ほかのコマンドと同じ[決まり方](#設定ディレクトリの決まり方)で選ばれる設定ディレクトリ（`profiles/default/` など）と compile の出力です。

### マクロ変更時の承認操作（アンロック）について

Vial（Web / GUI）はマクロの保存時と `QK_BOOT` の割り当て時に、指定の 2 キーを長押しする「アンロック」を求めます。これは Vial アプリ側の動作で、Cornix のファームウェア（RMK 0.8 系）はマクロの書き込みにロック状態を確認していません。そのため `cornix apply` / `cornix device` / MCP ではアンロック操作は不要です（`QK_BOOT` などの boot 系キーコードはそもそも書き込めないようにしています）。

## バックアップと元に戻す

`apply` と `restore` は、書き込む前にキーボードの状態を `<tmp>/device_backups/` に日時付きの .vil で保存します。
自分で取っておきたいときは `cornix device backup` を実行します。

```bash
cornix restore                                      # 最後のバックアップ（直前の apply の前の状態）に戻す
cornix restore tmp/profiles/default/device_backups/<日時>.vil   # 指定したバックアップに戻す
cornix restore --yes                                # 確認を省略する
```

- 最後に取ったバックアップとの差分を表示し、確認してから書き込みます
- `restore` も書き込み前に今の状態をバックアップするので、続けてもう一度 `restore` すると復元前の状態に戻ります
- `restore` はキーボードだけを戻します。設定ファイルも戻したいときは、Git で戻すか、設定を退避してから `cornix pull` で読み直してください

## 設定の置き場所と利用の形

### 設定ディレクトリの決まり方

コマンドが使う設定ディレクトリは、次の順で決まります（上ほど優先）。

1. `--config DIR`
2. 環境変数 `CORNIX_CONFIG`
3. `--profile NAME`（`profiles/NAME/`）
4. カレントディレクトリから親へたどって最初に見つかる `.cornix.yml`（`--root DIR` を付けたときは `DIR/.cornix.yml` だけを見ます）
   - `profile: NAME` … `.cornix.yml` と同じ場所の `profiles/NAME/`
   - `config: PATH` … `.cornix.yml` からの相対パス
5. どれもなければ、このリポジトリの `config/`（以前の置き場所。後方互換のため残しています）

`config/` 以外の設定を使うときは、`compile` / `decompile` / `validate` / `pull` / `status` / `apply` / `restore` / `rename` / `cleanup` の最初の行に「設定: profiles/default（.cornix.yml）」のように、どの設定をどう決めたかを表示します。

`<tmp>`（作業用ディレクトリ）は設定ごとに分かれます。`profiles/NAME/` なら `tmp/profiles/NAME/`、`config/` なら `tmp/` です。
`profiles/` の外の設定ディレクトリ（`--config` で指定したものなど）では、同じ名前のディレクトリと混ざらないよう、名前にパスのハッシュが付きます。

1 つのリポジトリに複数の設定を置けます（例: `profiles/work/`、`profiles/game/`）。切り替えるには `.cornix.yml` を書き換えるか、`--profile` を付けます。

### `init` が作るもの

```bash
cornix init [DIR] [--profile NAME | --config DIR] [--from FILE] [--no-pull]
```

- `DIR` は `.cornix.yml`・`tmp/`・`profiles/` を置く場所です（既定は `--root` か、カレントディレクトリ）
- 作る場所は、`--profile NAME` なら `DIR/profiles/NAME/`、`--config` ならその場所、どちらもなければ `DIR/profiles/default/` です
  （init の場所は共通のオプションだけで決まり、環境変数 `CORNIX_CONFIG` や既存の `.cornix.yml` は見ません）
- 次からその設定が使われるように `.cornix.yml`（`profile: NAME` か `config: PATH`）を作ります。すでにあれば変えません
  （`--config` でこのリポジトリの `config/` を指定したときは作りません）
- `.cornix.yml` がなく中身のある `config/` がある場所では、使う設定が黙って変わらないよう、オプションなしの `cornix init` は何も作らずに止まります。
  `--profile NAME` か `--config DIR` で場所を指定してください。指定して作ると、次からは新しい設定が使われることを表示します
- このリポジトリの外に作るときは、`.gitignore` に `tmp/` と `.decompile.lock` の行を足します（設定だけのリポジトリのため）。すでにあれば足しません
- キーボードにつながれば（`--from FILE` ならその .vil から）、decompile と同じ内容の設定を書きます

このリポジトリの `.gitignore` では、`/.cornix.yml` と `/profiles/` を Git の管理から外しています（手元だけの設定のため）。
フォークやブランチで設定を管理するなら、この 2 行を消してください。

### 以前の `config/` を使っている場合

`.cornix.yml` がなければ、今までどおりこのリポジトリの `config/` が使われるので、何もしなくても動きます。
この状態でオプションなしの `cornix init` を実行しても、`config/` を守るために止まります。
`profiles/` に移すときは、ディレクトリを動かして `.cornix.yml` を書きます。

```bash
mkdir -p profiles && mv config profiles/default
echo "profile: default" > .cornix.yml
cornix validate          # 「設定: profiles/default（.cornix.yml）」と表示されれば移せています
```

`<tmp>` も `tmp/` から `tmp/profiles/default/` に変わるので、`restore` に今までのバックアップを使いたいときは
`tmp/device_backups/` を `tmp/profiles/default/device_backups/` にコピーしてください。

### 利用の形

**A. このリポジトリ（かフォーク）で使う**

いちばん簡単な形です。`cornix init` で `profiles/default/` を作り、そのまま `cornix status` / `cornix apply` を使います。
設定を Git で管理するなら、`.gitignore` から `/.cornix.yml` と `/profiles/` の行を消し、main の上に設定をコミットしたブランチを作ります
（作者の `authors-keymap` ブランチと同じ形です）。

**B. フォークして `profiles/` に複数の設定を置く**

```bash
# GitHub でこのリポジトリをフォークしてから
git clone <自分のフォーク> cornix-layout && cd cornix-layout
bundle install
cornix init --profile <自分の名前>
# 名前に使えるのは英数字と . _ -（先頭は英数字）
# .gitignore から /.cornix.yml と /profiles/ の行を消してから
git add .gitignore profiles .cornix.yml && git commit -m "設定を追加"
git push
```

本家は `profiles/` の中と `.cornix.yml` を変更しないので、本家の更新は GitHub の「Sync fork」か `git pull upstream main` で取り込めます。

**C. 設定だけを別のリポジトリに置く**

ツールを clone して `cornix` を PATH に通し、設定は別のディレクトリ（リポジトリ）に置きます。

```bash
mkdir my-cornix && cd my-cornix && git init
cornix init                    # profiles/default/ と .cornix.yml を作り、.gitignore に tmp/ と .decompile.lock を足す
cornix status                  # このディレクトリ（かその下）で実行する
```

ツールを更新するときは、clone したディレクトリで `git pull` するだけです。

### サンプルの設定

次のブランチに、サンプルの設定があります。どちらも main の上に、設定（`profiles/<名前>/`）と `.cornix.yml` を載せたブランチです。

| ブランチ | 設定 | 内容 |
|---|---|---|
| `cornix-default-keymap` | `profiles/cornix-default/` | Cornix の標準的なレイアウト。初めての方におすすめです |
| `authors-keymap` | `profiles/authors/` | 作者が実際に使っているキーマップ。名前参照・修飾キー表現・コンボなどの使用例があります |

ブランチの `.cornix.yml` が手元の `.cornix.yml` とぶつからないよう、別のディレクトリ（worktree）で開くのがおすすめです。
フォークを clone した場合は、このブランチがないことがあるので、先に本家から取ってきます
（`git remote add upstream https://github.com/guccyon/cornix-layout.git && git fetch upstream` のあと、`upstream/cornix-default-keymap` を指定します）。

```bash
git worktree add ../cornix-default-keymap cornix-default-keymap
cd ../cornix-default-keymap
cornix compile          # 「設定: profiles/cornix-default（.cornix.yml）」で compile する
```

サンプル設定の提供も歓迎します（新しいブランチで共有し、プルリクエストを作成してください）。

## MCP サーバーとして使う

`cornix mcp` で MCP（Model Context Protocol）サーバーを標準入出力で起動します。
AI エージェントから「キーボードの今の設定を読んで」「この layout.vil を反映して」といった操作ができます。

- **Claude Code**: リポジトリ直下の `.mcp.json` に `cornix-device` として登録済みです。このディレクトリで Claude Code を開き、初回に表示される MCP サーバーの承認で許可してください
- **その他のクライアント**（Claude Desktop など）: 次のように絶対パスで登録します。`ruby` が見つからない場合（mise / rbenv など）は `command` に Ruby の絶対パスを指定してください

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

設定ディレクトリは、ほかのコマンドと同じ順で決まります。別の場所の設定を使うときは、`args` に `--root /path/to/my-cornix` や `--profile NAME` を足します。

`cornix mcp` は環境変数 `LANG` が未設定でも UTF-8 で入出力し、応答の JSON は非 ASCII 文字を `\uXXXX` にエスケープして返すので、クライアント側のロケールに関係なく読み取れます。

使えるツール:

| ツール | 書き込み | 内容 |
|---|---|---|
| `keyboard_info` | しない | キーボードの情報 |
| `read_keymap` | しない | 今の状態を layout.vil 形式で返す・保存する |
| `backup` / `list_backups` | しない | バックアップの保存と一覧 |
| `apply_layout` | `dry_run: false` のときだけ | 既定は dry run で差分と `confirm_token` を返す。`dry_run: false` と `confirm_token` を付けたときだけ書き込む |
| `restore_backup` | `dry_run: false` のときだけ | 最後のバックアップ（`backup_path` で指定も可）に戻す。dry run と `confirm_token` の扱いは `apply_layout` と同じ |

反映の流れ:

1. `cornix compile` で compile の出力（`<tmp>/build/layout.vil`。`apply_layout` の `vil_path` の既定）を作る
2. `apply_layout`（dry run）で差分と `confirm_token` を受け取り、内容を確認する
3. 同意したら `apply_layout` を `dry_run: false` と `confirm_token` を付けて呼ぶ。自動バックアップ → 差分のみ書き込み → 読み戻し検証が行われる
4. 元に戻すときは `restore_backup` を同じく dry run → `confirm_token` 付きの順で呼ぶ（古いバックアップは `list_backups` で選んで `backup_path` に指定）

確認後に差分が変わっていた場合（キーボード側やファイルが変更された場合）、トークンが一致しないため書き込みは拒否されます。
キーボードが接続されていない場合、どのツールもエラー応答を返し、何も書き込みません。
AI アシスタントに書き込みを任せるときも、書き込む前に dry run の結果を見せてもらってください。

## 安全のための仕組み

Cornix のファームウェアは RMK 0.8 系で、vial-qmk と違ってロックや範囲検査がほとんどありません（bootloader 移行や EEPROM リセットがロックなしで実行され、範囲外の書き込みではファームウェアがパニックします）。そのため次のようにしています。

- **送るコマンドの許可リスト**: HID ブリッジ（`ext/cornix_hid/main.swift`）は許可リストにあるコマンドしか送りません。bootloader 移行・EEPROM リセット・全消去・アンロック・キーマップ一括書き込み（RMK 0.8 にバグあり）は送れません（`tmp/cornix-hid --self-test` で確認できます）
- **範囲の検査**: キーは Vial GUI と同じ 1 キーずつの書き込みだけを使い、layer / row / col・マクロのオフセット・各エントリ番号はすべて送信前に範囲を検査します
- **書き込まないキー**: `QK_BOOT` などの boot 系キーコード（[data/dangerous_keycodes.yaml](data/dangerous_keycodes.yaml)）は、設定ファイルに書いてあっても書き込みません
- **書く前に検証**: `status` / `apply` は毎回 compile し、検証エラーがあればキーボードには触れません
- **確認してから書き込む**: `apply` / `restore` は差分を表示して確認を求めます。MCP は dry run と `confirm_token` の二段階です
- **書く前のバックアップ**: 書き込む直前の状態を必ず `<tmp>/device_backups/` に保存します
- **差分だけを書き込んで確かめる**: 変わった項目だけを書き込み、最後にキーボードを読み直して一致を確かめます

## トラブルシューティング

### キーボードが接続されていないとき

`cornix pull` / `status` / `apply` / `restore`、`cornix device` の各コマンドと MCP の各ツールは、最初にキーボードを探して接続します。見つからない場合は何も書き込まずにエラーで終了します（CLI は標準エラー出力に表示して終了コード 1、MCP はエラー応答）。

```
エラー: Cornix が見つかりません。Mac と Bluetooth（または USB）で接続されているか、スリープしていないか、別の機器に接続先が切り替わっていないかを確認してください
```

- **Bluetooth が切れている・キーボードの電源が切れている**: 上のエラーになります。キーを 1 回押してスリープを解除するか、Mac との接続を確認してから再実行してください
- **キーボードが別の機器（BT1 / BT2 など）に切り替わっている**: Mac からは見えないので同じエラーになります。Mac に接続しているチャンネルに切り替えてください
- **読み出しや書き込みの途中で接続が切れた**: 1 秒以内に応答がないと「キーボードから応答がありません」というエラーで中断します。書き込み中だった場合は、何件目まで書き込んだかと反映前のバックアップのパスを表示するので、再接続してから `cornix apply` をやり直すか、`cornix restore` で反映前に戻してください（どちらも差分だけを書き込みます）

### よくあるエラー

**キーコードを解釈できない**

```
Error: layers/0_base.yaml: mapping.left_hand.row0.Q: キーコード「Spce」を解釈できません: 「Spce」は不明なキーコードです
```

タイプミスです（`Spce` → `Space`）。使える名前は [data/aliases.yaml](data/aliases.yaml) と [data/keycodes.yaml](data/keycodes.yaml) にあります。

**position_map にないキー**

```
Error: layers/0_base.yaml: mapping.left_hand.row1.capz: position_map の left_hand.row1 にないキーです（使えるキー: caps, A, S, D, F, G）
```

`profiles/default/position_map.yaml` のそのグループにあるシンボルを使うか、`position_map.yaml` を変えます。

**番号や名前の重複**

```
Error: layers/2_layer.yaml: index: レイヤーの番号が重複しています: 2
Error: macros/01_macro.yaml: name: マクロの名前が重複しています: Bracket Pair
```

どちらかのファイルの `index` / `name` を変えます。

**存在しないマクロ・タップダンスの参照**

```
Error: layers/0_base.yaml: mapping.left_hand.row0.Q: キーコード「Macro('Unknown')」を解釈できません: マクロ「Unknown」が見つかりません
```

`profiles/default/macros/*.yaml` の `name` を確認し、参照を直します（`grep '^name:' profiles/default/macros/*.yaml`）。

**左右の修飾キーの混在**

```
キーコード「Shift + RCmd + A」を解釈できません: 左右の修飾キーは混在できません（例: Shift と RCmd）
```

QMK の修飾キー付きキーコードは左右どちらか一方しか表せません。どちらかにそろえます。

**decompile / pull が止まる、cleanup が止まる**

[`pull` が止まるとき](#pull-が止まるとき)を見てください。cleanup が `Protected: config/ directory has an active lock file` で止まる場合は `cornix cleanup -f` を使います。

**Claude Code CLI（`claude` コマンド）が見つからない**

```
  ❌ Error: Claude CLI not found
```

`cornix rename` には Claude Code CLI が必要です。https://claude.ai/download からインストールし、`claude --version` で確認します。

**Round-trip チェックが失敗する**

`ruby bin/diff_layouts` の出力で、どのレイヤー・行・項目が違うかを確認します（[Round-trip チェック](#round-trip-チェック)）。元の layout.vil と生成した layout.vil を添えて issue を作成してください。

## 開発者向け

### 構成

内部は層に分かれていて、設定ファイル・layout.vil・HID のバイト列はすべて外側の表現として扱い、内側では型のある値（ドメインモデル）だけを扱います。

```
Interface       CLI（bin/cornix → Interface::Cli::Main）・MCP サーバー
Application     ユースケース（Init / Compile / Decompile / Validate / Cleanup / RenameFiles / Device*）、Workspace と Environment
Mapping         キーコードの表記と値の変換（KeycodeNotation / VialNotation / KeycodeCodec）、Profile ⇄ DeviceImage（ProfileMapper）
Planning        DeviceImage どうしの差分と書き込み計画
Domain          Profile と値オブジェクト（Keycode, Layer, Macro, TapDance, Combo, PositionMap ...）
Image           DeviceImage（layout.vil / 実機の状態を 16bit 値のまま持つ）
Storage         設定ファイル（ConfigRepository）・layout.vil（VilFile）・バックアップ・.cornix.yml（SettingsFile）
Device          HID ブリッジとの通信、実機の読み出し・書き込み
```

```
compile    設定ディレクトリ → Profile → DeviceImage → layout.vil
decompile  layout.vil → DeviceImage → Profile → 設定ディレクトリ
device     layout.vil → DeviceImage（目標）と 実機 → DeviceImage（現在）の差分を書き込み、読み直して検証
```

設計の文書（日本語）:

- [docs/architecture.md](docs/architecture.md) … 方針・依存の向き・データの流れ・コード規約
- [docs/tasks.md](docs/tasks.md) … 主なクラスの公開メソッド、リファクタの経緯
- 開発のルールは [.claude/CLAUDE.md](.claude/CLAUDE.md) にあります

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
├── .cornix.yml               # 使う設定の指定（cornix init が作る。Git の管理外）
├── profiles/<名前>/          # 設定ファイル（cornix init が作る。Git の管理外）
├── config/                   # 以前の置き場所の設定（後方互換。main にはない）
└── tmp/                      # 生成物（Git の管理外）
    └── profiles/<名前>/      # 設定ごとの <tmp>（config/ の設定なら tmp/ の直下）
        ├── build/layout.vil  # compile の出力（status / apply が使う）
        ├── layout.vil        # decompile の既定の入力（pull がキーボードの状態を書く）
        └── device_backups/   # apply / restore の前のバックアップ
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
- `spec/docs/readme_sync_spec.rb` は README.md（英語）と README.ja.md（日本語）の構成がそろっていることを検査します
- 実機の代わりに RMK 0.8 の応答を模した `FakeRmkDevice` を使うので、キーボードなしで実行できます

詳細は [spec/README.md](spec/README.md) を参照してください。GitHub Actions でも push / pull request ごとに RSpec を実行します。

### Round-trip チェック

手元の layout.vil で decompile → compile が元に戻るかを確かめる手順です。

```bash
rm -rf /tmp/cornix-roundtrip                                      # 前回の確認用の設定が残っていれば消す
cornix init /tmp/cornix-roundtrip --from ~/Downloads/layout.vil   # 確認用の別の場所に設定を作る
cornix compile --root /tmp/cornix-roundtrip                       # → /tmp/cornix-roundtrip/tmp/profiles/default/build/layout.vil
ruby bin/diff_layouts ~/Downloads/layout.vil /tmp/cornix-roundtrip/tmp/profiles/default/build/layout.vil
# 期待結果: === ✓ FILES ARE IDENTICAL ===
```

`bin/diff_layouts [FILE1 FILE2]`（省略するとカレントディレクトリの `tmp/layout.vil` と `tmp/build/layout.vil`。旧 `config/` の場合のパスなので、`profiles/` では 2 つのファイルを指定します）は 2 つの layout.vil を読み込み、キー・エンコーダ・マクロ・タップダンス・コンボ・設定を 16bit 値で比べます。同じ値の別表記（`KC_PGDN` と `KC_PGDOWN` など）は同じとみなします。違えば場所を表示して終了コード 1 です。

### コントリビューション

プルリクエスト歓迎です。

1. このリポジトリをフォーク
2. フィーチャーブランチを作成（`git checkout -b feature/amazing-feature`）
3. `LANG=ja_JP.UTF-8 bundle exec rspec` がすべて通ることを確認
4. コミットしてプッシュ
5. プルリクエストを作成

README を変えるときは、README.md（英語）と README.ja.md（日本語）の両方を同じコミットで変えてください。

## 注意

- このツールは Cornix の公式の製品ではなく、開発元とは関係ありません
- ファームウェアの更新で通信の仕様が変わる可能性があります
- このツールの使用によって起きた問題について、作者は責任を負いません。大事な設定は Vial で layout.vil を書き出すなどして残しておいてください
- ライセンス: MIT License
- 参考: [Vial Documentation](https://get.vial.today/)、[QMK Firmware Documentation](https://docs.qmk.fm/)、[QMK Keycodes](https://docs.qmk.fm/keycodes_basic)
