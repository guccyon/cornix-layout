# バックエンドとのリクエストの約束（v0.1〜v0.4）

VS Code 拡張（以下「拡張」）と、プロファイルを読んで解釈するバックエンド（以下「サーバー」）の間の約束。
拡張はこの約束だけでサーバーと話し、`cornix` コマンドを直接叩かない（[ADR 003](adr.md)）。
今のサーバーは Ruby（`cornix` のサブコマンド）だが、将来は同梱の TypeScript 版（B 案、[roadmap.md](roadmap.md) の「将来の拡張」）に
差し替えられるように、約束には Ruby のクラス名や内部の形を出さない。

**状態: 決定（2026-10-19）。** 決めたことと理由は「[11. 決めたこと](#11-決めたこと)」。v0.2 で足すもの（2026-10-20 決定）は「[12. v0.2 で足すもの](#12-v02-で足すもの)」、
v0.3 で足すもの（2026-10-20 決定）は「[13. v0.3 で足すもの](#13-v03-で足すもの)」、v0.4 で足す実機の操作（2026-10-21 設計。実装はこれから）は「[14. v0.4 で足すもの](#14-v04-で足すもの)」。
今の約束の版（`protocolVersion`）は `"0.3"`。

起動・終了とプロファイルの一覧（`initialize`、`profile/list` など）のほかに、中身のメソッドとして次の 5 つを決める。

1. プロファイルを構造で読む（`profile/open`）
2. 候補を引く（`keycode/candidates`、`keycode/shortcutTree`）と、1 つの値の解釈（`keycode/inspect`）
3. 保存前の状態で検証する（`profile/validate`）
4. 変わった値だけを書き換える変更を返す（`profile/planEdits`、保存の知らせ `profile/saved`）
5. 外での変更の通知（`workspace/didChangeFiles` → `profile/didChange`）

これは v0.1 の約束の全部ではない。compile / validate / status のコマンドは v0.1 の後半で足す（[10. v0.1 のこの案に入れないもの](#10-v01-のこの案に入れないもの)）。

## 1. 通信

- **起動**: 拡張が `cornix serve` を子プロセスとして起動する（`cornix` の場所は設定 `cornix.path`）。
  `--root` はワークスペースのフォルダ。1 つのサーバーが同じワークスペースの複数のプロファイルを扱う
- **形式**: JSON-RPC 2.0。標準入出力に、LSP と同じ `Content-Length: <バイト数>\r\n\r\n<JSON>` の枠で 1 メッセージずつ流す
  （拡張は `vscode-jsonrpc` をそのまま使える）。JSON は UTF-8
- **標準出力は JSON-RPC 専用**。ログは標準エラー出力に書き、拡張は出力パネル「Cornix」に流す
- **順序**: サーバーはリクエストを届いた順に 1 つずつ処理する。`$/cancelRequest` は受け付けるが v0.1 では何もしない。
  そのため拡張は、打つたびに送る `keycode/candidates` を間引き（例: 50 ミリ秒）、新しい要求を送ったら古い要求の結果を捨てる
- **書き込み**: サーバーはファイルを書かない。保存は、サーバーが返した変更を拡張が当てて行う（[6. 保存](#6-保存)）
- **実機**: この約束にキーボードに触るメソッドはない（[ADR 014](adr.md)）

### ライフサイクル

```
拡張                                   サーバー
 │── initialize ──────────────────────▶│  約束の版と、できることを確かめる
 │◀───────────────────── result ───────│
 │── initialized（通知）──────────────▶│
 │── profile/list, profile/open ... ──▶│
 │── shutdown ────────────────────────▶│
 │◀───────────────────── result ───────│
 │── exit（通知）─────────────────────▶│  プロセスを終える
```

- `initialize` の前に来たリクエストには `-32002`（ServerNotInitialized）、`shutdown` の後に来たリクエストには `-32600`（InvalidRequest）を返す（LSP と同じ）
- サーバーが落ちたら、拡張は知らせを出して再起動のボタンを付ける（開いていたプロファイルは `profile/open` からやり直す）

## 2. 共通の型

TypeScript の書き方で示す。`?` は省略できる項目。

### 位置と範囲

```ts
// ファイルの中の位置。行も列も 0 始まり。列は UTF-16 のコード単位（LSP と同じ。日本語は 1 文字 1 単位）
type Position = { line: number; character: number };
type Range = { start: Position; end: Position };
```

### パスの基準

- `file`（Address、Diagnostic、`files` のキーなど）: **設定ディレクトリ**からの相対パス（`"layers/0_base.yml"`）
- `dir`（`profile/list`）と `workspace/didChangeFiles` の `path`: **ワークスペースのフォルダ**からの相対パス。ワークスペースの外は絶対パス

### Address（設定ファイルの中の値の場所）

画面の各項目と、検証の結果と、変更の宛先はすべて Address で指す。

```ts
type Address = {
  file: string;                 // 設定ディレクトリからの相対パス（"layers/0_base.yml"）
  path: (string | number)[];    // ファイルの中のキーの道筋（["mapping", "left_hand", "row0", "tab"]）
};
```

- `path` はファイルに書く形のキー。モデル内のパス（`layers[0]...`）は約束に出さない
- 注記付きの形（`{ key: <表記>, note: <注記> }`）でも、`path` は割り当ての場所（`tab`）で止める。
  `Storage::DiagnosticLocator` は注記付きのとき `.key` まで指すが、Address には `.key` を付けず、付け外しはサーバーが行う
- まだファイルに書かれていない場所（割り当てのない位置、ファイルにない QMK 設定）も指せる。そこへの変更は挿入になる（[6.3](#63-書き換えの決まり)）。
  指せるのは `profile/open` の結果に出てくる Address だけで、それ以外（ないファイル、position_map にない位置）は `-32602`（InvalidParams）

### FileVersion

```ts
type FileVersion = string | null;   // ディスク上のバイト列そのものの SHA-256（"sha256:" + 小文字の 16 進）。ファイルがなければ null
```

拡張とサーバーが同じ中身を見ているかを確かめるのに使う（mtime は使わない）。改行や BOM は正規化しない。
拡張は保存したあとのディスクのバイト列から同じ値を作る（BOM などでサーバーの読むバイト列とずれないように）。

### Diagnostic（検証の結果 1 件）

```ts
type Diagnostic = {
  severity: "error" | "warning";
  message: string;              // 利用者向けの日本語。validate の表示から「ファイル: キーの位置: 」を除いた文
  source: "structure" | "semantic";   // 構造検証（読み込み）か意味検証（Profile#diagnostics）か
  address?: Address;            // どの値の問題か。ファイルやディレクトリ全体の問題では省く
  file?: string;                // address がないときの、問題のあるファイル（ディレクトリの問題は "macros/"）
  range?: Range;                // 波線を引く範囲（値の部分）。位置が分からなければ省く
};
```

- 表記を解釈できない値（知らないキーの名前、定義のないマクロの名前 `Macro('Removed')` など）は、今の読み込みでは構造検証の問題になる。
  番号で指して定義がない（`Macro(20)`）・件数の上限・Cornix が対応していないキーなどは意味検証の問題
- 原因が別の項目にある問題（消したマクロへの参照など）は、参照している側の `address` に出す（[spec.md](spec.md) の「検証」）
- 構造の問題が 1 つでもあると、今の読み込み（`Storage::ConfigRepository#load`）は Profile を作らないので、意味検証の結果は出ない
- `range` は YAML のノードの位置（Psych のノードの開始・終了の行と列。列は文字単位）から求める。今の `DiagnosticLocator` は「ファイル: キーの位置」までなので、行と列を足す

### KeyValue（割り当て 1 つの解釈）

```ts
type KeyValue = {
  text: string;                 // ファイルに書いてある表記そのまま（"LT1(Space)"、"Shortcut('VS Code:基本操作:コマンドパレット')"）
  canonical: string;            // decompile の正規形（"LT1(Space)"、"Cmd" なら "LGui"）
  code: number | null;          // 16bit 値。capabilities.keycodeCode が false のサーバーでは null
  kind: KeyKind;
  origin?: "shortcut" | "presetShortcut" | "presetMacro";  // Shortcut(...) で書いたもの、preset: のマクロを指すもの
  display: KeyDisplay;
  icon?: string;                // アイコン ID（"simple-icons:figma"）。同梱のショートカットと preset: のマクロだけ
  note?: string;                // 注記（{ key:, note: } の note）
};

type KeyKind =
  | "basic" | "modified" | "layerAction" | "layerTap" | "layerMod" | "modTap" | "oneShotMod"
  | "macro" | "tapDance" | "quantum" | "noKey" | "transparent" | "raw";

type KeyDisplay = {
  label: string;                // 1 行で描くときの短い文字（"Space"、"⇧⌘P"、"Bracket Pair"、"TG L3"）。修飾キーは macOS の並び（⌃⌥⇧⌘）
  tap?: string;                 // 上の面の文字。2 役のキーのタップ側（"Space"）、レイヤー操作の操作名（"TG"）、LM の修飾キー（"⇧"）。MO は省く
  hold?: string;                // 下の帯の文字。2 役のキーのホールド側（"L1"、"⇧"）、レイヤー操作・LM のレイヤー（"L3"）
  actions?: TapDanceAction[];   // タップダンスの割り当てのある動作（図で窓に分けて描く）。定義のないもの・どの動作も NoKey なら省く
};

type TapDanceAction = {
  action: "tap" | "hold" | "doubleTap" | "tapHold";  // この順で並べ、NoKey の動作は省く
  label: string;                // その動作のキーの label（"Tab"、"L1"）
};
```

`kind` は `Domain::Keycode` の種類に対応する名前だが、約束としては文字列の列挙として固定し、Ruby のクラス名とは切り離す。
表示用の文字（`display`）もサーバーが作る（TypeScript 版も同じ `data/` から同じ文字を作る）。
レイヤーは名前があっても番号（`L3`）で描く（名前は任意で長くなりがちなので、図では番号にして名前は説明で見せる）。
レイヤー操作は LT の帯にそろえ、`hold` にレイヤー、`tap` に操作名を入れる（`MO(3)` は `{ label: "L3", hold: "L3" }`、`TG(3)` は `{ label: "TG L3", tap: "TG", hold: "L3" }`、
`LM(1, MOD_LSFT)` は `{ label: "L1 ⇧", tap: "⇧", hold: "L1" }`）。

### Change（画面での変更 1 つ）

```ts
type Change = {
  address: Address;
  value: string | number | boolean;   // キーは表記の文字列、QMK 設定は数値か真偽値
};
```

拡張は未保存の変更を Change の並びとして持つ（同じ Address は最後の値だけ）。
Change は「どのファイルの何行目」ではなく Address で指すので、外でファイルが変わっても当て直せる（[7. 外での変更](#7-外での変更)）。

## 3. メソッドの一覧

| メソッド | 向き | 種類 | 中身 |
|---|---|---|---|
| `initialize` | 拡張 → サーバー | リクエスト | 約束の版とできることの確認 |
| `initialized` | 拡張 → サーバー | 通知 | 準備ができた |
| `shutdown` / `exit` | 拡張 → サーバー | リクエスト / 通知 | 終わる |
| `profile/list` | 拡張 → サーバー | リクエスト | ワークスペースのプロファイルの一覧と既定 |
| `profile/open` | 拡張 → サーバー | リクエスト | プロファイルを構造で読む |
| `profile/close` | 拡張 → サーバー | 通知 | 開いたプロファイルを閉じる（params は `{ "profileId": "p1" }`。知らない id でも何もしない） |
| `keycode/candidates` | 拡張 → サーバー | リクエスト | キー入力欄の候補 |
| `keycode/shortcutTree` | 拡張 → サーバー | リクエスト | 同梱のショートカットの「アプリ → カテゴリ → ラベル」の木 |
| `keycode/inspect` | 拡張 → サーバー | リクエスト | 1 つの表記の解釈・説明・その欄だけの検証 |
| `profile/validate` | 拡張 → サーバー | リクエスト | 未保存の変更を当てた状態でプロファイル全体を検証 |
| `profile/planEdits` | 拡張 → サーバー | リクエスト | 未保存の変更をファイルの書き換え（範囲と文字）にする |
| `profile/saved` | 拡張 → サーバー | リクエスト | 書き換えを当てて保存した。新しい中身を読み直す |
| `workspace/didChangeFiles` | 拡張 → サーバー | 通知 | 設定ディレクトリのファイルが変わった |
| `profile/didChange` | サーバー → 拡張 | 通知 | 開いているプロファイルの中身が外で変わった |

## 4. ライフサイクルのメソッド

### `initialize`

```jsonc
// params
{ "protocolVersion": "0.2", "clientInfo": { "name": "cornix-vscode", "version": "0.2.0" } }
// result
{
  "protocolVersion": "0.2",
  "serverInfo": { "name": "cornix", "version": "1.0.0", "implementation": "ruby" },   // version は Cornix::VERSION（約束の版 protocolVersion とは別）
  "capabilities": {
    "semanticValidation": true,   // Profile#diagnostics に当たる意味検証をする
    "keycodeCode": true           // KeyValue.code（16bit 値）を返す
  }
}
```

- 版は `major.minor`。1.0 になるまでは `major.minor` 全体が一致しなければ、サーバーは `-32051`（[9. エラー](#9-エラー)）で断る。
  1.0 からは major が違えば断り、minor の違いは知らない項目を無視して続ける
- 拡張も、返った `protocolVersion` が自分の版と違えばつながない（v0.2 の拡張は v0.1 のサーバーを使わない。中身の画面が v0.1 のサーバーの返さない項目を前提にするため）。
  断られたとき・違う版が返ったときは、サーバーの版（`-32051` なら `data.supported`）と自分の版を比べて、
  サーバーのほうが古ければ「cornix を新しく」、新しければ「拡張を新しく」、分からなければ両方を挙げて知らせる
- 拡張は `capabilities` が false の機能を画面に出さない（意味検証がなければ、構造の検証の結果だけを出す）

### `shutdown` / `exit`

`shutdown` の result は `null`。そのあと `exit` の通知でサーバーは終わる。

## 5. プロファイルと候補のメソッド

### 5.1 `profile/list`

```jsonc
// params
{}
// result
{
  "profiles": [
    { "dir": "profiles/default", "name": "default" },
    { "dir": "profiles/ipad", "name": "ipad" },
    { "dir": "config", "name": "config" }
  ],
  "default": "profiles/default"
}
```

- プロファイルは `dir` で指す（`profile/open` の引数も `dir`）。`name` は表示用で、重なってもよい（拡張は重なるときだけ `dir` を添えて見せる）
- 並べるもの（この順。同じディレクトリは 1 回だけ）: `profiles/` の下のディレクトリ（名前の順。`--profile` に使える名前だけ）、
  `.cornix.yml` の `config:` が指すディレクトリ、後方互換の `config/`（中身があるとき）
- `default` はワークスペースのフォルダで `Application::Workspace.resolve`（`--root` 付き、オプションなし）が選ぶ設定ディレクトリ。
  環境変数 `CORNIX_CONFIG` は見ない（拡張を起動した環境によって既定が変わらないように）。
  そのディレクトリが一覧にないとき（ないとき、中身のない `config/` のとき）と、`.cornix.yml` が読めないときは `null`（拡張は一覧から選ばせる）。
  `.cornix.yml` の変更は v0.1 では知らせない（開くときに 1 回だけ使う）

### 5.2 `profile/open`

プロファイルを読み、画面に描くものをまとめて返す。

```jsonc
// params
{ "dir": "profiles/default" }
// result: ProfileSnapshot
{
  "profileId": "p1",         // 以降のリクエストで使う。profile/close まで有効
  "name": "default",
  "dir": "profiles/default",
  "status": "ok",            // "ok" | "invalid"（構造検証で読めなかった）
  "files": {                 // 読んだファイルとその中身の版。外での変更と保存のときの照合に使う
    "metadata.yaml": "sha256:9f2c…",
    "layers/0_base.yml": "sha256:41ab…",
    "settings/qmk_settings.yaml": "sha256:0d3e…"
  },
  "metadata": { "keyboard": "cornix", "version": 1, "vial_protocol": 6 },   // 読むだけで表示
  "positionMap": [
    { "hand": "left", "row": 0, "col": 0, "group": "row0", "symbol": "tab" }
  ],
  "layers": [
    {
      "index": 0, "name": "Base", "description": "Base layer …", "file": "layers/0_base.yml",
      "keys": [
        {
          "hand": "left", "row": 3, "col": 4,
          "address": { "file": "layers/0_base.yml", "path": ["mapping", "left_hand", "thumb_keys", "middle"] },
          "value": {
            "text": "LT1(Space)", "canonical": "LT1(Space)", "code": 16684, "kind": "layerTap",
            "display": { "label": "Space", "tap": "Space", "hold": "L1" }
          }
        },
        {
          "hand": "left", "row": 0, "col": 0,
          "address": { "file": "layers/0_base.yml", "path": ["mapping", "left_hand", "row0", "tab"] },
          "value": {
            "text": "TapDance('Tab Escape')", "canonical": "TapDance('Tab Escape')", "code": 22276, "kind": "tapDance",
            "display": { "label": "Tab Escape", "actions": [{ "action": "tap", "label": "Tab" }, { "action": "hold", "label": "Escape" }] }
          }
        }
      ],
      "encoders": {
        "left": {
          "push": { "address": { "file": "layers/0_base.yml", "path": ["mapping", "encoders", "left", "push"] },
                    "value": { "text": "Mute", "canonical": "Mute", "code": 168, "kind": "basic", "display": { "label": "Mute" } } },
          "ccw": { "...": "同じ形" },
          "cw": { "...": "同じ形" }
        },
        "right": { "...": "同じ形" }
      }
    }
  ],
  "settings": [
    {
      "group": "keyboard", "name": "tapping_term", "type": "integer", "value": 180,
      "default": null, "description": null,    // 説明と既定値は data/qmk_settings.yaml に足したら入る
      "address": { "file": "settings/qmk_settings.yaml", "path": ["keyboard", "tapping_term"] }
    }
  ],
  "references": {            // 候補やレイヤー名の表示に使う一覧
    "layers": [{ "index": 1, "name": "Symbols" }],
    "macros": [{ "index": 0, "name": "Bracket Pair", "icon": null }],
    "tapDances": [{ "index": 4, "name": "Tab Escape" }],
    "shortcuts": [{ "name": "前のタブへ", "text": "Command + Shift + [" }]
  },
  "diagnostics": []          // 保存済みのファイルの検証の結果（Diagnostic[]）
}
```

- `positionMap` と `keys` の位置は論理位置（[domain-model.md](../domain-model.md) の `KeyPosition` の hand / row / col。親指キーは row 3 の col 3〜5）。
  キーボード図の物理配置は拡張が持ち、この論理位置で組み合わせる（[ADR 009](adr.md)）
- `keys` は割り当てのない位置も含めて position_map のすべての位置を返す（`value` は `null`）。`address` はその位置を書くときの場所
- `settings` は `data/qmk_settings.yaml` のすべての設定を返す（ファイルにない設定は `value: null`）
- `status: "invalid"` のときは `files` と `diagnostics` だけを信じてよい（`layers` などは空）。
  拡張はエラーの一覧と、ファイルを開くボタンを出す（[11. 決めたこと](#11-決めたこと) の 6）
- マクロ・タップダンス・コンボ・ショートカットの中身の画面は v0.2。v0.1 では `references` の名前の一覧だけを返す

各項目の決まり（`null` になるものと、項目ごと省くもの）:

- `files`: 設定ディレクトリの設定ファイル（`metadata` `position_map` `settings/qmk_settings` `shortcuts` と、`layers/` `macros/` `tap_dance/` `combos/` の YAML）の版。
  版と読み込みには同じバイト列を使う。`settings/qmk_settings.yaml` はなくても `null` で入れる（QMK 設定の Address が指すファイルで、保存で作ることがあるため）。
  読んだ版はそのプロファイルの「知っている版」になる（前の版は置き換える）
- `metadata`: `metadata.yaml` の中身そのまま（読むだけで表示。`uid` は 2^53 を超える整数のことがあり、JavaScript の number では丸まる）
- レイヤーの `description` は書いていなければ `null`（空の文字列はそのまま `""`）。`file` はそのレイヤーのファイル
- `keys` は position_map の定義順（左手の row0〜row3・親指、右手の row0〜row3・親指）。`encoders` は `left` / `right` とも、`push` / `ccw` / `cw` もすべて必ずあり、
  `value` はファイルに書いていない操作（`push:` のように値を書いていないものも）では `null`（読み込みでは `NoKey` になるが、書いていないことを画面で分けられるように）
- KeyValue の `text` はファイルに書いてある表記（注記付きの形なら `key` の値）。`origin` `icon` `note` と KeyDisplay の `tap` `hold` `actions` は、値がなければ `null` にせず項目ごと省く。
  `origin` は `Shortcut(...)` で書いたもの（自分のショートカットなら `"shortcut"` でアイコンなし、同梱のものなら `"presetShortcut"` と元のアプリのアイコン）と、
  `preset:` のマクロを指すもの（`Macro(...)` でも番号でも `"presetMacro"` と元のアプリのアイコン）。`canonical` はそのプロファイルの名前参照を使った decompile の正規形
  （自分のショートカットと同じ値なら `Shortcut('名前')` になる）
- `settings` は `data/qmk_settings.yaml` の順。`value` は整数か真偽値（ファイルが 0 / 1 で書いていても `true` / `false`）、ファイルになければ `null`。
  `default` と `description` は `data/qmk_settings.yaml` に書いていなければ `null`。`address.path` は `[group, name]`。
  ただしファイルが旧 decompile の QSID の番号の形（`'7': 180`）で書いていて名前の形がなければ、その場所（`["7"]`）
- `references.macros` の `icon` は `preset:` のマクロの元のアプリのアイコン、ほかは `null`。`references.shortcuts` の `text` は `shortcuts.yaml` に書いた表記
- `diagnostics`（Diagnostic）: 構造検証の問題は、値の場所が分かれば `address`（注記付きの形でも `.key` を付けない）と `range`、
  ファイル全体の問題（YAML として読めないなど）は `file` だけ、どのファイルとも言えない問題（プロファイル全体の組み立ての問題）はどちらも省く。
  `shortcuts.yaml` の構造の問題は `file` だけにする（名前に `.` `[` `]` を含むと位置から道筋を正しく戻せないため）。
  意味検証の問題は、値の場所なら `address` と `range`、ファイル全体なら `file`、一覧全体（マクロの件数の上限など）なら `file` に `"macros/"` の形
- `status: "invalid"` のとき: `metadata` は `{}`、`positionMap` `layers` `settings` は `[]`、`references` の 4 つの一覧も `[]`
- `dir` が分からなければ `-32050`（`data: { "dir": … }`）、`dir` がなければ `-32602`

### 5.3 `keycode/candidates`

キー入力欄の候補。並び順はサーバーが決め、拡張はそのまま出す。

```jsonc
// params
{
  "profileId": "p1",
  "context": "layerKey",     // "layerKey" | "encoder"（v0.1）。v0.2 で "macroKey" "tapDanceAction" "comboTrigger" などを足す
  "query": "Cmd",            // 入力中の文字。空なら「上に出すもの」から並べる
  "limit": 50
}
// result（items は形の例で、一部だけ）
{
  "items": [
    { "insertText": "LGui", "label": "LGui", "detail": "Cmd · Command · KC_LGUI", "category": "modifier" },
    { "insertText": "MO(1)", "label": "MO(1)", "detail": "Symbols", "category": "layer" },
    {
      "insertText": "Shortcut('VS Code:基本操作:コマンドパレット')",
      "label": "コマンドパレット",
      "detail": "VS Code › 基本操作 · Shift + Command + P",
      "category": "presetShortcut",
      "icon": "material-icon-theme:vscode"
    },
    {
      "insertText": "Repeat", "label": "Repeat", "detail": "QK_REPEAT_KEY", "category": "special",
      "warning": "Cornix は Repeat Key に対応していません"
    }
  ],
  "typed": {                 // query をそのまま表記として読めたときの解釈（KeyValue）。読めなければ null
    "text": "Cmd", "canonical": "LGui", "code": 227, "kind": "basic", "display": { "label": "⌘" }
  },
  "truncated": true          // limit で切った
}
```

```ts
type CandidateCategory =
  | "basic" | "modifier" | "media" | "mouse" | "layer" | "macro" | "tapDance"
  | "shortcut" | "presetShortcut" | "special" | "raw";
```

- `insertText` は選んだときに入れる表記。マクロ・タップダンス・ショートカットは名前の形（`Macro('名前')`、`TapDance('名前')`、`Shortcut('名前')`）、
  それ以外は decompile の正規形（`QK_REPEAT_KEY` なら `Repeat`）
- 当てる文字・並べ方・除くものは [spec.md](spec.md) の「入力と補完」のとおり（正規の名前・別名・QMK 名・記号・ショートカットの日本語ラベルとアプリ名に部分一致、
  完全一致と前方一致を上に、`data/dangerous_keycodes.yaml` は出さない、`data/unsupported_keycodes.yaml` は `warning` にその理由を入れて下に）
- `raw`（`0x7E40`）は query が `0x` で始まるときだけ出す
- 修飾キー式（`Shift + Command + P`）は v0.1 では候補に出さず、打った文字を `typed` で解釈して見せる
- 「この入力ならこの候補」の共通テスト（[ADR 004](adr.md)）は、このメソッドの params と result の組をデータに書いたものにする（[8.2](#82-適合テスト)）
- `query` は省くと `""`、`limit` は省くと 50（1 未満は 1。上限は設けない）。知らない `context` は `-32602`（`data: { "field": "context" }`）
- 候補の `detail` `icon` `warning` は値がなければ項目ごと省く。`icon` は同梱のショートカットのアプリのアイコンと、`preset:` のマクロの元のアプリのアイコン
- 名前参照（マクロ・タップダンス・自分のショートカット・レイヤーの名前）は保存済みのプロファイルから取る。構造検証で読めないプロファイルでは、キーの表と同梱のショートカットだけを出す
- `typed` は query（前後の空白を除いて空なら `null`）を表記として読めたときの KeyValue（`text` は query そのまま）。読めなければ `null`

### 5.4 `keycode/shortcutTree`

同梱のショートカットを「アプリ → カテゴリ → ラベル」で辿るための木。中身はプロファイルによらないので、拡張は 1 回取ってとっておいてよい。

```jsonc
// params
{}
// result
{
  "apps": [
    {
      "name": "VS Code", "icon": "material-icon-theme:vscode",
      "categories": [
        {
          "name": "基本操作",
          "items": [
            { "label": "コマンドパレット", "insertText": "Shortcut('VS Code:基本操作:コマンドパレット')",
              "text": "Shift + Command + P", "macro": false },
            { "label": "キーボードショートカット", "insertText": "VS Code:基本操作:キーボードショートカット", "macro": true }
          ]
        }
      ]
    }
  ]
}
```

- `macro: true` は複数の手順の定義で、`macros/` の `preset:` でだけ使える（キー入力欄の候補には出さない）。
  `insertText` は `preset:` に書く名前で、`text` は省く
- アプリは `data/shortcuts/` のファイル名の順、カテゴリとラベルは定義の順（カテゴリの中では 1 シーケンスの定義のあとに複数の手順の定義）。
  アプリの `icon` はアイコンの表（`data/shortcut_icons.yaml`）になければ `null`（v0.1 の同梱のアプリはすべてある）。params は見ない（省いてもよい）

### 5.5 `keycode/inspect`

1 つの表記の解釈。入力欄の onchange の検証と、マウスを載せたときの説明に使う。

```jsonc
// params
{ "profileId": "p1", "context": "layerKey", "text": "Macro('Bracket Pair')" }
// result
{
  "value": {                 // KeyValue。読めなければ null
    "text": "Macro('Bracket Pair')", "canonical": "Macro('Bracket Pair')", "code": 30464, "kind": "macro",
    "display": { "label": "Bracket Pair" }
  },
  "diagnostics": [],         // この欄だけで分かる問題（読めない表記、参照先がない、未対応のキーなど。address は省く）
  "description": {           // 説明（マウスを載せたとき）
    "title": "マクロ Bracket Pair（M0）",
    "lines": ["角括弧ペア [] を挿入してカーソルを内側に配置", "tap: [ ] ←", "QMK: QK_MACRO_0（0x7700）"]
  }
}
```

- 参照先（マクロの名前など）は保存済みのプロファイルで判断する。v0.1 には名前を変える操作がないので未保存の変更は渡さない
  （名前の変更が入る v0.2 で `baseVersions` と `changes` を足す）
- 説明に出すもの: Shortcut の中身（`Shift + Command + P`）、マクロの手順、タップダンスの 4 つの動作（割り当てのあるものだけ。設定ファイルの description は動作の行と重なるので出さない）と tapping_term、レイヤー操作の行き先のレイヤー名、QMK のキーコード（16bit 値を添える）
- 読めない表記では `value` と `description` が `null` で、`diagnostics` に構造の error が 1 件（`source: "structure"`、message は読み込みのときと同じ文）
- 読めれば、`diagnostics` は意味検証の規則（参照先の定義がない、レイヤーの番号がレイヤー数を超える・定義されていない、Cornix が対応していないキー）でその値だけを確かめた結果。
  プロファイル全体の問題（件数の上限など）は混ぜない。保存済みのプロファイルが構造検証で読めないときは意味検証をしない（5.3 と同じく、キーの表と同梱のショートカットだけで読む）
- `description` は `{ title, lines }`。`lines` の最後はいつも QMK の keymap.c に書く名前と 16bit 値（`QMK: LT(1, KC_SPACE)（0x412C）`）。
  名前にできない値は 16bit 値だけ（`16bit 値: 0x5C00`）。v0.1 では Cornix の表（`data/keycodes.yaml`）にある値だけに名前を付け、
  表にない値（Raw）は QMK に名前があっても 16 進だけ（`0x7E40` は QMK の `QK_USER_0` だが `16bit 値: 0x7E40`）。
  ほかに `QK_MACRO_31` より後のマクロと、Vial GUI だけの名前 `USER32` 以降も 16 進だけ。
  名前の基準は最新の QMK（qmk_firmware の `data/constants/keycodes` の 0.0.9 時点）。値は vial-qmk と同じだが、vial-qmk や古い QMK では名前が違うものがある
  （`QK_MOUSE_CURSOR_UP` は古くは `KC_MS_UP`、`QK_UNDERGLOW_TOGGLE` は `RGB_TOG`）。
  名前は QMK の公式の表（https://docs.qmk.fm/keycodes ）の「Key」の列の長い名前（`KC_SPC` ではなく `KC_SPACE`、`KC_BSPACE` ではなく `KC_BACKSPACE`、
  `KC_TRNS` は `KC_TRANSPARENT`、`QK_BOOT` は `QK_BOOTLOADER`、`LSFT(KC_1)` は `KC_EXCLAIM`）。引数付きは
  修飾付き `LSFT(KC_P)` / `LSG(KC_P)` / `MEH(kc)` / `HYPR(kc)`（QMK に名前のない右の Ctrl+Shift+Alt と右の 4 つは `RCTL(RSFT(RALT(kc)))` の入れ子）、
  Mod-Tap `LGUI_T(kc)` / `MEH_T(kc)` / `HYPR_T(kc)`（名前のない組は `MT(MOD_RCTL | MOD_RSFT | MOD_RALT, kc)`）、`LT(1, KC_SPACE)`、`LM(1, MOD_LSFT)`、
  `MO(1)` などのレイヤー操作、`OSM(MOD_LCTL | MOD_LSFT)`（左の 3 つ・4 つは `MOD_MEH` / `MOD_HYPR`）、`TD(4)`、マクロは `QK_MACRO_0`。title は、ショートカットは「ショートカット 名前」（同梱は「同梱のショートカット 名前」）、
  マクロは「マクロ 名前（M0）」、タップダンスは「タップダンス 名前（TD(4)）」、そのほかは正規形。定義のないマクロ・タップダンスは lines に「定義されていません」
- 知らない `context` は `-32602`（`data: { "field": "context" }`）。v0.1 では `context` による解釈の違いはない

### 5.6 `profile/validate`

未保存の変更を当てた状態で、プロファイル全体を検証する（今の `cornix validate` は保存済みのファイルを読むので、その前の状態を検証する入口）。

```jsonc
// params
{
  "profileId": "p1",
  "baseVersions": { "layers/0_base.yml": "sha256:41ab…" },   // 変更を作ったときのファイルの版（変更のあるファイルだけ）
  "changes": [
    { "address": { "file": "layers/0_base.yml", "path": ["mapping", "left_hand", "row0", "tab"] }, "value": "Macro(20)" }
  ]
}
// result
{
  "diagnostics": [
    {
      "severity": "error", "source": "semantic",
      "message": "マクロ M20 が定義されていません",
      "address": { "file": "layers/0_base.yml", "path": ["mapping", "left_hand", "row0", "tab"] },
      "range": { "start": { "line": 7, "character": 11 }, "end": { "line": 7, "character": 20 } }
    }
  ]
}
```

- サーバーは [6.3](#63-書き換えの決まり) と同じ書き換えをメモリの上で当て、構造検証と意味検証を行う。ファイルは書かない
- 構造の問題（`Macro('Removed')` のような読めない表記など）が 1 つでもあれば、意味検証は行わず構造の問題だけを返す
- `range` は変更を当てたあとの中身での位置（保存すればそのまま波線に使える）
- `baseVersions` が今のファイルと違えば `-32060`（版の食い違い）

決めたこと（実装して決めた細部。[6.1](#61-profileplanedits) も同じ）:

- `baseVersions` と `changes` は省ける（`{}` と `[]`）。変更がなければ保存済みの中身の検証の結果（`profile/open` の `diagnostics` と同じ）を返す
- `baseVersions` は、サーバーがいま読んだディスクの版と比べる（`profile/open` で覚えた「知っている版」ではない）。
  値は版の文字列か `null`（ファイルがない）で、それ以外は `-32602`（`data: { "field": "baseVersions.<file>" }`）。
  設定ファイルでないファイルの今の版は `null` として比べる
- 変更のあるファイルはすべて `baseVersions` に入れる（まだない `settings/qmk_settings.yaml` は `null`）。なければ `-32602`（`data: { "field": "baseVersions" }`）
- 確かめる順: params の形（値が小数や `null`、`path` の要素の型、`baseVersions` の値の型など。`-32602`）→ 版の食い違い（`-32060`）→
  Change の宛先・値の型・`baseVersions` の抜け（`-32602`）→ 書き換え（`-32061`）。
  `-32060` の `data.files` は食い違ったファイルだけの今の版（ないファイルは `null`）
- Change の宛先は `profile/open` の結果に出てくる Address だけ（レイヤーの `keys` と `encoders` の `address`、`settings` の `address`）。
  それ以外は `-32602`（`data: { "field": "changes[i].address" }`）。`status: "invalid"` のプロファイルには宛先がない
- 値の型: キーは文字列。QMK 設定は `data/qmk_settings.yaml` の型に直し、整数の設定は整数、真偽値の設定は `true` / `false`（`0` / `1` も受け付ける）。
  合わなければ `-32602`（`data: { "field": "changes[i].value" }`）。整数の範囲（幅）はここでは見ず、超えれば構造の error の Diagnostic になる
- 同じ Address が何度も出てきたら、並びの順に当てる（最後の値になる）
- 値の部分だけでは書き換えられない Change は、`profile/planEdits` と同じく `-32061`（保存できない変更だと早く分かるように）

## 6. 保存

### 6.1 `profile/planEdits`

未保存の変更を、ファイルの書き換え（範囲と文字）にして返す。

```jsonc
// params
{ "profileId": "p1", "baseVersions": { "layers/0_base.yml": "sha256:41ab…" }, "changes": [ /* Change[] */ ] }
// result
{
  "files": [
    {
      "file": "layers/0_base.yml",
      "baseVersion": "sha256:41ab…",
      "create": false,                 // ファイルを新しく作るとき true（settings/qmk_settings.yaml がないときだけ）
      "edits": [
        { "range": { "start": { "line": 7, "character": 11 }, "end": { "line": 7, "character": 33 } }, "newText": "Escape" }
      ]
    }
  ],
  "diagnostics": []                    // 書き換えたあとの検証の結果（validate と同じ）
}
```

`baseVersions` が今のファイルと違えば `-32060`、値の部分だけでは書き換えられなければ `-32061`。

- params の決まりと確かめる順は [5.6](#56-profilevalidate) と同じ
- `files` は書き換えのあるファイルだけで、`changes` に初めて出てきた順。値が今と同じ Change だけのファイルは入れない（全部同じなら `files: []`）
- `baseVersion` はそのファイルの今の版（`create: true` なら `null`）
- `edits` の範囲はすべて今のファイル（`baseVersion` の中身）での位置で、重ならない。拡張はファイルごとにすべてを 1 つの `WorkspaceEdit` で当てる。
  同じファイルへの変更が 2 つ以上なら、サーバーは 1 つずつ当てて読み直し、元の中身との行の差分にまとめる。
  そのため隣り合う行の変更は複数行にまたがる 1 つの書き換えになることがある（変わる文字は値の部分だけ）
- `create: true` のときの `edits` は、空のファイルの先頭（0 行 0 列）に中身をすべて入れる 1 つの書き換え。拡張はファイルを作ってから当てる
- 真偽値の QMK 設定は、ファイルが `0` / `1` で書いていれば `0` / `1` で書く（`true` と `1` は同じ値として、書き換えを作らない）
- `-32061` の `data.address` はその Change の Address、`message` は「値の部分だけでは書き換えられません（理由）: 道筋。テキストで直してください」。
  アンカーとエイリアスは今の読み込みが構造の問題にする（プロファイルが `invalid` になり宛先がない）ので、`"anchor"` は v0.1 では返らない

### 6.2 保存の流れ

1. 拡張は、書き換える対象のファイルがテキストエディタで未保存（dirty）のまま開いていれば保存を止め、「テキストの変更を先に保存するか戻してください」と知らせる
2. `profile/planEdits` を呼ぶ。`diagnostics` に構造の error があれば保存しない（保存するとプロファイル全体が `invalid` になり、画面で直せなくなるため）。
   意味検証の error と warning は保存を止めない
3. 拡張は当てる前に、対象のファイルのディスクのバイト列の版（[2.](#fileversion) の FileVersion）が `files` の `baseVersion` と同じか確かめる
   （`create: true` ならファイルがないこと）。違えば（2 のあとに外で変わった）当てずに、[7.3](#73-拡張の扱い) の扱いをしてから 2 からやり直す
   （サーバーは planEdits の時点のディスクと比べるだけなので、古い位置の書き換えが新しい中身に当たって外の変更を壊さないように）。
   同じなら `files` を 1 つの `WorkspaceEdit` にして `vscode.workspace.applyEdit` で当て、対象の `TextDocument` を `save()` する。
   当てるのに失敗したら、未保存の変更はそのまま残す（サーバーは何も覚えていないので、やり直しは 2 から）
4. 保存が終わったら、拡張は保存したファイルの中身の版を `profile/saved` で知らせる。保存時の整形（`files.insertFinalNewline` など）で中身が
   書き換えの結果と違っていても、保存したあとの中身の版を送る
5. 3 から 4 の間、拡張は対象のファイルについての監視の知らせ（`workspace/didChangeFiles`）を送らずに溜め、4 のあとで送る

### 6.3 書き換えの決まり

[ADR 006](adr.md) のとおり、値の部分だけを書き換える。

- 値の部分（スカラーの範囲）だけを置き換える。キー・字下げ・コメント・ほかの行・フロー表記（`{ tab: Escape, Q: Q }`）の並びは変えない
- 値が今のファイルの値と同じ（表記の文字が同じで、読んだときの型も同じ。`"180"` と `180` は違う値）なら書き換えを作らない
- 引用符はサーバーが決める（`","` `"-"` のように YAML で引用符が要るものだけ囲む）。もとが引用符付きならその引用符を保ち、
  新しい値に同じ引用符が含まれるときはもう一方の引用符にする（`Storage::ConfigEditor#quoted` と同じ）
- 注記付きの形は `key` の値だけを置き換え、`note` は残す
- まだ書かれていないレイヤーのキーは、同じグループ（`row0` など）の中の position_map の順の場所に `symbol: 値` の行を足す（ブロック形式のとき）。
  グループの見出し（`row2:`）が値なしで書かれていれば、その下に字下げして足す。グループの見出しや `mapping:` ごとないときも、position_map の順に見出しを足す
- ファイルにない QMK 設定は、`group`（`keyboard:` / `vial:`）の下の、`data/qmk_settings.yaml` の順の場所に足す。group の見出しがなければ足す。
  `settings/qmk_settings.yaml` がなければ `create: true` で作る。ほかのファイルは作らない
- 局所的に書き換えられないとき（複数行の値、アンカーとエイリアス、フロー表記の中への挿入など）は、そのファイルを作り直さずに
  `-32061`（書き換えられない）を返す（[11. 決めたこと](#11-決めたこと) の 5）

### 6.4 `profile/saved`

```jsonc
// params
{ "profileId": "p1", "files": { "layers/0_base.yml": "sha256:77c0…" } }   // 保存したファイルと、保存したあとの中身の版
// result: ProfileSnapshot（profile/open の result と同じ形）
```

サーバーは知らされたファイルを読み直し、その版を「知っている版」にして、新しい ProfileSnapshot を返す。
読み直した中身の版が知らされた版と違えば（保存の直後にさらに外で変わったとき）、読み直した版を知っている版にし、`profile/didChange` を送る。
拡張は返された snapshot で描き直し、未保存の変更を空にする（以降の `baseVersions` は snapshot の `files` から取る）。

- `files` は要る（`{ file: 版 | null }`。なければ `-32602`、値が文字列でも `null` でもなければ `data: { "field": "files.<file>" }`）。
  設定ファイルでないもの（知っている版にも読み直した版にもないファイル）は見ない
- サーバーは設定ディレクトリ全体を読み直す。「知っている版に知らされた版を重ねたもの」と読み直した版を比べ、違うファイルがあれば
  `profile/didChange` を送る（保存の直後にさらに外で変わったファイルと、知らされていないファイルの外での変更。消えたファイルは `null`）
- `profile/didChange` は `profile/saved` の応答の**前に**届く。その `snapshot` は応答の result と同じもの（拡張は応答の snapshot で描けばよい）

## 7. 外での変更

### 7.1 `workspace/didChangeFiles`（拡張 → サーバー、通知）

拡張は `vscode.workspace.createFileSystemWatcher` で開いているプロファイルの設定ディレクトリを見張り、変わったファイルを知らせる
（LSP の `workspace/didChangeWatchedFiles` と同じ役目。Ruby 側に監視の gem を足さないため）。

```jsonc
{ "changes": [ { "path": "profiles/default/layers/0_base.yml", "type": "changed" } ] }   // path はワークスペースからの相対。type: "created" | "changed" | "deleted"
```

### 7.2 `profile/didChange`（サーバー → 拡張、通知）

サーバーは知らされたファイルを読み直し、中身の版が知っている版（`profile/open` か `profile/saved` で覚えた版）と違うときだけ、
そのプロファイルについて知らせる（ファイルが足されたとき・消えたときも知らせる）。

```jsonc
{
  "profileId": "p1",
  "files": { "layers/0_base.yml": "sha256:e1d4…" },   // 変わったファイルと新しい版（消えたファイルは null）
  "snapshot": { /* ProfileSnapshot（profile/open の result と同じ形） */ }
}
```

決めたこと（7.1・7.2）:

- `path` はワークスペースのフォルダからの相対パスか絶対パス。開いているプロファイルの設定ディレクトリそのもの・その中・その親
  （`profiles/` ごと消えた・名前が変わったとき。VS Code の見張りはいちばん上の 1 件しか出さないことがある）を指すものだけを見る。
  ディレクトリを指してもよい（`layers/` ごと消えたときなど）。`type` の値で扱いを変えない（どれでも読み直して比べる）。
  設定ディレクトリが消えたら、`files` はすべて `null`、`snapshot` は `status: "invalid"`（どのファイルとも言えない構造の問題 1 件）
- 見るプロファイルごとに設定ファイルの版を読み、知っている版と違うときだけ読み直して `profile/didChange` を送る。
  `files` は知っている版と違う設定ファイルすべて（知らせの `path` に入っていないものも。足されたファイルは新しい版、消えたファイルは `null`）。
  送ったときの版が新しい知っている版になる（同じ知らせをもう一度受けても送らない）。設定ファイルでないファイルの変更は知らせない
- 同じ設定ディレクトリを 2 つの `profileId` で開いていれば、それぞれに送る
- params の形が違えば知らせ全体を捨てる（通知なのでログに書くだけ）。`type` が `"created"` `"changed"` `"deleted"` のどれでもないときも同じ
- 適合テスト（[8.2](#82-適合テスト)）のデータは、途中でファイルを書き換える手順を持たないので、送らない場合だけを書いている。
  送る場合は `spec/interface/editor_server/handlers/write_handlers_spec.rb` で確かめる

### 7.3 拡張の扱い

[ADR 007](adr.md) のとおり。

- 未保存の変更がなければ、`snapshot` で黙って描き直す
- あれば、どちらを残すか聞く。「外の変更を残す」なら未保存の変更を捨てて `snapshot` で描き直す
- 「画面の変更を残す」なら、Change ごとに次のように当て直し、`baseVersions` を `snapshot.files` の版にする
  - 新しい snapshot に同じ Address があり、外の変更の前後でその値（キーは `value.text`、QMK 設定は `value`）が変わっていなければ、そのまま当て直す
  - 同じ Address の値が外でも変わっていれば、その Change の値と外の値を並べて、どちらにするか項目ごとに選ばせる。
    当て直した値が新しい値と同じになった Change は捨てる
  - 新しい snapshot に同じ Address がなければ（ファイル名が変わった、ファイルが消えた）、その Change は当て直せないものとして見せ、捨てるか選ばせる。
    v0.1 ではファイル名の変更を追わない

## 8. 差し替えとテスト

### 8.1 TypeScript 版に差し替えるときの決まり

- 約束に出す名前（`kind`、`category`、`context`、メソッド名）は文字列の列挙で、Ruby のクラス名や定数名と結び付けない
- 候補・表示の文字・説明は `data/*.yaml` から作る（[ADR 004](adr.md)）。TypeScript 版も同じ `data/` を読む
  - `MO(n)` など関数形式の一覧は `KeycodeCodec` の定数にあるので、B 案の前に `data/` へ出す（[roadmap.md](roadmap.md)）
  - 候補の `category` の分け方（`modifier` / `media` / `mouse` など）も今の `data/keycodes.yaml` にはない（分類は special / basic / shifted / quantum だけ）。
    `keycodes.yaml` に分類を足すか別のファイルにして、データに持つ（[roadmap.md](roadmap.md) の v0.1 の進め方の 4 で決める）
- B 案では compile を使う検証はしない（[roadmap.md](roadmap.md)）。意味検証（参照先・件数の上限など）も今は Ruby にしかないので、
  TypeScript 版は `capabilities.semanticValidation: false` を想定する（作るときに見直す）。そのとき `profile/validate` は構造の問題だけを返す
- 拡張は `initialize` の `capabilities` だけを見て振る舞いを変え、`serverInfo.implementation` で分岐しない

### 8.2 適合テスト

約束のテストは「リクエストと期待する応答」の組をデータで書き（置き場所の案: `spec/fixtures/protocol/`）、
Ruby の RSpec と、将来の TypeScript の vitest の両方から同じデータを読んで確かめる。
`keycode/candidates` の「この入力ならこの候補」もここに書く。応答の比べ方は、順序に意味のある配列（候補の並び）は順序ごと、
それ以外の Hash は書いた項目だけを比べる（版の文字列などは比べない）。

データは `spec/fixtures/protocol/<メソッド>/<名前>.json`（`<メソッド>` は `profile_list` のように `/` を `_` にしたもの。
ライフサイクルと枠・形の約束は `lifecycle/`）に 1 件ずつ置く。形は次のとおり（`request` か `raw` のどちらか一方が要り、ほかは省ける）。

```jsonc
{
  "description": "何を確かめるか（省けばファイル名）",
  "setup": {
    "profile": "test_config",          // spec/fixtures/<名前> をワークスペースの profiles/default に置き、開いておく（profileId は "p1"）
    "open": false,                     // profile を置くだけで開かない（profile/open 自体を確かめるとき）
    "profiles": { "profiles/ipad": "test_config", "config": null },   // ほかの設定ディレクトリ（null なら空のディレクトリ。profile と重ねない）
    "files": { ".cornix.yml": "profile: ipad\n", "profiles/default/layers/5_empty.yml": null },   // ワークスペースに書くファイル（ワークスペースからの相対パス。null なら消す）
    "initialize": false,               // initialize（protocolVersion "0.2"）と initialized を先に送らない
    "before": [{ "id": "b1", "method": "shutdown" }]  // request の前に送るメッセージ（応答は確かめない）
  },
  "request": { "id": 1, "method": "profile/list", "params": {} },   // jsonrpc は省くと "2.0"。"jsonrpc": null なら項目ごと外す。id がなければ通知
  "raw": "{oops",                      // request の代わりに、本文の文字列をそのまま枠に入れて送る（JSON でない本文・null・配列など）
  "response": { "id": 1, "result": { "default": "profiles/default" } },   // 応答。書かなければ「応答がない」ことを確かめる
  "notifications": [{ "method": "profile/didChange", "params": { "profileId": "p1" } }]   // サーバーからの通知（書けば確かめる）
}
```

- 送る順: `initialize` と `initialized`（`setup.initialize: false` でなければ）、`setup.profile` を開くこと、`before`、`request`（か `raw`）。
  `setup.profile` は、`profile/open` を受けるサーバーではそのリクエストで開く
- 確かめる応答は `request` の id のもの（`raw` と通知では、setup と before のほかで最初の応答）。setup と before のほかに応答があれば誤り
- `response` の比べ方: Hash は書いた項目だけ、配列は順序と長さごと、ほかの値（`null` を含む）は等しいこと。`notifications` も同じ比べ方で、届いた順に並べた配列と比べる

### 8.3 Ruby 側の置き場所（案）

[architecture.md](../architecture.md) の層と依存の向きを守る（Interface は Application だけを参照する）。

| 層 | 置くもの |
|---|---|
| Interface | `Interface::EditorServer`（枠の読み書き、JSON-RPC の振り分け、エラーの code への変換。`Interface::Mcp` の標準入出力の扱いを参考に）と `cornix serve` のコマンド。Application の結果を JSON にするだけで、`Domain::Keycode` などには触らない |
| Application | ユースケース（プロファイルを読む、候補を引く、表記を解釈する、変更を当てて検証する、書き換えを作る、保存を受けて読み直す）。応答の形（KeyValue や ProfileSnapshot の Hash）は Application の結果オブジェクトの `to_h` が作る |
| Mapping | 候補の表と並べ方、表示の文字（`data/*.yaml` から） |
| Storage | YAML のノードの位置（行と列）、値の部分だけの書き換え（`ConfigEditor#update_fields` の考え方を入れ子の値に広げる。ただし「ファイル全体を書き直す」逃げ道は使わない）、ファイルの中身を差し替えて読む口（保存前の検証用） |

## 9. エラー

JSON-RPC のエラーで返す。`message` は利用者に見せてよい日本語。`data` に機械向けの中身を入れる。
独自の code は、LSP が使っている範囲（-32001〜-32003、-32800〜-32803）と重ならない -32050 台・-32060 台に置く。

| code | 名前 | いつ | data |
|---|---|---|---|
| -32700 | ParseError | JSON として読めない（id は `null`） | — |
| -32600 | InvalidRequest | JSON-RPC の形でない（本文がオブジェクトでない・`jsonrpc: "2.0"` がない・id が文字列か整数でない・method も result / error もない）、通知で送るメソッドに id を付けた、2 回目の `initialize`、`shutdown` の後のリクエスト | — |
| -32601 | MethodNotFound | 知らないメソッド（`$/` で始まるリクエストも。`$/` で始まる通知と知らない通知は何もしない） | — |
| -32602 | InvalidParams | params の形が違う、Address が指せない（[2. の Address](#address設定ファイルの中の値の場所)） | `{ "field": "changes[0].address" }` |
| -32603 | InternalError | サーバーの不具合、検証の結果にならない `Cornix::Error`（message にその文を入れる） | — |
| -32002 | ServerNotInitialized | `initialize` の前のリクエスト（LSP と同じ code） | — |
| -32050 | ProfileNotFound | `dir` や `profileId` が分からない | `{ "dir": "profiles/ipad" }` か `{ "profileId": "p9" }` |
| -32051 | ProtocolVersionMismatch | 約束の版が合わない（[4.](#initialize)） | `{ "supported": ["0.2"] }` |
| -32052 | NotSupported | capabilities にない機能を呼んだ（v0.1 では使わない。TypeScript 版が持たないコマンドを足すとき用） | `{ "capability": "…" }` |
| -32060 | VersionConflict | `baseVersions` が今のファイルと違う | `{ "files": { "layers/0_base.yml": "sha256:e1d4…" } }`（今の版） |
| -32061 | EditNotLocal | 値の部分だけでは書き換えられない | `{ "address": { … }, "reason": "multiline" }`（reason: `"multiline"` \| `"anchor"` \| `"flowInsert"`） |

- プロファイルが構造検証で読めないこと・値が読めないことはエラーにしない。`status: "invalid"` や `diagnostics` で返す
- リクエストで送るメソッドを通知で送られたら、実行せずに捨てる（応答を返せないので、ログに書くだけ）。通知の処理の失敗もログに書くだけ

## 10. v0.1 のこの案に入れないもの

- compile / validate / status をエディタから実行するコマンド（v0.1 の後半で `command/compile` などとして足す。status は読むだけ）
- マクロ・タップダンス・コンボ・ショートカットの中身の画面と、その `context`（v0.2。[12.2](#122-profileopen-に足すもの)・[12.4](#124-中身の画面の-context)）
- 項目の追加・削除・名前の変更（v0.2。[12.5](#125-profileplanitemedit)）
- 注記の編集（v0.2。Address ではなく Change の `field: "note"` で指す。[12.3](#123-change-に足すもの)）
- 実機への書き込み（入れない。[ADR 014](adr.md)）

## 11. 決めたこと

2026-10-19 にすべて次のとおり決めた（括弧の中は退けた案）。

1. **枠の形**: LSP と同じ `Content-Length`。`vscode-jsonrpc` がそのまま使え、将来の LSP の入口とも共通（MCP と同じ 1 行 1 メッセージ）
2. **サブコマンドの名前**: `cornix serve`（`cornix editor-server`、`cornix rpc`）
3. **ファイルを書くのは誰か**: サーバーは書き換えを返すだけで、拡張が `WorkspaceEdit` で当てて保存する。テキストで同じファイルを開いていてもずれず、サーバーを差し替えても書き込みの扱いが変わらない（サーバーが書く）
4. **ファイルの見張り**: 拡張が見張ってサーバーに知らせる。Ruby に gem が要らず、LSP と同じ（サーバーが見張る）
5. **値の部分だけでは書き換えられないとき**: 書かずにエラーにする。コメントを壊さないことを優先し、画面には「テキストで直してください」とファイルを開くボタンを出す（そのファイルだけ作り直す）
6. **構造検証で読めないプロファイルを開いたとき**: エラーの一覧だけを出す。Claude が書きかけのときは、直れば `profile/didChange` で描き直る（読めたファイルだけを描く）。
   今の読み込みはキー 1 つの読めない表記でも全体を止めるので、外で 1 か所書き間違えると画面では直せない。画面から構造の error を作って保存することは止める（[6.2](#62-保存の流れ)）
7. **割り当てを消す操作**: v0.1 では入れず、`NoKey`（KC_NO）を選んでもらう。行の削除は v0.2 の項目の削除と一緒に決める（空の値にする、行を消す）。v0.2 では Change の `op: "remove"`（[12.3](#123-change-に足すもの)）
8. **候補を絞る場所**: 打つたびにサーバーに聞く。並べ方がサーバー 1 か所に集まり、適合テストで両方の実装を縛れる（最初に全部もらって画面で絞る）。
   これはサーバーを別のプロセスに置く今の作り（LSP と同じ形）での決め。将来サーバーを不要にする（拡張だけで動かす）ときは、候補のデータと絞り込みのロジックを拡張の側に持つ
9. **画面の作り**: プロファイルを 1 つの仮想ドキュメント（`cornix-profile:` のスキーム）に見立て、カスタムエディタ（`CustomEditorProvider`）に乗せる。
   dirty の印・Ctrl+S・閉じるときの確認を VS Code に任せられる。元に戻す・やり直しの中身は、拡張が Change を `onDidChangeCustomDocument` の編集として渡して作る
   （ふつうの Webview パネルでこれらを自前で作る）。[ADR 015](adr.md)

## 12. v0.2 で足すもの

[tasks-v0.2.md](tasks-v0.2.md) の「決めたこと」を約束にしたもの。v0.1 の形は変えず、項目とメソッドを足す（v0.1 の拡張が知らない項目は無視できる）。
**状態: 決定。** 約束の版（`protocolVersion`）は段 3 で `"0.2"` に上げた（段 2 の間は `"0.1"` のまま足した）。
`"0.2"` のサーバーは、1.0 になるまでの決まり（[4.](#initialize)）のとおり `"0.1"` の拡張を `-32051` で断る。

### 12.1 KeySlot（キーを入れる欄 1 つ）

v0.1 のレイヤーのキー・エンコーダの操作と同じ「Address と値」の組に名前を付け、中身の画面でも使う。

```ts
type KeySlot = {
  address: Address;             // その値を書く場所（まだ書いていなければ、書くときの場所）
  value: KeyValue | null;       // 書いていなければ null。注記は KeyValue.note
};
```

`LayerKey` と `EncoderAction` は KeySlot に位置（hand / row / col）を足したもの・KeySlot そのものとして読み替えてよい（形は v0.1 と同じ）。

### 12.2 `profile/open` に足すもの

```jsonc
{
  "positionMap": [
    { "hand": "left", "row": 0, "col": 0, "group": "row0", "symbol": "tab",
      "address": { "file": "position_map.yaml", "path": ["left_hand", "row0", 0] } }       // 足す: 名前を書いている場所
  ],
  "layers": [
    { "index": 0, "name": "Base", "...": "v0.1 と同じ",
      "descriptionAddress": { "file": "layers/0_base.yml", "path": ["description"] } }   // 足す
  ],
  "macros": [
    {
      "index": 0, "name": "Bracket Pair", "description": "角括弧ペア", "file": "macros/00_bracket_pair.yml",
      "descriptionAddress": { "file": "macros/00_bracket_pair.yml", "path": ["description"] },
      "icon": null,                       // preset: のマクロの元のアプリのアイコン（なければ null）
      "preset": null,                     // preset: の名前（sequence で書いていれば null）
      "presetAddress": null,              // preset: で書いていれば ["preset"] の Address（同梱のマクロの選び直しに使う）
      "summary": ["tap: [ ] ←"],         // 手順を 1 行ずつ（keycode/inspect の説明の手順の行と同じ文。preset でも出す）
      "steps": [                          // sequence の手順（preset で書いていれば []）
        {
          "address": { "file": "macros/00_bracket_pair.yml", "path": ["sequence", 0] },
          "action": "tap",                // "tap" | "down" | "up" | "delay" | "text"
          "keysAddress": { "file": "…", "path": ["sequence", 0, "keys"] },          // tap / down / up だけ
          "keys": [ { "address": { "file": "…", "path": ["sequence", 0, "keys", 0] }, "value": { "text": "KC_LBRACKET", "...": "KeyValue" } } ]
        },
        { "address": { "…": "…" }, "action": "delay",
          "duration": { "address": { "file": "…", "path": ["sequence", 1, "duration"] }, "value": 100 } },
        { "address": { "…": "…" }, "action": "text",
          "content": { "address": { "file": "…", "path": ["sequence", 2, "content"] }, "value": "hello" } }
      ]
    }
  ],
  "tapDances": [
    {
      "index": 4, "name": "Tab Escape", "description": null, "file": "tap_dance/04_tab_escape.yml",
      "descriptionAddress": { "…": "…" },
      "actions": { "tap": KeySlot, "hold": KeySlot, "doubleTap": KeySlot, "tapHold": KeySlot },
      "tappingTerm": { "address": { "file": "…", "path": ["tapping_term"] }, "value": 200 }   // 書いていなければ value は null（読み込みでは 250）
    }
  ],
  "combos": [
    {
      "index": 0, "name": "Left Bracket", "description": null, "file": "combos/00_left_bracket.yml",
      "descriptionAddress": { "…": "…" },
      "triggersAddress": { "file": "…", "path": ["trigger_keys"] },
      "triggers": [KeySlot, KeySlot],     // trigger_keys に書いてある数だけ（KC_NO の詰め物も書いてあれば出す）
      "output": KeySlot
    }
  ],
  "shortcuts": [
    { "name": "前のタブへ", "address": { "file": "shortcuts.yaml", "path": ["shortcuts", "前のタブへ"] },
      "value": { "text": "Command + Shift + [", "...": "KeyValue" } }
  ]
}
```

- 並びは `references` と同じ（マクロ・タップダンス・コンボは番号の順、ショートカットはファイルの順）。`status: "invalid"` のときは 4 つとも `[]`
- `description` は書いていなければ `null`。`descriptionAddress` はいつもある（書いていなければ挿入の場所）
- 名前（`name`）の Address は返さない。名前を変えるのは参照の書き換えを伴うので Change ではなく [12.5](#125-profileplanitemedit) で行う
- マクロの手順の `keys` は、ファイルが 1 つの値（`keys: KC_A`）で書いていれば要素 1 つで、その Address は `["sequence", i, "keys"]`
- タップダンスの動作の Address は、ファイルが `actions:` の下に書いていれば `["actions", "on_tap"]`、上の階層なら `["on_tap"]`。
  動作をどちらにも書いていなければ `actions:` の下（`Schema::TapDanceFile.write` と同じ形）
- コンボの `triggers` の要素の Address は `["trigger_keys", i]`、`output` は `["output_key"]`
- ショートカットの `path` は `["shortcuts", 名前]`（名前に `.` があってもそのまま 1 つの要素）

### 12.3 Change に足すもの

`op` を省けば v0.1 と同じ値の書き換え（`set`）。

```ts
type Change =
  | { op?: "set"; address: Address; value: string | number | boolean; field?: "key" | "note" }
  | { op: "remove"; address: Address; field?: "key" | "note" }
  | { op: "insert"; address: Address; index: number; value: string | MacroStepValue }
  | { op: "move"; address: Address; from: number; to: number };

type MacroStepValue =
  | { action: "tap" | "down" | "up"; keys: string[] }
  | { action: "delay"; duration: number }
  | { action: "text"; content: string };
```

- **set**: `field: "note"` は注記を書く（`field` を省くか `"key"` なら割り当て）。注記のない形（`tab: Escape`）に注記を書くと
  フロー表記の `{ key: Escape, note: 注記 }` にする（ブロック表記の行の中で値の部分だけを置き換える）。注記を書けるのは注記付きの形を書ける場所
  （レイヤーのキー・エンコーダの操作・タップダンスの動作・コンボの `output_key`。[notation.md](../notation.md)）だけで、ほかは `-32602`
- **remove**: 宛先の行（Hash の 1 項目）か並びの要素を消す。`field: "note"` は注記だけを消して `key` の値だけの形に戻す。
  消せる宛先: レイヤーのキー（行を消す。消したあとの読み込みでは「割り当てなし」で、compile では KC_NO。[tasks-v0.2.md](tasks-v0.2.md) の決めたことの 4）、エンコーダの操作、タップダンスの動作、`description`、
  `tapping_term`、マクロの手順（`["sequence", i]`）、手順のキー（`["sequence", i, "keys", j]`）、コンボのキー（`["trigger_keys", i]`）。
  消したあとの中身が構造の問題になるとき（手順のキーが 0 個など）も書き換えは作り、検証の結果で知らせる（[6.2](#62-保存の流れ) のとおり保存は止まる）
- **insert**: 宛先は並び（`["sequence"]`、`["sequence", i, "keys"]`、`["trigger_keys"]`）で、`index` の前に足す（並びの長さなら末尾）。
  手順の値は MacroStepValue、キーは表記の文字列。1 つの値で書いた `keys`（`keys: KC_A`）に足すときは、フロー表記の並び（`keys: [KC_A, KC_B]`）に置き換える
- **move**: 並びの中で `from` の要素を `to` の位置へ動かす（ほかの要素の順は保つ）。要素の行（コメントを含む）ごと動かす
- 並び（`sequence`・`keys`・`trigger_keys`）の中を指す Address は、それより前の Change を当てたあとの位置で数える。
  そのため拡張は、並びの要素を指す Change と並びへの `insert` / `remove` / `move` を畳まずに並びの順のまま持つ
  （v0.1 の「同じ Address は最後の値だけ」は、並びの中を指さない `set` にだけ使う）
- フロー表記の並びの中への挿入・移動は、並び全体を 1 行のフロー表記として書き直す（並びの中のコメントはないものとする。
  並びが複数行のフロー表記なら `-32061`（reason `"flowInsert"`））
- 拡張の当て直し（[7.3](#73-拡張の扱い)）: 並びを指す Change（`insert` / `remove` / `move` と、並びの要素を指す `set`）があるファイルが外で変わったら、
  そのファイルの Change はまとめて「当て直せないもの」として扱う（並びの位置がずれているかもしれないため）

### 12.4 中身の画面の context

`keycode/candidates` と `keycode/inspect` の `context` に足す。上に出すものは `data/keycode_categories.yaml` の `contexts` に書く（[spec.md](spec.md) の「ファイルの種類ごと」）。

| context | 欄 | 候補から除くもの | 上に出すもの |
|---|---|---|---|
| `macroKey` | マクロの手順のキー | レイヤー操作・マクロ・タップダンス・ショートカット（「すべて出す」は `all: true`） | 基本キー・修飾キー・メディア |
| `tapDanceAction` | タップダンスの動作 | そのタップダンス自身（params の `exclude: "TapDance('名前')"`） | 基本キー・レイヤー操作 |
| `comboTrigger` | コンボの同時に押すキー | レイヤー操作・マクロ・タップダンス・ショートカット | ベースレイヤー（レイヤー 0）にあるキー |
| `comboOutput` | コンボの出すキー | — | マクロ・基本キー |
| `shortcutValue` | `shortcuts.yaml` の値 | ショートカット（`Shortcut(...)`） | 修飾キー式の候補・基本キー |

- params に足す: `all?: boolean`（`macroKey` で除くものも出す。既定 `false`）、`exclude?: string`（その表記と同じ値の候補を除く）
- 修飾キー式の組み立て欄（[tasks-v0.2.md](tasks-v0.2.md) の 6）は拡張が表記を組み立て、`keycode/inspect` で解釈を確かめる（サーバーに組み立てのメソッドは足さない）

### 12.5 `profile/planItemEdit`

項目の追加・削除・名前の変更を、ファイルの作成・削除・改名と書き換えにして返す。[tasks-v0.2.md](tasks-v0.2.md) の決めたことの 2 のとおり、
拡張は確認のダイアログを出してからすぐに当てて保存する（未保存の変更には積まない）。未保存の変更があるときは、拡張が先に保存を促す。

```jsonc
// params
{ "profileId": "p1", "baseVersions": { /* snapshot.files をそのまま */ }, "edit": ItemEdit }
// result
{
  "files": [
    { "file": "macros/05_new_macro.yml", "baseVersion": null, "create": true,
      "edits": [{ "range": { "start": { "line": 0, "character": 0 }, "end": { "line": 0, "character": 0 } }, "newText": "---\nindex: 5\n…" }] },
    { "file": "macros/03_old.yml", "baseVersion": "sha256:…", "renameTo": "macros/03_new_name.yml", "edits": [ /* name の行 */ ] },
    { "file": "macros/04_unused.yml", "baseVersion": "sha256:…", "delete": true, "edits": [] }
  ],
  "references": [ /* Address[]。削除・名前の変更で書き換える（削除なら壊れる）参照の場所 */ ],
  "diagnostics": []
}
```

```ts
type ItemKind = "macro" | "tapDance" | "combo" | "shortcut";   // rename だけ "layer" も使える（v0.4 で create・delete も。14.9）
type ItemEdit =
  | { op: "create"; kind: "macro" | "tapDance" | "combo"; name: string; preset?: string }
  | { op: "create"; kind: "shortcut"; name: string; value: string }
  | { op: "delete"; kind: ItemKind; name: string }
  | { op: "rename"; kind: ItemKind | "layer"; name: string; to: string }
  | { op: "renamePosition"; hand: "left" | "right"; row: number; col: number; to: string };
```

- **create**: 番号は空いているいちばん小さい番号（上限を超えれば `-32602`、`data: { "field": "edit" }`）。ファイル名は `<2 桁の番号>_<名前から作った slug>.<拡張子>`
  （slug は ASCII の英数字を小文字にして、ほかを `_` にまとめたもの。残らなければ `macro` / `tap_dance` / `combo`。拡張子はそのディレクトリでいちばん多いもの、なければ `yaml`）。
  中身は `Schema::*File.write` と同じ形の最小のもの（マクロは `action: tap`・`keys: [KC_NO]` の手順 1 つか `preset:`、タップダンスは動作なし、コンボは `trigger_keys: [KC_NO, KC_NO]` と `output_key: KC_NO`）。
  ショートカットは `shortcuts.yaml` の `shortcuts:` の末尾に `名前: 値` の行を足す（ファイルがなければ作る）。同じ名前がすでにあれば `-32602`
- **delete**: ファイルを消す（ショートカットは行を消す）。参照は書き換えず、`references` に壊れる参照の場所を返す（拡張は確認のダイアログに件数を出す）。
  `diagnostics` は消したあとの検証の結果（参照している側にエラー）
- **rename**: `name` の行を書き換え、参照（`Macro('旧名')` / `TapDance('旧名')` / `Shortcut('旧名')`）をすべての設定ファイルでテキストとして置き換え、
  ファイル名の slug を新しい名前に合わせて `renameTo` にする（番号の接頭辞は保つ）。前後の compile の結果（16bit 値）が同じでなければ、書かずに `-32061`（reason `"verify"`）。
  `Application::RenameFiles` と同じ手順だが、ファイルは書かずに書き換えとして返す。レイヤーは名前で参照されないので、`name` の行とファイル名だけを変える
- **renamePosition**: `position_map.yaml` のその位置の名前と、すべてのレイヤーのファイルの `mapping` の下のその名前のキーを書き換える（compile の結果は変わらない）。
  同じグループに同じ名前があれば `-32602`。フロー表記の position_map（`row0: [tab, Q, …]`）は並びの中の 1 要素だけを置き換える
- 名前の決まり（空でない・前後の空白なし・既存の名前と重ならない）に合わなければ `-32602`（`data: { "field": "edit.name" }` か `"edit.to"`）。知らない名前は `-32050` ではなく `-32602`
- 拡張は `files` を 1 つの `WorkspaceEdit`（`createFile` / `deleteFile` / `renameFile` と `replace`）にして当て、書き換えたファイルを保存し、
  `profile/saved` に新しい版（消したファイルは `null`、改名したファイルは古い名前に `null`・新しい名前に版）を送る。VS Code の元に戻す（ファイルの undo）で戻せる
- `baseVersions` の照合と `-32060` は [6.1](#61-profileplanedits) と同じ（書き換えるファイルだけを比べる）

### 12.6 エラーに足すもの

- `-32061` の reason に `"verify"`（名前の変更の前後で compile の結果が変わる）を足す

### 12.7 拡張だけで作るもの

約束は変えない。

- 位置の名前の表示: 図の上のトグルボタンで固定の切り替え、Alt を押している間だけ一時表示。名前は紫（`--vscode-charts-purple`）、マクロの `M` の印は橙（`--vscode-charts-orange`）に変える。
  下のペインのレイヤーの欄のラベルも同じ紫
- `KC_TRNS` のキー: レイヤー 0 の同じ位置の値の `display.label` を薄く描き、説明に「レイヤー 0 の値」と書く（snapshot の `layers[0]` から拡張が引く）
- 候補の行のアイコン: `Candidate.icon`（v0.1 からある）を候補の行に描く
- テキストの波線: `profile/open` と `profile/didChange` の `diagnostics` の `range` を `DiagnosticCollection` に入れる（`address` も `file` もないものは出さない）

## 13. v0.3 で足すもの

[tasks-v0.3.md](tasks-v0.3.md) の「決めたこと」を約束にしたもの。v0.2 の形は変えず、項目を足す（v0.2 の拡張が知らない項目は無視できる）。
**状態: 決定。** 約束の版（`protocolVersion`）は段 3 で `"0.3"` に上げた（段 2 の間は `"0.2"` のまま足した）。
`"0.3"` のサーバーは、1.0 になるまでの決まり（[4.](#initialize)）のとおり `"0.2"` の拡張を `-32051` で断る。

### 13.1 `profile/planItemEdit` に足すもの

```ts
type ItemEdit =
  | /* 12.5 のもの */
  | { op: "expandPreset"; kind: "macro"; name: string };
```

- **expandPreset**: `preset:` で書いたマクロの `preset:` の行を、同梱の定義（`data/shortcuts/` の `macro: true` の項目）の手順の `sequence:` に置き換える。
  ほかの行（`name` `description` `index` やコメント）は変えない。手順の書き方は `Schema::MacroFile.write` と同じ形
- 前後の compile の結果（16bit 値）が同じでなければ、書かずに `-32061`（reason `"verify"`）
- `preset:` で書いていないマクロ・知らない名前は `-32602`（`data: { "field": "edit.name" }`）
- 結果の形は 12.5 と同じ（`files` は書き換える 1 ファイル、`references` は `[]`）。拡張は確認のダイアログのあとすぐ当てて保存する

### 13.2 `profile/open` に足すもの

```jsonc
{
  "combos": [
    { "index": 0, "name": "Left Bracket", "...": "12.2 と同じ",
      "reachable": true }               // 足す: トリガーのキーがすべてそろうレイヤーがある
  ]
}
```

- `reachable` は、どれかのレイヤーで、そのレイヤーに割り当てたキーコード（`KC_TRNS` の位置はレイヤー 0 の値）にトリガーのキーがすべて入っていれば `true`。
  トリガーが `KC_NO` だけのコンボは `true`（作ったばかりのものに印を付けない）
- 同じ判定で、意味検証の警告「押せないコンボ」を出す（`address` はそのコンボの `["trigger_keys"]`。validate にも出る）

### 13.3 振る舞いだけ変えるもの

形は変えない。

- `keycode/candidates`: 前方一致・部分一致の下に、query の文字を順に含むもの（あいまい一致）を出す。大文字小文字・`_`・空白は区別しない。
  当てはまり方が同じ候補の中では、そのプロファイルで使っている回数の多いものを上にする（context ごとに上に出すものは今までどおり先）
- `KeyValue.display`: `KC_UP` / `KC_LEFT` / `KC_RIGHT` / `KC_DOWN` の `label`（と `tap`）を `↑` / `←` / `→` / `↓` にする。`text`（表記）は変えない

### 13.4 拡張だけで作るもの

約束は変えない。[tasks-v0.3.md](tasks-v0.3.md) の決めたことの 1〜3 と、申し送りの見た目の直し（`（なし）` を出さない、節を畳む、書いていない位置を NoKey と同じ枠に）。
同梱のショートカットの選択は `keycode/shortcutTree`（v0.2 からある）を使い、コピーは `create`・`kind: "shortcut"`（12.5）で足す。

## 14. v0.4 で足すもの

[tasks-v0.4.md](tasks-v0.4.md) の「決めたこと」を約束にしたもの。実機の操作は、`cornix serve` とは別のプロセスの device のサーバーで行う（ADR 018）。
**状態: 設計（実装はこれから）。** ただし 14.9（レイヤーの追加と削除。issue #84）は入れた。14.9 は足しただけ（今のリクエストの形は変えない）なので、約束の版（`protocolVersion`）は `"0.3"` のまま。
`"0.4"` に上げるのは段 3（device のサーバーを入れるとき）。device のサーバー（14.1〜14.8）のほかは、編集のサーバー（`cornix serve`）の形は変えない。

### 14.1 device のサーバー

```
cornix serve --device [--allow-writes]
```

- 枠（Content-Length）・JSON-RPC・ライフサイクル（`initialize` / `shutdown` / `exit`）は [1.](#1-通信) と [4.](#4-ライフサイクルのメソッド) と同じ。登録するメソッドは `device/*` だけ（ほかは `-32601`）
- `initialize` の `capabilities` に `"device": true` と `"deviceWrites": <--allow-writes を付けたか>` を返す
- 拡張は設定 `cornix.device.allowWrites` が `true` のときだけ `--allow-writes` を付ける。付けずに起動したサーバーは `device/apply` と `device/restore` を `-32074` で断る（ADR 019）
- 拡張は必要になったときに起動し、使い終わっても残す。`allowWrites` が変わったら起動し直す。キーボードへの接続はメソッドごとに開いて閉じる（今の `Environment#open_device` と同じ）
- リクエストは 1 つずつ処理する。実機を読むのに BLE で約 10 秒かかる（[device.md](../device.md)）が、編集のサーバーとは別のプロセスなので候補や検証は止まらない
- プロファイルは各メソッドの `dir`（[5.1](#51-profilelist) の `dir`）で指す。compile の出力はそのプロファイルの tmp（`Application::Workspace` の決まり）

### 14.2 共通の型

```ts
// 実機との違い 1 件
interface DeviceChange {
  kind: "key" | "encoder" | "macro" | "tapDance" | "combo" | "setting" | "other";
  layer?: number;            // kind が key / encoder のとき
  position?: string;         // kind が key のとき。position_map の位置（図と欄で使う）
  encoder?: { side: "left" | "right"; direction: "cw" | "ccw" | "push" };
  index?: number;            // macro / tapDance / combo の番号
  name?: string;             // 名前がある項目（マクロなど）・設定の名前
  device: string;            // 実機の今の値の表記（キーは VialNotation の表記。項目は短い要約）
  profile: string;           // このプロファイルの値の表記
  text: string;              // 1 行の説明（Device::ChangeDescriber と同じ文）
}

interface DevicePlan {
  token: string;             // Planning::Plan#token。device/apply・device/restore に渡す
  empty: boolean;
  changes: DeviceChange[];
  warnings: string[];        // RMK 未対応のキーコードなど（Device::ChangePolicy）
  keyboard: { name: string; uid: string };   // 書き込み先（確認のダイアログに出す）
}
```

- マトリクスの座標 → `position` は `Domain::PositionMap` で直す。位置に名前がない（`position_map.yaml` にない）キーは `kind: "other"` にして `text` だけを使う

### 14.3 `device/compare`（読むだけ）

```jsonc
// params
{ "dir": "profiles/default" }
// result
{ "plan": DevicePlan, "source": "tmp/profiles/default/build/layout.vil" }
```

- 保存済みのファイルを compile し、その出力と実機の差分を返す（`Application::Compile` → `Application::DeviceDiff`）。未保存の変更は見ない（拡張は先に保存を促す）
- プロファイルが検証のエラーで compile できないときは、何も読まずに `-32075` CompileFailed（message に compile のエラーの文、`data: { "diagnostics": Diagnostic[] }`）

### 14.4 `device/apply`

```jsonc
// params
{ "dir": "profiles/default", "token": "…" }   // token は直前の device/compare の plan.token
// result
{ "applied": 12, "backup": "tmp/profiles/default/device_backups/20261021-101500.vil", "remaining": DeviceChange[] }
```

- サーバーは compile し直して計画し直し、`token` が違えば何も書かずに `-32071`（直前の比べたあとで、ファイルか実機が変わった）
- 差分がなければ何も書かず、バックアップも取らない（`applied: 0`・`backup: null`）
- 書く前に今の状態をバックアップし、1 件ずつ書き、読み直して検証する（`Application::DeviceApply` の `expected_token`）。`remaining` は読み直しで残った違い（ふつうは `[]`）
- 書いている途中で切れたら `-32072`（`data: { "applied": 5, "backup": "…" }`）。もう一度比べて反映すれば続きからそろう

### 14.5 `device/backups` と `device/compareBackup`・`device/restore`

```jsonc
// device/backups の params / result
{ "dir": "profiles/default" }
{ "backups": [ { "name": "20261021-101500", "path": "tmp/…/20261021-101500.vil", "createdAt": "2026-10-21T10:15:00+09:00" } ] }   // 新しい順

// device/compareBackup（読むだけ）の params / result
{ "dir": "profiles/default", "backup": "20261021-101500" }
{ "plan": DevicePlan, "source": "tmp/…/20261021-101500.vil" }

// device/restore の params / result（14.4 と同じ形）
{ "dir": "profiles/default", "backup": "20261021-101500", "token": "…" }
{ "applied": 12, "backup": "tmp/…/20261021-101820.vil", "remaining": [] }
```

- `Application::ListBackups` / `DeviceRestore`（`dry_run: true` が compareBackup）を使う。知らない `backup` は `-32602`（`data: { "field": "backup" }`）
- 戻す前にも今の状態をバックアップする（続けてもう一度戻すと戻す前に戻る）

### 14.6 `device/progress`（サーバー → 拡張、通知）

```jsonc
{ "phase": "read" | "write" | "verify", "done": 120, "total": 560 }
```

- 読む・書く・読み直すの進み具合。拡張は `withProgress` に出す
- `$/cancelRequest` は `phase: "read"` の間だけ受け付け、そのリクエストを `-32800`（RequestCancelled）で終える。書き始めたら取り消せない（受け取っても続ける）

### 14.7 エラーに足すもの

| code | 名前 | いつ | data |
|---|---|---|---|
| -32070 | DeviceUnavailable | 実機が使えない | `{ "reason": "platform" \| "bridge" \| "notConnected" \| "timeout" }`（macOS 以外・ブリッジが未ビルド・見つからない・応答がない） |
| -32071 | PlanChanged | `token` が計画し直したものと違う | — |
| -32072 | WriteIncomplete | 書いている途中で切れた・失敗した | `{ "applied": 5, "backup": "…" }` |
| -32073 | PlanRejected | 書き込み禁止のキーコード（`QK_BOOT` など。`Device::ChangePolicy`）を含む計画。`device/compare` でも返す | `{ "keycodes": ["QK_BOOT"] }` |
| -32074 | WritesNotAllowed | `--allow-writes` なしで書き込みのメソッドを呼んだ | — |
| -32075 | CompileFailed | プロファイルが compile できない | `{ "diagnostics": Diagnostic[] }` |
| -32800 | RequestCancelled | 読む間に取り消された（LSP と同じ code） | — |


### 14.8 拡張だけで作るもの

約束は変えない。[tasks-v0.4.md](tasks-v0.4.md) の「画面」: ボタンと「実機: 同じ／違う N 件／未確認」の印（状態バーにも）、違うキーの橙の枠とレイヤーのタブの点、
「実機との差分」の節、確認のダイアログ（件数・警告・`keyboard.name`）、バックアップの選択（QuickPick）、設定 `cornix.device.allowWrites`。
保存したら印を「未確認」に戻す（`profile/saved` のあと）。

### 14.9 `profile/planItemEdit` に足すもの（レイヤーの追加と削除。issue #84）

**状態: 入れた。** 空のレイヤーのファイルを置かなくてよくなった（issue #83）ので、ファイルのないレイヤーは画面に出ない。拡張からレイヤーのファイルを作る・消す。

```ts
type ItemEdit =
  | /* 12.5・13.1 のもの */
  | { op: "create"; kind: "layer"; name: string; index?: number }   // index は 0〜9。省けば空いているいちばん小さい番号
  | { op: "delete"; kind: "layer"; name: string; file?: string }   // file があればファイルで探す（下の「レイヤーの指し方」）
  | { op: "rename"; kind: "layer"; name: string; to: string; file?: string };   // rename は 12.5 のもの。file を足した
```

- **レイヤーの指し方**: レイヤーの名前は重なってよい（decompile は空のレイヤーをどれも `Empty` などにする。ファイル名は番号の接頭辞で分かれる）。
  また番号のない（使わない）レイヤーのファイルも予定している（issue #85）。名前でも番号でも 1 つに決まらないので、`delete`・`rename` は
  `file`（設定ディレクトリからの相対パス。snapshot の `layers[].file`）があればそのファイルのレイヤーを探す（省けば `name` の最初のもの。v0.2 の拡張のため）。
  ファイルのパスは設定ディレクトリの中で一意。そのファイルのレイヤーがなければ `-32602`（`"edit.file"`）。`file` はレイヤーだけ、`index` は `create` だけに書ける。
  `create`・`rename` の新しい名前は、ほかのレイヤーと同じでもよい（空・前後の空白・改行はだめ）。拡張は削除と名前の変更にいつも `file` を付ける。
  名前を変えるとファイル名も変わるが、結果の `renameTo` と次の snapshot で新しいパスが分かる。
  マクロ・タップダンス・コンボも #85 で同じことになるので、そのときにそろえる

- **create**: `layers/<番号>_<名前>.<拡張子>` を作る。名前の部分は `Storage::ConfigFiles.item_path` と同じ（decompile が書く名前とそろえる。既定の名前 `Layer N` なら `layer`）、
  拡張子はそのディレクトリでいちばん多いもの（なければ `yaml`）。中身は `Schema::LayerFile` が受け付ける最小の形（`name`・`description: ''`・`index`・`mapping` の両手の空のグループ。エンコーダは書かない）。
  その番号のレイヤーがもうある・範囲の外なら `-32602`（`data: { "field": "edit.index" }`）、`index` を省いて空いている番号がなければ `"edit"`。
  名前は空でなければよい（上の「名前の重なり」）。`index` はレイヤーのときだけ書ける（ほかの種類に書けば `-32602`、`"edit.index"`）
- **delete**: そのファイルを消す。参照は書き換えず、`references` にそのレイヤーを指すレイヤー操作（`MO` / `TG` / `TO` / `OSL` / `LT` / `LM` など。
  16bit 値で数える。消すファイルの中は入れない）の場所を返す。`diagnostics` は消したあとの検証の結果（指していた側に警告「レイヤー N が定義されていません」）。
  compile では消したレイヤーは `KC_NO` で埋まる（#83）
- 結果の形・確認のダイアログのあとすぐ当てて保存することは 12.5 と同じ
- 適合テストのデータは `spec/fixtures/protocol/profile_plan_item_edit/` の `create_layer*.json`・`create_index_not_layer.json`・`delete_layer*.json`
- 同じ issue の下の欄の「キー別」の並べ方（位置ごとに全レイヤーの欄を並べる）は拡張だけで作る。欄の変更は今と同じ `Change`（そのレイヤーのファイルの `address`）で、約束は変えない
