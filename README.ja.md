# Cornix Keyboard Layout Manager

[English](README.md) | 日本語

Cornix キーボードのキーマップ（レイヤー・エンコーダ・マクロ・タップダンス・コンボ・QMK Settings）を
人が読める YAML ファイルで管理し、Vial を使わずに接続中のキーボードへ直接書き込むツールです。

- キーボードから設定を読み出して YAML にする（`pull`）
- YAML を編集して、キーボードとの差分を確認する（`status`）
- 差分だけをキーボードに書き込む（`apply`）。書く前に必ずバックアップを取り、書いたあとに読み直して確かめる
- 気に入らなければ、書き込む前の状態に戻す（`restore`）。読んだ・書いた・compile した状態はスナップショットとして残る（`snapshots`）

設定ファイルは Git で管理できるので、変更の履歴を残したり、用途ごとに設定を切り替えたりできます。
YAML では `Cmd + Q` のような修飾キー表現、`Macro('Bracket Pair')` のような名前での参照、名前付きショートカット、注記、コメントが使えます。
MCP サーバーとしても動くので、Claude などの AI アシスタントからキーボードの設定を読んだり変えたりすることもできます。
Vial で読み書きしたいときは、`layout.vil` との相互変換もできます（[Vial を使う場合](#vial-を使う場合compile--decompile)）。

> **非公式のツールです。** Cornix の開発元とは関係ありません。
> キーボードへの直接の読み書きは、実機での検証と Vial / RMK の公開されているソースをもとにしています。使用は自己責任でお願いします。

## 目次

- [対応しているもの](#対応しているもの)
- [必要なもの](#必要なもの)
- [はじめ方](#はじめ方)
- [コマンドの一覧](#コマンドの一覧)
- [設定ファイルの書き方](#設定ファイルの書き方)
- [キーの書き方](#キーの書き方)
- [YAML の注意](#yaml-の注意)
- [設定ファイルの検証](#設定ファイルの検証)
- [名前を付ける（rename）](#名前を付けるrename)
- [スナップショットと元に戻す](#スナップショットと元に戻す)
- [設定の置き場所と利用の形](#設定の置き場所と利用の形)
- [VS Code の画面で編集する](#vs-code-の画面で編集する)
- [MCP サーバーとして使う](#mcp-サーバーとして使う)
- [安全のための仕組み](#安全のための仕組み)
- [トラブルシューティング](#トラブルシューティング)
- [Vial を使う場合（compile / decompile）](#vial-を使う場合compile--decompile)
- [開発者向け](#開発者向け)
- [注意](#注意)

## 対応しているもの

| 項目 | 対応 |
|---|---|
| キーボード | Cornix |
| ファームウェア | RMK 0.8 系（Vial プロトコル 6） |
| OS | キーボードとの通信（`pull` / `status` / `apply` / `restore` / `device` / `mcp`）は macOS のみ。`validate` や Vial 用の変換は Ruby が動けばどこでも |
| 接続 | Bluetooth または USB |

## 必要なもの

- **Ruby 3.2 以上**（`Data.define` を使うため。CI は 4.0 系）。標準ライブラリだけで動くので、gem のインストール（`bundle install`）は要りません
- **Xcode Command Line Tools**（キーボードとの通信に使います。`swiftc` がなければ `xcode-select --install`）
  - 通信には小さな Swift のプログラム（`ext/cornix_hid/main.swift`）を使います。初めて使うときに自動でビルドされ、`tmp/cornix-hid` に置かれます
- **Claude Code CLI**（`claude` コマンド。`cornix rename` を使うときだけ）

## はじめ方

### 1. 取得する

```bash
git clone https://github.com/guccyon/cornix-layout.git   # 自分のフォークを clone してもよい
cd cornix-layout
```

このまま `cornix init` すると、設定は Git の管理外になります（`.gitignore` で外しています）。設定を Git で管理するなら、フォークするか、設定を別のリポジトリに置きます（[利用の形](#利用の形)）。

`cornix` コマンドとして使いたいときは、`bin/cornix` への symlink を PATH の通ったディレクトリに置きます（`ruby bin/cornix <コマンド>` でも実行できます）。

```bash
mkdir -p ~/.local/bin && ln -s "$PWD/bin/cornix" ~/.local/bin/cornix   # ~/.local/bin が PATH にない場合は PATH に足す
cornix help             # コマンドの一覧（cornix help <コマンド> で詳しく）
cornix --version        # ツールのバージョン
```

リリースには `vX.Y.Z` のタグを付けています（例: `git checkout v1.0.0`）。バージョンごとの変更は [CHANGELOG.md](CHANGELOG.md) にあります。

### 2. 設定を作る（`init`）

Cornix を Mac と Bluetooth（または USB）でつなぎ、`cornix device info` で接続を確かめてから実行します。

```bash
cornix init
```

キーボードの今の設定が `profiles/default/` に YAML で書き出され、使う設定の指定（`profile: default`）が `.cornix.yml` に書かれます。
以降のコマンドはこれを見て `profiles/default/` を使います。

- キーボードにつながらなかったときは空の設定ディレクトリだけを作るので、つないでから `cornix pull` を実行してください
- 設定ディレクトリにすでにファイルがあると、上書きせずに止まります
- 名前を変えたり、設定を別のリポジトリに置いたりするときは [設定の置き場所と利用の形](#設定の置き場所と利用の形) を見てください

初めはレイヤーやマクロの名前が `Layer 0`・`Macro 0` のようになっています。`cornix rename` を使うと、Claude が内容を読んで名前を提案します（[名前を付ける](#名前を付けるrename)）。

### 3. 設定を編集する

`profiles/default/` の YAML をエディタで編集します。書き方は [設定ファイルの書き方](#設定ファイルの書き方) を見てください。
書き方に誤りがないかは、キーボードなしで `cornix validate` で確かめられます。

### 4. 差分を見る（`status`）

```bash
cornix status
```

キーボードの今の状態と比べて、書き込まれる変更を表示します（キーボードには書き込みません）。差分がなければ終了コード 0、差分があれば 2 で終わります。

### 5. 書き込む（`apply`）

```bash
cornix apply           # 差分を表示し、[y/N] で確認してから書き込む
cornix apply --yes     # 確認を省略する
```

書き込む前のバックアップや確かめ方は [安全のための仕組み](#安全のための仕組み) にあります。

### 6. 元に戻す（`restore`）

```bash
cornix restore         # 直前の apply の前の状態に戻す
```

詳しくは [スナップショットと元に戻す](#スナップショットと元に戻す)。

## コマンドの一覧

```
cornix <コマンド> [オプション]
```

| コマンド | キーボード | 内容 |
|---|---|---|
| `init [DIR] [--from FILE] [--no-pull]` | 読む（`--from` / `--no-pull` なら使わない） | 設定ディレクトリ（既定は `profiles/default/`）と `.cornix.yml` を作り、キーボード（か `--from` の .vil）から設定を書く |
| `pull` | 読む | キーボードの状態を設定ディレクトリの YAML にする。設定がすでにあれば止まる |
| `status` | 読む | キーボードとの差分を表示する。差分があれば終了コード 2 |
| `apply [--yes]` | 書く（確認のあと） | 差分を確認してからキーボードへ書き込む |
| `restore [SNAPSHOT] [--yes]` | 書く（確認のあと） | スナップショット（既定は直前の apply の前の状態）に戻す |
| `snapshots [--kind KIND]` | 使わない | キーボードの状態と compile の出力のスナップショットを新しい順に一覧する |
| `validate` | 使わない | 設定ファイルを検証する |
| `rename` | 使わない | Claude の提案を確認しながら、設定ファイルに意味のある名前を付ける |
| `mcp` | ツールによる | MCP サーバーとして起動する（[MCP サーバーとして使う](#mcp-サーバーとして使う)） |
| `serve [--device [--allow-writes]]` | 使わない（`--device` では読む。書くのは `--allow-writes` のときだけ） | VS Code 拡張のバックエンド（[VS Code の画面で編集する](#vs-code-の画面で編集する)）。`--device` で実機と比べる・書き込む別のサーバーを起動します |

`cornix device` では、ファイルを指定して読み書きできます。

| サブコマンド | 内容 |
|---|---|
| `device info` | 接続中のキーボードの情報 |
| `device read [-o FILE]` | キーボードの状態を layout.vil 形式で出力する |
| `device backup` | キーボードの状態をスナップショット（種類 `backup`）として `<tmp>/snapshots/` に保存する |
| `device diff [FILE]` / `device apply [FILE] [--yes]` | 指定した .vil とキーボードの差分を表示する / 書き込む（既定は compile の出力） |
| `device restore [SNAPSHOT] [--yes]` | `restore` と同じ |

Vial 用の `compile` / `decompile` / `cleanup` は [Vial を使う場合](#vial-を使う場合compile--decompile) にあります。

共通のオプション（どのコマンドにも、コマンド名の前にも後にも付けられます）:

| オプション | 内容 |
|---|---|
| `--profile NAME` | `profiles/NAME/` の設定を使う |
| `--config DIR` | 設定ディレクトリを直接指定する |
| `--root DIR` | `tmp/` と `profiles/` を置く場所（既定は `.cornix.yml` のあるディレクトリ、なければこのリポジトリ） |
| `--json` | 結果を 1 つの JSON の値として標準出力に出す（スクリプト向け） |

ふだんは `.cornix.yml` で設定ディレクトリが決まるので、`--profile` / `--config` / `--root` を付ける必要はありません。

終了コード: `0` = 成功、`1` = エラー、`2` = 差分がある（`status` のみ）。エラーは標準エラー出力に `エラー: …` の形で表示します。

`--json` を付けると、標準出力には 1 つの JSON の値だけを出し、ほかの文章は混ぜません。終了コードは同じで、エラーは標準出力に `{ "error": "..." }` を出します。
たとえば `cornix status --json` は `{ "config", "compile", "diff" }`、`cornix validate --json` は `{ "config", "ok", "diagnostics": [{ "severity", "path", "message" }], "unused": [{ "kind", "file", "name" }] }` を出します。
`apply` / `restore` / `device apply` / `device restore` は `--json` では y/N で確認できないので、`--yes` も付けてください（付けないとキーボードに触れる前に止まります）。
`cleanup -f`・`rename`・`mcp`・`serve` は `--json` に対応していません（`help` は `--json` を無視します）。

### `pull` が止まるとき

設定ディレクトリにすでに設定（`layers/` か `macros/` のファイル）があると、`pull` は編集した内容を上書きしないよう、キーボードを読まずに止まります。

```
⚠️  Error: config/ directory already contains configuration files.
```

（設定ディレクトリが `profiles/` の下にあっても、この表示は `config/` のままです。）
キーボードの状態で作り直したいときは、今の設定を退避してから実行します。

```bash
mv profiles/default profiles/default.backup
cornix pull
```

キーボードには名前がないので、読み直した設定のレイヤーやマクロの名前・説明・注記・`Shortcut('名前')` の参照・ファイル名は既定に戻ります。必要なものは退避したディレクトリから戻してください。
キーボードとの違いを見たいだけなら `cornix status` で足ります。

## 設定ファイルの書き方

### ファイル構成

```
profiles/default/
├── metadata.yaml              # キーボードの情報（version / uid など）
├── position_map.yaml          # キーの名前と物理位置の対応
├── settings/qmk_settings.yaml # QMK Settings（tapping_term など）
├── shortcuts.yaml             # 名前付きショートカット（任意。自分で作る）
├── layers/0_layer.yaml        # レイヤー 0〜9
├── macros/00_macro.yaml       # マクロ
├── tap_dance/00_tap_dance.yaml # タップダンス
└── combos/00_combo.yaml       # コンボ
```

- ファイル名は自由に変えられます（拡張子は `.yaml` と `.yml` のどちらでも）。番号は YAML の `index` だけで決まり、ファイル名の先頭の番号は読みません。番号の接頭辞は並べて見やすくするためのもので、付けなくても、`index` と違っていてもかまいません（`pull` と拡張の追加は接頭辞を付けて書きます）
- `layers/` `macros/` `tap_dance/` `combos/` のファイルで `index` を書かない（または `index:` の値を空にする）と、未使用のファイルになります。`compile` に含めないので、使わない定義を消さずに控えておき、番号を書けば有効にできます。未使用のファイルも書き方は検査し、問題は警告として出します（`compile` は止めません）。ただし YAML として読めないファイルは未使用かどうか分からないので、今までどおりエラーです
- `pull` はキーを読みやすい形（エイリアス → 修飾キー表現 → 関数形式 → `0xHHHH` の順）で書き、マクロ・タップダンスは名前で参照します

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

- `mapping` の下は `position_map.yaml` と同じ形です。各手の `row0`〜`row3`・`thumb_keys` はすべて書きます（中身は空でかまいません）
- グループの中で書かなかったキーは割り当てなしになり、`compile` / `apply` では `NoKey`（KC_NO）として書き込みます。下のレイヤーを使うには `Trans` を書きます。書かなかったエンコーダの操作は `NoKey` です
- レイヤー番号を変えるときは `index` だけを変えます（ファイル名はそのままでかまいません）。`MO(2)` などは「レイヤー 2」という番号を指すので、ほかのファイルは書き換わりません。2 つのレイヤーの中身を入れ替えたいときは、2 つのファイルの `index` を入れ替えるだけで、`MO(2)` などはそのまま新しいレイヤー 2 を指します

### 注記（`note`）

キーを割り当てる場所（レイヤーのキー・エンコーダ、タップダンスの動作、コンボの `output_key`）には、`key` と `note` で注記を付けられます。

```yaml
# レイヤーファイルの抜粋
mapping:
  left_hand:
    row0:
      tab:
        key: TapDance('Tab Escape')
        note: タップで Tab、長押しで Escape
  encoders:
    left:
      push: { key: Mute, note: ミュート }
```

注記は設定ファイルにだけ残り、キーボードには書き込まれません。`key` は省略できません。

### マクロ

```yaml
# profiles/default/macros/01_curly_bracket_pair.yaml
name: Curly Bracket Pair
description: "{} を入力してカーソルを中に戻す"
index: 1
sequence:
  - action: down           # 押し下げる（複数なら同時に）
    keys: LShift
  - action: tap            # 順にタップ（1 キーなら keys: Left のように書いてもよい）
    keys: ["[", "]"]
  - action: up             # 離す
    keys: LShift
  - action: tap
    keys: Left
```

ほかに、文字列を入力する `action: text`（`content:` に ASCII の文字列）と、待つ `action: delay`（`duration:` にミリ秒）があります。

`sequence` の代わりに `preset` を書くと、同梱のショートカット（[data/shortcuts/](data/shortcuts/)）の手順のマクロになります。

```yaml
# profiles/default/macros/05_window_capture.yaml
index: 5
preset: 'macOS:システム:ウィンドウキャプチャ'   # ⌘⇧4 → Space
# name を省くと preset の名前になる（Macro('macOS:システム:ウィンドウキャプチャ') で参照できる）
```

- 連続して押すもの（`Fusion 360:スケッチ:スプライン` の S → P など）のように、1 つのキーで表せないショートカットはこの書き方で使います（`Shortcut(...)` では使えません）
- 1 つのキーのショートカットも書けます。修飾キー付きは「修飾キーを押す → キーを押して離す → 修飾キーを離す」の手順になります
- `preset` は同梱の定義だけを使います（`shortcuts.yaml` で同じ名前を上書きしても変わりません）
- マクロの番号（`index`）は自分で決めます。プリセットはデバイスに書き込まれないので、decompile ではふつうの `sequence` として書かれます

### タップダンス

```yaml
# profiles/default/tap_dance/00_tab_escape.yaml
name: Tab Escape
index: 0
actions:
  on_tap: Tab
  on_hold: Escape
  on_double_tap: NoKey     # 省略すると NoKey
  on_tap_hold: NoKey
tapping_term: 200          # ミリ秒（省略すると 250）
```

### コンボ

```yaml
# profiles/default/combos/06_left_click.yaml
name: Left Click
index: 6
trigger_keys: [Left, Down]   # 最大 4 キー
output_key: MouseButton1
```

トリガーはキーの位置ではなくキーコードで書きます。トリガーのキーがすべてそろうレイヤーが 1 つもないコンボは押せないので、`validate` で警告します（`Trans` の位置はレイヤー 0 の値で見ます）。

### QMK Settings

```yaml
# profiles/default/settings/qmk_settings.yaml
keyboard:
  tapping_term: 180
  permissive_hold: false
  hold_on_other_key_press: true
vial:
  combo_timing_window: 50
```

使える名前と値の幅は [data/qmk_settings.yaml](data/qmk_settings.yaml) にあります。書かなかった項目は、キーボードの今の値のまま変わりません。

### マクロ・タップダンスの参照

| 書き方 | マクロ | タップダンス |
|---|---|---|
| 名前（推奨） | `Macro('Bracket Pair')` | `TapDance('Tab Escape')` |
| 番号（`index`） | `Macro(0)` | `TapDance(2)` |
| QMK 形式 | `M0` | `TD(2)` |

- 名前はファイルの `name` です。`'` を含む名前は `"..."` で囲みます（`Macro("Rock'n Roll")`）
- 名前が見つからない、または番号のものが定義されていないと検証エラーです。未使用のファイル（`index` のないもの）の名前を参照しても検証エラーです
- 名前で参照していれば、マクロ・タップダンスの `index` を変えても参照は自然に新しい番号を指します（番号や QMK 形式で書いた参照は書き換わりません）
- マクロの中（`sequence` の `keys`）では参照は使えません

### 名前付きショートカット（`shortcuts.yaml`）

同じショートカットを何か所でも使うときは、名前を付けて定義し、`Shortcut('名前')` で参照します。

```yaml
# profiles/default/shortcuts.yaml
shortcuts:
  前のタブへ: Command + Shift + [
  次のタブへ: Command + Shift + ]
  括弧のペア: Macro('Bracket Pair')    # マクロ・タップダンスの参照も書ける
```

```yaml
# profiles/default/layers/0_base.yaml（抜粋）
mapping:
  left_hand:
    row0:
      Q: Shortcut('前のタブへ')
      W: Shortcut('次のタブへ')
```

- `Shortcut('名前')` は定義したキーコードそのものになります。関数の引数の中（`LT1(Shortcut('名前'))`）でも、その場所に書けるキー（`LT1` なら基本キー）を定義したときは使えます
- 定義にない名前は検証エラーです。`shortcuts.yaml` の値とマクロの中では `Shortcut(...)` は使えません
- `shortcuts.yaml` は `pull` では作られないので、自分で作ります
- [cornixhub](https://cornixhub.com/shortcuts) で共有されているショートカット（27 アプリ・824 件）は、定義しなくても `Shortcut('アプリ:カテゴリ:ラベル')` で使えます（例: `Shortcut('Spotify:再生:次のクリップ')`）。使える名前は [data/shortcuts/](data/shortcuts/) のファイルで確かめられます。ラベルは cornixhub の日本語表記です
- `shortcuts.yaml` に同じ名前を書くと、同梱の定義より優先されます
- decompile で `Shortcut(...)` に書き戻されるのは `shortcuts.yaml` の定義だけです（同梱の定義と同じ値はふつうのキーコードで書かれます）
- 複数の手順のもの（`macro:` で書いたもの）は `Shortcut(...)` では使えません。[マクロ](#マクロ)の `preset` で使います

### キーの位置（`position_map.yaml`）

レイヤーファイルで使うキーの名前（`left_hand.row0.Q` など）は `position_map.yaml` で決まります。名前は自由に変えられます。

```yaml
left_hand:
  row0: [tab, Q, W, E, R, T]
  row1: [caps, A, S, D, F, G]
  row2: [lshift, Z, X, C, V, B]
  row3: [lctrl, command, option]
  thumb_keys: [left, middle, right]
right_hand:
  row0: [Y, U, I, O, P, backspace]
  row1: [H, J, K, L, colon, enter]
  row2: [N, M, comma, dot, up, rshift]
  row3: [left, down, right]
  thumb_keys: [left, middle, right]
encoders:
  left: { push: push, ccw: ccw, cw: cw }
  right: { push: push, ccw: ccw, cw: cw }
```

- キーは左右の手とも**物理的に左から右**の順です
- 名前は同じグループの中で一意であればよく、使える文字は英数字・`_`・`-` です

## キーの書き方

大文字・小文字は区別します。

| 種類 | 書き方の例 | 説明 |
|---|---|---|
| キーの名前 | `A` `Tab` `Enter` `Escape` `Space` `Left` `F5` `VolumeUp` `MouseButton1` | 使える名前は [data/aliases.yaml](data/aliases.yaml) と [data/keycodes.yaml](data/keycodes.yaml)（`KC_TAB` などの QMK 名も書ける） |
| 記号 | `"!"` `"@"` `"["` `"1"` | 記号や数字 1 文字は引用符で囲みます |
| 何もしない / 下のレイヤーへ | `NoKey` / `Trans` | |
| 修飾キー表現 | `Cmd + Q` `Ctrl + Shift + F` | [修飾キー表現](#修飾キー表現) |
| QMK の関数 | `LGUI(KC_Q)` `LCTL_T(A)` `OSM(MOD_LSFT)` | 長押しで Ctrl・タップで A のような Mod-Tap も書ける |
| レイヤー操作 | `MO(1)` `TG(2)` `TO(0)` `LT(1, Space)` `LT1(Space)` | 番号はレイヤーの `index` |
| 参照 | `Macro('Bracket Pair')` `TapDance(2)` `Shortcut('前のタブへ')` | [参照](#マクロタップダンスの参照)、[ショートカット](#名前付きショートカットshortcutsyaml) |
| 生の値 | `0x7E00` | 表で表せない値（`pull` も解釈できない値はこの形で書きます） |

`QK_BOOT`（`Reset`）などの boot 系キーコードは設定ファイルには書けますが、キーボードには書き込みません。
`QK_REPEAT_KEY` / `QK_ALT_REPEAT_KEY` / `QK_LAYER_LOCK` / `USER08`〜`USER63` は Cornix が対応していないとみられるキーで（Vial でも表示されません）、書き込みはしますが `validate` / `compile` / `status` / `apply` で警告します（[data/unsupported_keycodes.yaml](data/unsupported_keycodes.yaml)）。

### 修飾キー表現

```yaml
Q: Cmd + Q                         # LGUI(KC_Q)
W: Shift + Cmd + Left              # SGUI(KC_LEFT)
E: Ctrl + Shift + Alt + Cmd + Y    # HYPR(KC_Y)
```

- 修飾キーの順序と `+` の前後の空白は自由です
- 修飾キーの名前: `Shift` / `Ctrl`（`Control`）/ `Alt`（`Option`）/ `Cmd`（`Command`, `Gui`, `Win`）。右側は `RShift` / `RCtrl` / `RAlt` / `RCmd` など
- **左右の修飾キーは混ぜられません**（`Shift + RCmd + A` はエラー）。修飾できるのは基本キーだけです
- `pull` は `Ctrl, Option, Shift, Command` の順で書くので、`Cmd + Q` と書いた設定は読み直すと `Command + Q` になります（値は同じです）

## YAML の注意

YAML は引用符のない値の型を自動で決めるので、次のものは **必ず引用符で囲みます**。

| 書きたいもの | 正しい書き方 | 引用符がないと |
|---|---|---|
| 数字のキー `1` | `"1"` | キーコードの値 0x0001（= `Trans`）として、**エラーなしで**読まれる |
| 記号 1 文字の `!` | `"!"` | 空（割り当てなし）として、**エラーなしで**読まれる |
| 記号のキー `[` `]` `-` など | `"["` | YAML の文法エラーになる |
| `yes` `no` `on` `off` | 引用符で囲む | 真偽値になる（validate が書き直し方とあわせて教えてくれます） |

`Command + Shift + [` のように、記号が文字列の途中にあるときは引用符なしでも書けます。
ただし `{ push: ..., ccw: ... }` のような 1 行のマッピングの中では、`[` `]` `,` などを含む値は引用符で囲みます。
数字と `!` の誤りは validate では見つからないので、書き込む前に `cornix status` の差分で確かめてください。

## 設定ファイルの検証

```bash
cornix validate
```

```
✗ Validation failed:
  Error: layers/1_symbol.yaml: mapping.left_hand.row0.tab: キーコード「Spce」を解釈できません: 「Spce」は不明なキーコードです
  Error: layers/1_symbol.yaml: mapping.left_hand.row1.capz: position_map の left_hand.row1 にないキーです（使えるキー: caps, A, S, D, F, G）
```

- 問題は止まらずに集め、「ファイル: 位置: 内容」で表示します（終了コード 1）。グループやファイルの形の誤りを直すと、さらに見つかることがあります。`status` / `apply` も同じ検査を先に行います
- 先にファイルの書き方（YAML の文法、項目、キーコード、キーの名前、番号の範囲）を、それが通ってから設定全体（件数の上限、番号・名前の重複、参照先、レイヤー番号）を検査します
- 件数の上限: レイヤー 10、マクロ 32、タップダンス 32、コンボ 32、コンボのトリガー 4 キー
- 警告（`⚠  Warning: …`）だけなら続行します
- 未使用のファイル（`index` のないもの）があれば、最後に `ℹ  Unused files (no index, not compiled): 件数` とその一覧を出します。未使用のファイルは書き方だけを検査し（参照先などは見ません）、問題は警告にします

## 名前を付ける（`rename`）

```bash
cornix rename
```

既定の名前（`Macro N`・`TapDance N`・`Combo N`・`Layer N`）のマクロ・タップダンス・コンボ・レイヤーを Claude が読んで、名前・説明・ファイル名を提案します。
1 件ずつ `Y`（承認）/ `n`（スキップ）/ `e`（編集）で選ぶと、バックアップ（`profiles/default.backup_<日時>/` など）を取ってからまとめて変え、
`Macro('旧名')` などの名前の参照も書き換えます（番号の参照 `Macro(3)` / `TD(2)` とファイル名の番号は変えません）。変更の前後で設定の値が変わっていないことを確かめ、違えば元に戻します。

`claude` がないときは、`ruby bin/rename_file --config-dir profiles/default ...` で手で名前を付けられます（使い方は `ruby bin/rename_file --help`）。

## スナップショットと元に戻す

キーボードを読んだとき・書き込む前・compile したときに、その状態を日時付きのスナップショットとして `<tmp>/snapshots/<日時>-<種類>/layout.vil`（`20261019-010203-pre-apply/layout.vil` など）に残します。スナップショットは上書きしません。
`<tmp>` は設定ごとの作業用ディレクトリで、`profiles/default/` なら `tmp/profiles/default/` です（`tmp/` は Git の管理外です）。

| 種類 | 残すとき |
|---|---|
| `read` | キーボードを読んだとき（`pull` / `init` / `status` / `apply` / `restore` / `device read` / `device diff`） |
| `build` | `compile` の出力（`status` / `apply` が compile したときも） |
| `backup` | `cornix device backup` |
| `pre-apply` | `apply` が書き込む直前 |
| `pre-restore` | `restore` が書き込む直前 |
| `legacy` | 前の版の `<tmp>/device_backups/` のバックアップ（読むだけ） |

`read` と `build` は種類ごとに新しい 50 件だけ残し、古いものは消します。ほかの種類は消すまで残ります。

```bash
cornix snapshots                             # スナップショットを新しい順に一覧する（日時・種類・パス）
cornix snapshots --kind pre-apply            # 種類で絞り込む
cornix restore                               # いちばん新しい pre-apply（直前の apply の前の状態）に戻す
cornix restore 20261019-010203-pre-restore   # 指定したスナップショットに戻す（名前でもパスでもよい）
```

- 戻す先との差分を表示し、確認してから書き込みます
- `restore` は書き込む前に今の状態を `pre-restore` のスナップショットに残します。restore を取り消すときは、そのスナップショットを `restore` に渡してください（引数なしでもう一度 `restore` すると、同じ `pre-apply` に戻ります）
- `pre-apply` のスナップショットがまだないときは、`restore` は前の版の `<tmp>/device_backups/` のいちばん新しいバックアップを使います
- compile の最新の出力は今までどおり `<tmp>/build/layout.vil`、`pull` が読んだものは `<tmp>/layout.vil` にも書きます。スナップショットの `layout.vil` は `cornix device diff` や `cornix decompile` にも渡せます
- `restore` はキーボードだけを戻します。設定ファイルは Git で戻してください

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

`config/` 以外を使うときは、`validate` / `pull` / `status` / `apply` / `restore` などの最初の行に「設定: profiles/default（.cornix.yml）」のように表示します。
1 つのリポジトリに複数の設定を置けます（例: `profiles/work/`、`profiles/game/`）。切り替えるには `.cornix.yml` を書き換えるか、`--profile` を付けます。

### `init` が作るもの

```bash
cornix init [DIR] [--profile NAME | --config DIR] [--from FILE] [--no-pull]
```

- `DIR`（既定は `--root` か、カレントディレクトリ）に、`--profile NAME` なら `profiles/NAME/`、`--config` ならその場所、どちらもなければ `profiles/default/` を作ります。名前に使えるのは英数字と `. _ -` です（先頭は英数字）
- 次からその設定が使われるように `.cornix.yml` を作ります。すでにあれば変えません
- `.cornix.yml` がなく中身のある `config/` がある場所では、使う設定が黙って変わらないよう、オプションなしの `cornix init` は何も作らずに止まります（`--profile NAME` か `--config DIR` を付けてください）
- このリポジトリの外に作るときは、`.gitignore` に `tmp/` と `.decompile.lock` の行を足します

このリポジトリの `.gitignore` は `/.cornix.yml` と `/profiles/` を Git の管理から外しています（手元だけの設定のため）。フォークやブランチで設定を管理するなら、この 2 行を消してください。

### 以前の `config/` を使っている場合

`.cornix.yml` がなければ、今までどおり `config/` が使われるので、何もしなくても動きます。`profiles/` に移すときは次のようにします。

```bash
mkdir -p profiles && mv config profiles/default
echo "profile: default" > .cornix.yml
cornix validate          # 「設定: profiles/default（.cornix.yml）」と表示されれば移せています
```

スナップショットの場所も `tmp/snapshots/` から `tmp/profiles/default/snapshots/` に（前の版のバックアップは `tmp/device_backups/` から `tmp/profiles/default/device_backups/` に）変わるので、今までのものを `restore` に使うときはコピーしてください。

### 利用の形

**A. フォークして使う（おすすめ）**

```bash
# GitHub でこのリポジトリをフォークしてから
git clone <自分のフォーク> cornix-layout && cd cornix-layout
cornix init --profile <自分の名前>
# .gitignore から /.cornix.yml と /profiles/ の行を消してから
git add .gitignore profiles .cornix.yml && git commit -m "設定を追加"
git push
```

本家は `profiles/` の中と `.cornix.yml` を変更しないので、本家の更新は GitHub の「Sync fork」か `git pull upstream main` で取り込めます。

**B. 設定だけを別のリポジトリに置く**

ツールを clone して `cornix` を PATH に通し、設定は別のディレクトリで管理します。

```bash
mkdir my-cornix && cd my-cornix && git init
cornix init                    # profiles/default/ と .cornix.yml を作り、.gitignore に tmp/ と .decompile.lock を足す
cornix status                  # このディレクトリ（かその下）で実行する
```

### サンプルの設定

| ブランチ | 設定 | 内容 |
|---|---|---|
| `cornix-default-keymap` | `profiles/cornix-default/` | Cornix の標準的なレイアウト |
| `authors-keymap` | `profiles/authors/` | 作者が実際に使っているキーマップ。名前参照・修飾キー表現・コンボなどの使用例 |

どちらも main の上に設定と `.cornix.yml` を載せたブランチです。手元の `.cornix.yml` とぶつからないよう、別のディレクトリで開くのがおすすめです。

```bash
git worktree add ../cornix-default-keymap cornix-default-keymap   # フォークにないときは upstream から fetch して upstream/cornix-default-keymap
cd ../cornix-default-keymap && cornix validate
```

## VS Code の画面で編集する

`editors/vscode/` に、設定ディレクトリ丸ごとを 1 画面で見せ、すべての設定ファイルを候補から選びながら編集できる VS Code 拡張があります。
Marketplace には出していないので、.vsix を作って手元で入れます（手順は [editors/vscode/README.md](editors/vscode/README.md)）。
拡張は `cornix serve`（実機の操作は `cornix serve --device`）とだけ話します。キーボードに書き込むのは、設定で許したうえで毎回確かめたときだけです（下の **実機**）。ターミナルの `status` / `apply` もこれまでどおり使えます。

アクティビティバーの Cornix のアイコンか、コマンド「Cornix: プロファイルを開く」で開きます。上半分にキーボードの図、下半分に編集の欄が並び、図のキーをクリックするとその欄へ移ります。

| ファイル | 画面でできること |
|---|---|
| `layers/` | キーとエンコーダ、注記、割り当てを消す、レイヤーの名前と説明 |
| `macros/` | 手順（追加・削除・上下に動かす）、tap / down / up のキー、`delay`、`text`、`preset`、`preset` を手順に展開 |
| `tap_dance/` | 4 つの動作とその注記、`tapping_term` |
| `combos/` | 同時に押すキー（4 つまで。図のキーから選べる）、出すキーとその注記 |
| `shortcuts.yaml` | 値、同梱のショートカットから足す |
| `settings/qmk_settings.yaml` | 各設定（説明と既定値付き） |
| `position_map.yaml` | キーの名前（位置の名前） |
| `metadata.yaml` | 読むだけで表示 |

- **キーの入力**: 名前・別名・QMK 名・同梱のショートカットの日本語ラベルとアプリ名で候補を引きます。前方一致・部分一致に当たらないときは、打った文字を順に含むもの（あいまい一致。`lbr` → `[`）も下に出します。当てはまり方が同じなら、そのプロファイルでよく使っているキーが上に来ます。候補の一覧のいちばん下の「同梱から選ぶ…」で、同梱のショートカットをアプリ → カテゴリ → ラベルの順に選んで `Shortcut('…')` を入れられます。欄の横の組み立て欄で、修飾キー式（`Shift + Command + P`）・`LT(2, Escape)`・Mod-Tap（`RSFT_T(Up)`）を組み立てられます。入れたその場で検証し、マウスを載せると何に解釈されるかを表示します
- **図**: 図の上の「位置の名前」のボタン（押すと固定、マウスを載せている間か Alt を押している間は一時）で、割り当ての代わりに位置の名前を紫で表示します。名前は `position_map.yaml` のもので、表示中にキーを押すとその場で変えられます。`Trans` のキーにはレイヤー 0 の同じ位置のキーを薄く表示します。矢印キーは `↑` `←` `→` `↓` で表示します。マクロには橙の `M`、自分のショートカットには `★`、同梱のショートカットにはアプリのアイコンが付きます。割り当てのない位置は `NoKey` と同じく、枠だけで中は空白です
- **コンボ**: 図の上のコンボの番号のボタンを押す（固定）かマウスを載せている（一時）間、そのコンボのトリガーのキーを今のレイヤーで強調します。押せないコンボ（トリガーのキーがすべてそろうレイヤーがないもの）には ⚠ が付きます。コンボの節の「図から選ぶ」で、図のキーを押してトリガーに足せます
- **レイヤーの欄**: 編集フォームの先頭の「レイヤー別 / キー別」でモードを切り替えます。キー別では、キーの位置ごとにファイルのあるレイヤーの割り当てを並べるので、あるキーが各レイヤーでどう割り当てられているかを比べながらその場で直せます。図で選んでいるレイヤーの行を強調し、「▽ と空欄を畳む」で `Trans` と書いていない行を隠せます
- **節**: レイヤー以外の節（マクロ・タップダンス・コンボ・ショートカット・QMK 設定）は最初は畳んであります（`▶` / `▼`）
- **割り当てを消す**: 欄の横の ✕ で YAML のその行を消します。割り当てのない位置は `NoKey` として書き込まれます（[レイヤー](#レイヤー)）
- **保存**: 変更は Cmd+S（Ctrl+S）まで未保存として持ち、元に戻すも効きます。保存では変えた値の部分だけを書き換え、コメントや並びを保ちます。開いている間に Claude などがファイルを変えたら、未保存の変更がなければ読み直し、あればどちらを残すか聞きます
- **追加**: レイヤーの並びの末尾の「＋」と、マクロ・タップダンス・コンボ・ショートカットの節の「追加」で、検索の欄・「新しく作る」・「未使用（N）」（`index` のない[未使用のファイル](#ファイル構成)）・（マクロとショートカットは）同梱から、の一覧を出します。新しいレイヤーには空いている番号と、選んだ名前を付けます（ほかのレイヤーと同じ名前でもかまいません）。同梱から作るマクロは、ラベルを名前にした `preset:` のマクロです
- **「…」メニュー**: 項目の見出し（とレイヤーの見出し）の「…」1 つに、状態に合う操作を出します:「番号を変える…」「未使用にする」「名前を変える」「ファイルを開く」「削除…」。ショートカットには番号がないので、名前の変更・ファイルを開く・削除だけです
- **未使用の項目と番号**: 「追加」の一覧で未使用の項目を選ぶと、末尾の番号（使っているいちばん大きい番号の次。上限なら空いている最小）で使い始め、その項目を選びます。番号が埋まっているときは、どれかを未使用にするまで選べません。「番号を変える…」ではすべての番号（今・使っている（名前付き）・空き）を並べ、空きを選ぶと移動、使っている番号を選ぶと入れ替えます。マクロとタップダンスでは番号の参照（`Macro(3)`・`M3`・`TD(2)` など）も追従させます。名前の参照と、`MO(1)` などのレイヤーの参照は書き換えません（番号の選択に書き添えます）。未使用の項目を使い始める・未使用にする・番号の変更・ショートカットの追加（同梱からも、名前を入れて足すのも）は、値の編集と同じく未保存の変更です。元に戻す・やり直しが効き、Cmd+S（Ctrl+S）で保存します。未使用にすると壊れる参照があるときは、先に確かめます
- **削除・名前の変更**: 項目とレイヤーの削除・名前の変更は「…」メニューから行います。これらと、新しいレイヤー・マクロ・タップダンス・コンボの作成は、確認のダイアログのあとすぐファイルに書きます（未保存の変更があれば先に保存を促します）。レイヤーの削除では、ダイアログに `MO(n)` などそのレイヤーを指すキーの数を出します。名前の変更は、すべてのファイルの `Macro('旧名')` などの参照とファイル名も書き換え、compile の結果が変わるときは止めます。削除では参照は書き換えず、ダイアログに参照の数を出し、参照している側にエラーを出します
- **手順に展開**: マクロの「手順に展開」は、`preset:` の行を同梱の定義の手順に置き換えます。確認のダイアログのあとすぐファイルに書き、compile の結果が変わるときは止めます
- **テキストエディタ**: 設定ファイルをテキストで開いたときも、同じ検証の結果を波線で表示します
- **読めない値**: ファイルに解析できないキーコード（`KC_FOOO` など）があっても編集画面はそのまま出し、その欄をエラーにします。警告などほかの検証の結果も一緒に出るので、フォームで直せます（項目の追加・削除・名前の変更と実機への反映は、直すまでできません）
- **実機**: 編集フォームの一番下の節「デバイス転送」で、保存済みのプロファイルを接続中のキーボードに書き込みます。`cornix device` と同じく macOS とブリッジが要ります（[必要なもの](#必要なもの)）
  - 「反映のプレビュー…」かコマンド「Cornix: 実機に反映…」で、保存済みのプロファイルを compile して（未保存の変更は先に保存します）実機を読み（Bluetooth で 10 秒ほど）、違いを編集画面に重ねたモーダルに出します。図では違うキーを橙の枠で囲み、レイヤーのタブに違いの件数を付け、「場所: 実機の値 → このプロファイルの値」の一覧を並べます。「確定」を押すまで何も書かず、「やめる」で閉じます。モーダルを出している間は編集画面を操作できません
  - プロファイルに検証のエラーがあるあいだは「反映のプレビュー…」を押せず、横に件数と「先にエラーを直して保存してください」を出します（実機を読む前に止めます）。節には保存済みのプロファイルの検証のエラーと警告の一覧を出し（「キーを表示」で編集フォームのそのレイヤーの欄へ移ります。マクロなどの項目と QMK 設定はその欄へ）、見出しにも件数を付けます。警告だけなら反映できます（モーダルにも警告を並べます）
  - 確定すると、実機をバックアップしてから書き、読み直して確かめます。プレビューのあとで設定ファイルが変わったときは押せません（そのときは「もう一度比べる」）
  - 書き込めるのは設定 `cornix.device.allowWrites` を有効にしたときだけです（既定は無効。プレビューはいつでもできます）。拡張は設定が有効のときだけ `cornix serve --device` を `--allow-writes` 付きで起動し、付いていないサーバーは書き込みを断ります
  - 戻したいときは、設定ファイルを元に戻す（Undo や git）か直してから、もう一度反映します。バックアップから戻すのはコマンドラインで行います（`cornix restore` / `cornix device restore`）

## MCP サーバーとして使う

`cornix mcp` で MCP（Model Context Protocol）サーバーを標準入出力で起動します。

- **Claude Code**: リポジトリ直下の `.mcp.json` に `cornix-device` として登録済みです。このディレクトリで Claude Code を開き、初回の承認で許可してください
- **その他のクライアント**（Claude Desktop など）: 次のように絶対パスで登録します。`ruby` が見つからない場合（mise / rbenv など）は `command` に Ruby の絶対パスを書きます

```json
{
  "mcpServers": {
    "cornix-device": {
      "command": "ruby",
      "args": ["/path/to/cornix-layout/bin/cornix", "mcp", "--root", "/path/to/my-cornix"]
    }
  }
}
```

`--root` には `.cornix.yml` のあるディレクトリ（このリポジトリで設定を管理しているならこのリポジトリ）を指定します。
設定を別のリポジトリに置いているときは、そのディレクトリで `claude mcp add cornix-device -- ruby /path/to/cornix-layout/bin/cornix mcp --root "$PWD"` を実行すると、Claude Code に登録できます。

| ツール | 書き込み | 内容 |
|---|---|---|
| `keyboard_info` | しない | キーボードの情報 |
| `read_keymap` | しない | 今の状態を layout.vil 形式で返す・保存する |
| `backup` / `list_backups` | しない | スナップショット（種類 `backup`）の保存 / スナップショットの一覧（`kind` で絞り込める） |
| `apply_layout` | `dry_run: false` のときだけ | .vil（既定は `cornix compile` の出力）を書き込む。既定は dry run で差分と `confirm_token` を返し、`dry_run: false` と `confirm_token` を付けたときだけ書き込む |
| `restore_backup` | `dry_run: false` のときだけ | スナップショット（既定は最新の `pre-apply`）に戻す。`apply_layout` と同じ二段階 |

各ツールの結果には、人が読む短い要約と、2 つ目として `cornix device … --json` と同じ形の JSON（`config` は入りません）が入ります。`keyboard_info` はその JSON だけを、`save_path` なしの `read_keymap` は layout.vil の中身だけを返します。

`apply_layout` が書くのは、最後に `cornix status` / `apply`（か `compile`）が書いた `<tmp>/build/layout.vil` です。YAML を変えたら、先に `cornix status` を実行してください。
確認したあとにキーボードやファイルが変わるとトークンが一致せず、書き込みは拒否されます。AI アシスタントに任せるときも、書き込む前に dry run の結果を見せてもらってください。

## 安全のための仕組み

Cornix のファームウェア（RMK 0.8 系）はロックや範囲の検査がほとんどないので（bootloader 移行や EEPROM リセットがロックなしで実行され、範囲外の書き込みでパニックします）、次のようにしています。

- **送るコマンドの許可リスト**: HID ブリッジは許可リストにあるコマンドしか送りません。bootloader 移行・EEPROM リセット・全消去・キーマップ一括書き込みは送れません（`tmp/cornix-hid --self-test` で確認できます）
- **範囲の検査**: キーは 1 つずつ書き込み、レイヤー・行・列・マクロの位置などを送る前にすべて検査します
- **書き込まないキー**: `QK_BOOT` などの boot 系キーコード（[data/dangerous_keycodes.yaml](data/dangerous_keycodes.yaml)）は書き込みません
- **書く前に検証・確認・バックアップ**: 設定に誤りがあれば止まり、差分を見せて確認を求め、書く直前の状態を保存します
- **差分だけを書いて確かめる**: 変わったところだけを書き込み、最後に読み直して一致を確かめます

Vial はマクロの保存時に 2 キーの長押し（アンロック）を求めますが、これは Vial アプリ側の動作で、ファームウェアは確認していません。このツールではアンロックは要りません。

## トラブルシューティング

### キーボードが見つからない

```
エラー: Cornix が見つかりません。Mac と Bluetooth（または USB）で接続されているか、スリープしていないか、別の機器に接続先が切り替わっていないかを確認してください
```

- キーを 1 回押してスリープを解除するか、Mac との接続を確かめてから再実行してください
- キーボードが別の機器（BT1 / BT2 など）に切り替わっていると、Mac からは見えません。Mac に接続しているチャンネルに切り替えてください
- 途中で接続が切れると「キーボードから応答がありません」で止まります。書き込み中だったときは、何件目まで書いたかとバックアップの場所を表示するので、つなぎ直して `cornix apply` をやり直すか、`cornix restore` で戻してください（どちらも差分だけを書きます）

### よくある検証エラー

| 表示 | 直し方 |
|---|---|
| `キーコード「Spce」を解釈できません` | 綴りを直す（`Space`）。候補が「もしかして」で表示されます |
| `position_map の left_hand.row1 にないキーです` | `position_map.yaml` にある名前を使う |
| `マクロ「Unknown」が見つかりません` | 参照する名前を、マクロのファイルの `name` に合わせる |
| `左右の修飾キーは混在できません` | 修飾キーを左右どちらかにそろえる |
| `row2, row3, thumb_keys がありません` | 各手のグループをすべて書く（中身は空でよい） |

## Vial を使う場合（compile / decompile）

キーボードへ直接書き込む代わりに、Vial（Web / GUI）の `layout.vil` で読み書きすることもできます。macOS 以外ではこの方法を使います。

```bash
cornix init --from ~/Downloads/layout.vil   # Vial の File > Export Layout で書き出した layout.vil から設定を作る
cornix compile                              # 検証してから <tmp>/build/layout.vil を書く（-o FILE で出力先を指定）
# Vial の File > Import Layout で <tmp>/build/layout.vil を読み込む
```

| コマンド | 内容 |
|---|---|
| `compile [-o FILE]` | 設定を検証して .vil を書く（既定は `<tmp>/build/layout.vil`）。`status` / `apply` も内部でこれを行う |
| `decompile [FILE]` | layout.vil を今の設定ディレクトリの YAML にする（既定は `<tmp>/layout.vil`）。設定がすでにあれば止まる（[`pull` が止まるとき](#pull-が止まるとき)と同じ） |
| `cleanup [-f]` | 設定ディレクトリと compile の出力を消す。init / decompile が作る `.decompile.lock` があると `-f`（と確認）が必要 |

decompile → compile で 16bit 値が元と一致するので、Vial で作った設定をそのまま移せます。

## 開発者向け

```bash
bundle install                              # テスト用の gem（RSpec）を入れる
LANG=ja_JP.UTF-8 bundle exec rspec          # すべてのテスト（キーボード不要）
```

- 設計: [docs/architecture.md](docs/architecture.md)（層と依存の向き・データの流れ・コード規約）、[docs/tasks.md](docs/tasks.md)（主なクラスの公開メソッド）。テストの構成は [spec/README.md](spec/README.md)
- 開発のルールは [.claude/CLAUDE.md](.claude/CLAUDE.md) にあります。README を変えるときは README.md（英語）と README.ja.md（日本語）を同じコミットで変えてください（`spec/docs/readme_sync_spec.rb` が構成を確かめます）
- 手元の layout.vil で decompile → compile が元に戻るかは次のように確かめます

```bash
rm -rf /tmp/cornix-roundtrip
cornix init /tmp/cornix-roundtrip --from ~/Downloads/layout.vil
cornix compile --root /tmp/cornix-roundtrip
ruby bin/diff_layouts ~/Downloads/layout.vil /tmp/cornix-roundtrip/tmp/profiles/default/build/layout.vil
# 期待結果: === ✓ FILES ARE IDENTICAL ===
```

## 注意

- このツールは Cornix の公式の製品ではなく、開発元とは関係ありません。ファームウェアの更新で通信の仕様が変わる可能性があります
- このツールの使用によって起きた問題について、作者は責任を負いません。大事な設定は `cornix device backup` などで残しておいてください
- ライセンス: [MIT License](LICENSE)。著作権表示と許諾文を残せば、自由に改変・再配布できます。無保証です
- 参考: [Vial Documentation](https://get.vial.today/)、[QMK Keycodes](https://docs.qmk.fm/keycodes_basic)
