# バックエンドとのリクエストの約束（v0.1 の案）

VS Code 拡張（以下「拡張」）と、プロファイルを読んで解釈するバックエンド（以下「サーバー」）の間の約束。
拡張はこの約束だけでサーバーと話し、`cornix` コマンドを直接叩かない（[ADR 003](adr.md)）。
いまのサーバーは Ruby（`cornix` のサブコマンド）だが、将来は同梱の TypeScript 版（B 案、[roadmap.md](roadmap.md) の「将来の拡張」）に
差し替えられるように、約束には Ruby のクラス名や内部の形を出さない。

**状態: 案。** 「[判断が要るところ](#判断が要るところ)」に挙げた点が決まったら「案」を外す。

v0.1 で決めるのは次の 5 つだけにする。

1. プロファイルを構造で読む（`profile/open`）
2. 候補を引く（`keycode/candidates`、`keycode/shortcutTree`）と、1 つの値の解釈（`keycode/inspect`）
3. 保存前の状態で検証する（`profile/validate`）
4. 変わった値だけを書き換える変更を返す（`profile/planEdits`）
5. 外での変更の通知（`workspace/didChangeFiles` → `profile/didChange`）

compile / validate / status のコマンド、項目の追加・削除・名前の変更、注記の編集は v0.1 の約束に入れない（[v0.1 に入れないもの](#v01-に入れないもの)）。

## 1. 通信

- **起動**: 拡張が `cornix serve` を子プロセスとして起動する（`cornix` の場所は設定 `cornix.path`）。
  `--root` はワークスペースのフォルダ。1 つのサーバーが同じワークスペースの複数のプロファイルを扱う
- **形式**: JSON-RPC 2.0。標準入出力に、LSP と同じ `Content-Length: <バイト数>\r\n\r\n<JSON>` の枠で 1 メッセージずつ流す
  （拡張は `vscode-jsonrpc` をそのまま使える）。JSON は UTF-8
- **標準出力は JSON-RPC 専用**。ログは標準エラー出力に書き、拡張は出力パネル「Cornix」に流す
- **順序**: サーバーはリクエストを届いた順に 1 つずつ処理する。`$/cancelRequest` は受け付けるが v0.1 では何もしない
- **書き込み**: サーバーはファイルを書かない。保存は、サーバーが返した変更を拡張が当てて行う（[5.7](#57-profileplanedits)）
- **実機**: v0.1 の約束にキーボードに触るメソッドはない（[ADR 014](adr.md)）

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

サーバーが落ちたら、拡張は知らせを出して再起動のボタンを付ける（開いていたプロファイルは `profile/open` からやり直す）。

## 2. 共通の型

TypeScript の書き方で示す。`?` は省略できる項目。

### 位置と範囲

```ts
// ファイルの中の位置。行も列も 0 始まり。列は UTF-16 のコード単位（LSP と同じ。日本語は 1 文字 1 単位）
type Position = { line: number; character: number };
type Range = { start: Position; end: Position };
```

### Address（設定ファイルの中の値の場所）

画面の各項目と、検証の結果と、変更の宛先はすべて Address で指す。

```ts
type Address = {
  file: string;                 // 設定ディレクトリからの相対パス（"layers/0_base.yml"）
  path: (string | number)[];    // ファイルの中のキーの道筋（["mapping", "left_hand", "row0", "tab"]）
};
```

- `path` はファイルに書く形のキー（`Storage::DiagnosticLocator` の「キーの位置」と同じ考え方）。モデル内のパス（`layers[0]...`）は約束に出さない
- 注記付きの形（`{ key: <表記>, note: <注記> }`）でも、`path` は割り当ての場所（`tab`）を指す。`.key` を足すのはサーバーの仕事
- まだファイルに書かれていない場所（割り当てのない位置）も指せる。そこへの変更は挿入になる

### FileVersion

```ts
type FileVersion = string;      // ファイルの中身の SHA-256（"sha256:" + 16 進）。ファイルがなければ null
```

拡張とサーバーが同じ中身を見ているかを確かめるのに使う（mtime は使わない）。

### Diagnostic（検証の結果 1 件）

```ts
type Diagnostic = {
  severity: "error" | "warning";
  message: string;              // 利用者向けの日本語（validate の表示と同じ文）
  source: "structure" | "semantic";   // 構造検証（読み込み）か意味検証（Profile#diagnostics）か
  address?: Address;            // どの値の問題か。ファイルやディレクトリ全体の問題では省く
  file?: string;                // address がないときの、問題のあるファイル（ディレクトリの問題は "macros/"）
  range?: Range;                // 波線を引く範囲（値の部分）。位置が分からなければ省く
};
```

- 原因が別の項目にある問題（消したマクロへの参照など）は、参照している側の `address` に出す（[spec.md](spec.md) の「検証」）
- `range` は YAML のノードの位置（Psych のノードの開始・終了の行と列）から求める。いまの `DiagnosticLocator` は「ファイル: キーの位置」までなので、行と列を足す

### KeyValue（割り当て 1 つの解釈）

```ts
type KeyValue = {
  text: string;                 // ファイルに書いてある表記そのまま（"LT1(Space)"、"Shortcut('VS Code:基本操作:コマンドパレット')"）
  canonical: string;            // decompile の正規形（"LT1(Space)"）
  code: number | null;          // 16bit 値。参照先がないなど値にできなければ null
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
  label: string;                // 図に描く短い文字（"Space"、"⌘⇧P"、"Bracket Pair"）
  tap?: string;                 // 2 役のキーのタップ側（"Space"）
  hold?: string;                // 2 役のキーのホールド側（"L1"、"⇧"）
};
```

`kind` は `Domain::Keycode` の種類に対応する名前だが、約束としては文字列の列挙として固定し、Ruby のクラス名とは切り離す。
表示用の文字（`display`）もサーバーが作る（TypeScript 版も同じ `data/` から同じ文字を作る）。

### Change（画面での変更 1 つ）

```ts
type Change = {
  address: Address;
  value: string | number | boolean;   // キーは表記の文字列、QMK 設定は数値か真偽値
};
```

拡張は未保存の変更を Change の並びとして持つ（同じ Address は最後の値だけ）。
Change は「どのファイルの何行目」ではなく Address で指すので、外でファイルが変わっても、同じ場所が変わっていなければそのまま当て直せる。

## 3. メソッドの一覧

| メソッド | 向き | 種類 | 中身 |
|---|---|---|---|
| `initialize` | 拡張 → サーバー | リクエスト | 約束の版とできることの確認 |
| `initialized` | 拡張 → サーバー | 通知 | 準備ができた |
| `shutdown` / `exit` | 拡張 → サーバー | リクエスト / 通知 | 終わる |
| `profile/list` | 拡張 → サーバー | リクエスト | ワークスペースのプロファイルの一覧と既定 |
| `profile/open` | 拡張 → サーバー | リクエスト | プロファイルを構造で読む |
| `profile/close` | 拡張 → サーバー | 通知 | 開いたプロファイルを閉じる |
| `keycode/candidates` | 拡張 → サーバー | リクエスト | キー入力欄の候補 |
| `keycode/shortcutTree` | 拡張 → サーバー | リクエスト | 同梱のショートカットのアプリ → カテゴリ → ラベル |
| `keycode/inspect` | 拡張 → サーバー | リクエスト | 1 つの表記の解釈・説明・その欄だけの検証 |
| `profile/validate` | 拡張 → サーバー | リクエスト | 未保存の変更を当てた状態でプロファイル全体を検証 |
| `profile/planEdits` | 拡張 → サーバー | リクエスト | 未保存の変更をファイルの書き換え（範囲と文字）にする |
| `workspace/didChangeFiles` | 拡張 → サーバー | 通知 | 設定ディレクトリのファイルが変わった |
| `profile/didChange` | サーバー → 拡張 | 通知 | 開いているプロファイルの中身が外で変わった |

## 4. ライフサイクルのメソッド

### `initialize`

```jsonc
// params
{ "protocolVersion": "0.1", "clientInfo": { "name": "cornix-vscode", "version": "0.1.0" } }
// result
{
  "protocolVersion": "0.1",
  "serverInfo": { "name": "cornix", "version": "0.1.0", "implementation": "ruby" },
  "capabilities": {
    "semanticValidation": true,   // Profile#diagnostics 相当の意味検証をする（TypeScript 版では false もありうる）
    "keycodeCode": true           // KeyValue.code（16bit 値）を返す
  }
}
```

- 版は `major.minor`。major が違えばサーバーは `-32002`（[7. エラー](#7-エラー)）で断る。minor の違いは、知らない項目を無視して続ける
- 拡張は `capabilities` が false の機能を画面に出さない（意味検証がなければ、その欄の構造の検証だけを出す）

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
    { "name": "default", "dir": "profiles/default" },
    { "name": "ipad", "dir": "profiles/ipad" }
  ],
  "default": "default"   // .cornix.yml が指すもの。なければ null（拡張は一覧から選ばせる）
}
```

`dir` はワークスペースのフォルダからの相対パス。`profiles/` の外の設定ディレクトリ（`.cornix.yml` の `config:` や、後方互換の `config/`）も、
名前をディレクトリ名にして並べる。

### 5.2 `profile/open`

プロファイルを読み、画面に描くものをまとめて返す。

```jsonc
// params
{ "profile": "default" }     // profile/list の name
// result: ProfileSnapshot
{
  "profileId": "p1",         // 以降のリクエストで使う。profile/close まで有効
  "name": "default",
  "dir": "profiles/default",
  "status": "ok",            // "ok" | "invalid"（構造検証で読めなかった）
  "files": {                 // 読んだファイルとその中身の版。外での変更と保存のときの照合に使う
    "metadata.yaml": "sha256:9f2c…",
    "layers/0_base.yml": "sha256:41ab…"
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
          "hand": "left", "row": 3, "col": 1,
          "address": { "file": "layers/0_base.yml", "path": ["mapping", "left_hand", "thumb_keys", "middle"] },
          "value": {
            "text": "LT1(Space)", "canonical": "LT1(Space)", "code": 16684, "kind": "layerTap",
            "display": { "label": "Space", "tap": "Space", "hold": "L1" }
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

- `positionMap` と `keys` の位置は論理位置（[domain-model.md](../domain-model.md) の `KeyPosition` の hand / row / col）。
  キーボード図の物理配置は拡張が持ち、この論理位置で組み合わせる（[ADR 009](adr.md)）
- `keys` は割り当てのない位置も含めて position_map のすべての位置を返す（`value` は `null`）。`address` はその位置を書くときの場所
- `status: "invalid"` のときは `diagnostics` だけを信じてよい（`layers` などは空）。拡張はエラーの一覧と、ファイルを開くボタンを出す
- マクロ・タップダンス・コンボ・ショートカットの中身の画面は v0.2。v0.1 では `references` の名前の一覧だけを返す

### 5.3 `keycode/candidates`

キー入力欄の候補。並び順はサーバーが決め、拡張はそのまま出す。

```jsonc
// params
{
  "profileId": "p1",
  "context": "layerKey",     // "layerKey" | "encoder"（v0.1）。v0.2 で "macroKey" "tapDanceAction" "comboTrigger" などを足す
  "query": "cmd",            // 入力中の文字。空なら「上に出すもの」から並べる
  "limit": 50
}
// result
{
  "items": [
    {
      "insertText": "Shortcut('VS Code:基本操作:コマンドパレット')",   // 選んだときに入れる表記（decompile の正規形）
      "label": "コマンドパレット",
      "detail": "VS Code › 基本操作 · Shift + Command + P",
      "category": "presetShortcut",
      "icon": "material-icon-theme:vscode"
    },
    {
      "insertText": "MO(1)", "label": "MO(1)", "detail": "Symbols", "category": "layer"
    },
    {
      "insertText": "QK_REPEAT_KEY", "label": "QK_REPEAT_KEY", "category": "special",
      "warning": "Cornix が対応していないとみられるキーです"
    }
  ],
  "typed": {                 // query をそのまま表記として読めたときの解釈（KeyValue）。読めなければ null
    "text": "cmd", "canonical": "…", "...": "KeyValue と同じ形"
  },
  "truncated": true          // limit で切った
}
```

```ts
type CandidateCategory =
  | "basic" | "modifier" | "media" | "mouse" | "layer" | "macro" | "tapDance"
  | "shortcut" | "presetShortcut" | "special" | "raw";
```

- 当てる文字・並べ方・除くものは [spec.md](spec.md) の「入力と補完」のとおり（正規の名前・別名・QMK 名・記号・ショートカットの日本語ラベルとアプリ名に部分一致、
  完全一致と前方一致を上に、`data/dangerous_keycodes.yaml` は出さない、`data/unsupported_keycodes.yaml` は `warning` を付けて下に）
- `raw`（`0x7E40`）は query が `0x` で始まるときだけ出す
- 修飾キー式（`Shift + Command + P`）は v0.1 では候補に出さず、打った文字を `typed` で解釈して見せる
- 「この入力ならこの候補」の共通テスト（[ADR 004](adr.md)）は、このメソッドの params と result の組をデータに書いたものにする（[8.2](#82-適合テスト)）

### 5.4 `keycode/shortcutTree`

同梱のショートカットを アプリ → カテゴリ → ラベル で辿るための木。中身はプロファイルによらないので、拡張は 1 回取ってとっておいてよい。

```jsonc
// params
{ "profileId": "p1" }
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
              "text": "Shift + Command + P", "macro": false }
          ]
        }
      ]
    }
  ]
}
```

`macro: true` は複数の手順の定義で、`macros/` の `preset:` でだけ使える（キー入力欄の候補には出さない）。

### 5.5 `keycode/inspect`

1 つの表記の解釈。入力欄の onchange の検証と、マウスを載せたときの説明に使う。

```jsonc
// params
{ "profileId": "p1", "context": "layerKey", "text": "Macro('Bracket Pair')", "changes": [] }
// result
{
  "value": {                 // KeyValue。読めなければ null
    "text": "Macro('Bracket Pair')", "canonical": "Macro('Bracket Pair')", "code": 30464, "kind": "macro",
    "display": { "label": "Bracket Pair" }
  },
  "diagnostics": [],         // この欄だけで分かる問題（読めない表記、参照先がない、未対応のキーなど。address は省く）
  "description": {           // 説明（マウスを載せたとき）
    "title": "マクロ Bracket Pair（M0）",
    "lines": ["角括弧ペア [] を挿入してカーソルを内側に配置", "tap: [ ] ←"]
  }
}
```

- `changes` は未保存の変更（参照先の有無を未保存の状態で判断するため）。v0.1 では名前を変える操作がないので、たいてい空でよい
- 説明に出すもの: Shortcut の中身（`Shift + Command + P`）、マクロの手順、タップダンスの 4 つの動作、レイヤー操作の行き先のレイヤー名、16bit 値

### 5.6 `profile/validate`

未保存の変更を当てた状態で、プロファイル全体を検証する（いまの `cornix validate` は保存済みのファイルを読むので、その前の状態を検証する入口）。

```jsonc
// params
{
  "profileId": "p1",
  "baseVersions": { "layers/0_base.yml": "sha256:41ab…" },   // 変更を作ったときのファイルの版
  "changes": [
    { "address": { "file": "layers/0_base.yml", "path": ["mapping", "left_hand", "row0", "tab"] }, "value": "Macro('Removed')" }
  ]
}
// result
{
  "diagnostics": [
    {
      "severity": "error", "source": "semantic",
      "message": "マクロ「Removed」は定義されていません",
      "address": { "file": "layers/0_base.yml", "path": ["mapping", "left_hand", "row0", "tab"] },
      "range": { "start": { "line": 7, "character": 11 }, "end": { "line": 7, "character": 27 } }
    }
  ]
}
```

- サーバーは [5.7](#57-profileplanedits) と同じ書き換えをメモリの上で当て、構造検証と意味検証を行う。ファイルは書かない
- `range` は変更を当てたあとの中身での位置（保存すればそのまま波線に使える）
- `baseVersions` が今のファイルと違えば `-32010`（版の食い違い）

### 5.7 `profile/planEdits`

未保存の変更を、ファイルの書き換え（範囲と文字）にして返す。拡張はこれを VS Code の `WorkspaceEdit` として当てて保存する。

```jsonc
// params
{ "profileId": "p1", "baseVersions": { "layers/0_base.yml": "sha256:41ab…" }, "changes": [ /* Change[] */ ] }
// result
{
  "files": [
    {
      "file": "layers/0_base.yml",
      "baseVersion": "sha256:41ab…",
      "newVersion": "sha256:77c0…",    // 書き換えたあとの中身の版（保存したあとの外での変更と見分けるため）
      "create": false,                 // ファイルを新しく作るとき true（settings/qmk_settings.yaml がないときなど）
      "edits": [
        { "range": { "start": { "line": 7, "character": 11 }, "end": { "line": 7, "character": 34 } }, "newText": "Escape" }
      ]
    }
  ],
  "diagnostics": []                    // 書き換えたあとの検証の結果（validate と同じ）
}
```

書き換えの決まり（[ADR 006](adr.md)）:

- 値の部分（スカラーの範囲）だけを置き換える。キー・字下げ・コメント・ほかの行・フロー表記（`{ tab: Escape, Q: Q }`）の並びは変えない
- 値が今のファイルの値と同じ（表記の文字が同じ）なら書き換えを作らない
- 引用符はサーバーが決める（`","` `"-"` のように YAML で引用符が要るものだけ囲む。もとが引用符付きならその引用符を保つ）
- 注記付きの形は `key` の値だけを置き換え、`note` は残す
- まだ書かれていない位置は、同じグループの中の position_map の順の場所に `symbol: 値` の行を足す（ブロック形式のとき）
- 局所的に書き換えられないとき（複数行の値、アンカーとエイリアス、フロー表記の中への挿入など）は、そのファイルを作り直さずに
  `-32011`（書き換えられない）を返す（[判断が要るところ](#判断が要るところ) の 5）
- `baseVersions` が今のファイルと違えば `-32010`

## 6. 外での変更

### `workspace/didChangeFiles`（拡張 → サーバー、通知）

拡張は `vscode.workspace.createFileSystemWatcher` で設定ディレクトリを見張り、変わったファイルを知らせる（LSP の `workspace/didChangeWatchedFiles` と同じ役目。
Ruby 側に監視の gem を足さないため）。

```jsonc
{ "changes": [ { "path": "profiles/default/layers/0_base.yml", "type": "changed" } ] }   // type: "created" | "changed" | "deleted"
```

### `profile/didChange`（サーバー → 拡張、通知）

サーバーは知らされたファイルを読み直し、中身の版が自分の知っている版（`profile/open` の `files` か、`planEdits` の `newVersion`）と違うときだけ、
そのプロファイルについて知らせる。拡張が自分で保存したことによる変更では知らせない。

```jsonc
{
  "profileId": "p1",
  "files": { "layers/0_base.yml": "sha256:e1d4…" },   // 変わったファイルと新しい版（消えたファイルは null）
  "snapshot": { /* ProfileSnapshot（profile/open の result と同じ形） */ }
}
```

拡張の扱い（[ADR 007](adr.md)）:

- 未保存の変更がなければ、`snapshot` で黙って描き直す
- あれば、どちらを残すか聞く。「画面の変更を残す」を選んだら、`baseVersions` を新しい版にして Change をそのまま当て直す
  （同じ Address が外でも変わっていたら、その Change の今の値と外の値を並べて見せる）

## 7. エラー

JSON-RPC のエラーで返す。`message` は利用者に見せてよい日本語。`data` に機械向けの中身を入れる。

| code | 名前 | いつ | data |
|---|---|---|---|
| -32700 | ParseError | JSON として読めない | — |
| -32600 | InvalidRequest | JSON-RPC の形でない | — |
| -32601 | MethodNotFound | 知らないメソッド | — |
| -32602 | InvalidParams | params の形が違う、Address が指せない（`layers/9_x.yml` がないなど） | `{ "field": "changes[0].address" }` |
| -32603 | InternalError | サーバーの不具合（`Cornix::Error` 以外の例外） | — |
| -32001 | ProfileNotFound | `profile` や `profileId` が分からない | `{ "profile": "ipad" }` |
| -32002 | ProtocolVersionMismatch | 約束の major の版が違う | `{ "supported": ["0.1"] }` |
| -32003 | NotSupported | capabilities にない機能を呼んだ | `{ "capability": "semanticValidation" }` |
| -32010 | VersionConflict | `baseVersions` が今のファイルと違う | `{ "files": { "layers/0_base.yml": "sha256:e1d4…" } }`（今の版） |
| -32011 | EditNotLocal | 値の部分だけでは書き換えられない | `{ "address": { … }, "reason": "multiline" }` |

- プロファイルが構造検証で読めないこと・値が読めないことはエラーにしない。`status: "invalid"` や `diagnostics` で返す
- `-32000`〜`-32099` は JSON-RPC が実装に任せている範囲。`-32010` 台は保存まわりに使う

## 8. 差し替えとテスト

### 8.1 TypeScript 版に差し替えるときの決まり

- 約束に出す名前（`kind`、`category`、`context`、メソッド名）は文字列の列挙で、Ruby のクラス名や定数名と結び付けない
- 候補・表示の文字・説明は `data/*.yaml` から作る（[ADR 004](adr.md)）。TypeScript 版も同じ `data/` を読む。
  `MO(n)` など関数形式の一覧は `KeycodeCodec` の定数にあるので、B 案の前に `data/` へ出す（[roadmap.md](roadmap.md)）
- TypeScript 版は意味検証をしない（`capabilities.semanticValidation: false`）。`profile/validate` は構造の問題だけを返す
- 拡張は `initialize` の `capabilities` だけを見て振る舞いを変え、`serverInfo.implementation` で分岐しない

### 8.2 適合テスト

約束のテストは「リクエストと期待する応答」の組をデータで書き（置き場所の案: `spec/fixtures/protocol/`）、
Ruby の RSpec と、将来の TypeScript の vitest の両方から同じデータを読んで確かめる。
`keycode/candidates` の「この入力ならこの候補」もここに書く。応答の比べ方は、順序に意味のある配列（候補の並び）は順序ごと、
それ以外の Hash は書いた項目だけを比べる（版の文字列などは比べない）。

### 8.3 Ruby 側の置き場所（案）

[architecture.md](../architecture.md) の層と依存の向きを守る。

| 層 | 置くもの |
|---|---|
| Interface | `Interface::EditorServer`（枠の読み書き、JSON-RPC の振り分け、エラーの code への変換。`Interface::Mcp` の標準入出力の扱いを参考に）と `cornix serve` のコマンド |
| Application | ユースケース（プロファイルを読む、候補を引く、表記を解釈する、変更を当てて検証する、書き換えを作る）。Interface からはこれだけを呼ぶ |
| Mapping | 候補の表と並べ方、表示の文字（`data/*.yaml` から） |
| Storage | YAML のノードの位置（行と列）、値の部分だけの書き換え（`ConfigEditor#update_fields` を入れ子の値に広げる）、ファイルの中身を差し替えて読む口（保存前の検証用） |

## 判断が要るところ

決めてほしい点。各項目の **推奨** で書き進めてある。

1. **枠の形**: **LSP と同じ `Content-Length`**（`vscode-jsonrpc` がそのまま使え、将来の LSP の入口とも共通） / MCP と同じ 1 行 1 メッセージ（`Interface::Mcp` の読み書きをそのまま使える）
2. **サブコマンドの名前**: **`cornix serve`** / `cornix editor-server` / `cornix rpc`
3. **ファイルを書くのは誰か**: **サーバーは書き換えを返すだけで、拡張が `WorkspaceEdit` で当てて保存する**（テキストで同じファイルを開いていてもずれない。サーバーを差し替えても書き込みの扱いが変わらない） / サーバーが書く
4. **ファイルの見張り**: **拡張が見張ってサーバーに知らせる**（Ruby に gem が要らない。LSP と同じ） / サーバーが見張る
5. **値の部分だけでは書き換えられないとき**: **書かずにエラーにする**（コメントを壊さないことを優先。画面には「テキストで直してください」とファイルを開くボタン） / そのファイルだけ作り直す（いまの `update_fields` の逃げ道と同じ）
6. **構造検証で読めないプロファイルを開いたとき**: **エラーの一覧だけを出す**（Claude が書きかけのときは、直れば `profile/didChange` で描き直る） / 読めたファイルだけを描く
7. **割り当てを消す操作**: **v0.1 では入れず、`NoKey`（KC_NO）を選んでもらう**（行の削除は v0.2 の項目の削除と一緒に決める） / 空の値にする / 行を消す
8. **候補を絞る場所**: **打つたびにサーバーに聞く**（並べ方がサーバー 1 か所に集まり、適合テストで両方の実装を縛れる） / 最初に全部もらって画面で絞る

約束の外だが、作る前に決めたいこと:

- **未保存の表示と元に戻すの仕組み**: VS Code が dirty の印・元に戻す・Ctrl+S を面倒みるのはカスタムエディタ（`CustomEditorProvider`）の画面で、
  ふつうの Webview パネル（`WebviewPanel`）では自前で作ることになる（と理解している。v0.1 の 7 で試して確かめる）。
  ADR 001 はカスタムエディタを「1 ファイルに 1 画面」として退けたが、プロファイルを 1 つの仮想ドキュメント（例: `cornix-profile:` のスキーム）に見立てれば、
  プロファイル丸ごとの画面のままカスタムエディタに乗せられる。そうすると Change の並びが VS Code の編集の履歴になる。
  ADR 001 / 005 / 008 に関わるので、どちらで作るかを決めたい

## v0.1 に入れないもの

- compile / validate / status をエディタから実行するコマンド（v0.1 の後半で `command/compile` などとして足す。status は読むだけ）
- マクロ・タップダンス・コンボ・ショートカットの中身の画面と、その `context`（v0.2）
- 項目の追加・削除・名前の変更（v0.2。名前の変更は `cornix rename`）
- 注記の編集（v0.2。`Change` の `address` に `note` を指す道筋を足す）
- 実機への書き込み（入れない。[ADR 014](adr.md)）
