# 変更履歴

このプロジェクトの主な変更を記録します。書式は [Keep a Changelog](https://keepachangelog.com/ja/1.1.0/) に、
バージョンの付け方は [Semantic Versioning](https://semver.org/lang/ja/) に従います。
バージョンは `lib/cornix/version.rb` の `Cornix::VERSION` で、`cornix --version` で表示できます。

## [Unreleased]

### 追加

- VS Code 拡張 v0.1（`editors/vscode/`）。プロファイル丸ごとを 1 画面で編集する。Marketplace には出していない。.vsix を作って手元で入れる（手順は `editors/vscode/README.md`）
  - 上にキーボード図、下にレイヤーごとの欄を出す。図では修飾キーを記号で、Mod-Tap とレイヤー操作を下の帯で、タップダンスを割り当てた動作ごとに分けた枠で描き、マクロに `M`・自分のショートカットに `★` の印、同梱のショートカットにアプリのアイコンを付ける
  - キー入力欄では、名前・別名・QMK 名・同梱のショートカットの日本語ラベルとアプリ名で候補を引く。入れたその場で検証し、マウスを載せると中身と QMK のキーコードを表示する
  - 保存（Cmd+S）は変えた値の部分だけを書き換え、コメントや並びを保つ。Claude などが外でファイルを変えたら、未保存の変更がなければ読み直し、あればどちらを残すか聞く
  - QMK 設定（説明と既定値付き）とメタデータを表示する。キーボードへの書き込みは拡張からはしない
- VS Code 拡張 v0.2。すべての設定ファイルを画面だけで編集できる
  - 下のペインにマクロ（手順の追加・削除・並べ替え、`delay` / `text`、`preset`）・タップダンス（4 つの動作、`tapping_term`）・コンボ（同時に押すキーと出すキー）・ショートカットの節を足した
  - マクロ・タップダンス・コンボ・ショートカットの追加・削除・名前の変更と、レイヤーの名前の変更。確認のダイアログのあとすぐファイルに書く。名前の変更は全ファイルの参照とファイル名も書き換え、compile の結果が変わるときは止める。削除は参照の数を見せ、参照している側にエラーを出す
  - レイヤーの欄の割り当てを消す操作（YAML の行を消す）と、注記（`{ key:, note: }` の note）の欄。タップダンスの動作とコンボの出すキーにも注記の欄
  - 図で割り当ての代わりに位置の名前（`position_map.yaml` の名前）を紫で見せる切り替え（ボタンと Alt）と、位置の名前の変更（全レイヤーの `mapping` のキーもまとめて書き換える）。マクロの `M` の印は橙にした
  - `KC_TRNS` のキーにレイヤー 0 の同じ位置のキーを薄く出す。修飾キー式・`LT`・Mod-Tap の組み立て欄
  - 設定ファイルをテキストで開いたときに、同じ検証の結果を波線で出す
- `cornix serve [--root DIR]`: VS Code 拡張と JSON-RPC（標準入出力）で話すサーバー。約束は `docs/vscode-extension/protocol.md`。
  約束の版 0.2 で、`profile/open` がマクロ・タップダンス・コンボ・ショートカットの中身を返し、変更（Change）に行の削除・並びへの挿入と移動・注記を足し、
  項目の追加・削除・名前の変更を返す `profile/planItemEdit` を足した（どれもファイルは書かず、書き換えを返す）
- 別名 `Vol+` / `Vol-`（音量）、`←` `↓` `→` `↑`（矢印キー）、`SingleQuote`（`'`）、`◀◀`（巻き戻し）、`▶︎▶︎` / `▶▶`（早送り）、`⏯`（再生 / 一時停止）。`Ctrl + Vol+` のように修飾キー式のキーにも書ける

### 変更

- 音量のキーの正規名を `VolumeUp` / `VolumeDown` から `Vol+` / `Vol-` にした。decompile はこの名前で書き、VS Code 拡張の図もこの名前を出す（`VolumeUp` / `VolumeDown` はこれまでどおり読める）
- `cornix compile` は、レイヤーのファイルに書いていない（割り当てのない）位置を `-1` ではなく `KC_NO`（0）にする。
  `-1` だと `cornix device apply` がその位置を飛ばして前の値が残り、Vial での読み込みも失敗しうるため。
  キーのない枠（col 6 のエンコーダのプッシュ以外）と、ファイルのないレイヤーは今までどおり `-1`

## [1.0.0] - 2026-10-19

最初のリリースです。

### キーボードとの読み書き

- `cornix pull` / `status` / `apply` / `restore`: キーボードの設定を YAML に読み出し、差分を確かめ、差分だけを書き込み、バックアップから戻す（macOS、Bluetooth / USB）
- 書き込みの前に必ずバックアップを取り、書き込んだあとに読み直して確かめる。`QK_BOOT` など実機に書き込まないキーコード（`data/dangerous_keycodes.yaml`）が含まれていれば、書き込みをすべて止める
- `cornix device info` / `read` / `backup` / `diff` / `apply` / `restore`: ファイルを指定して読み書きする
- `cornix mcp`: MCP サーバーとして起動し、Claude などの AI アシスタントから読み書きできる（書き込みは dry run と確認トークンの 2 段階）

### 設定ファイル

- レイヤー・エンコーダ・マクロ・タップダンス・コンボ・QMK Settings を YAML で書く
- `cornix init` と `profiles/`・`.cornix.yml`、共通のオプション `--config` / `--profile` / `--root` で、設定ディレクトリを作って切り替える
- 修飾キー式（`Cmd + Q`）、別名（`Tab`, `!`）、名前での参照（`Macro('名前')` / `TapDance('名前')`）
- 名前付きショートカット `Shortcut('名前')` と、同梱の cornixhub のショートカット（`Shortcut('アプリ:カテゴリ:ラベル')`）。手順を `macros/` の `preset:` でマクロにできる
- 割り当てに注記を書ける（`{ key:, note: }`）
- cornixhub の Vial キー一覧にあるキーを名前で書ける（Cornix が対応していないとみられるキーは validate などで警告する）

### 検証と名前付け

- `cornix validate`: 構造検証と意味検証。問題は止まらずに集めて「ファイル: 位置: 内容」で表示する。Cornix が対応していないとみられるキーは警告する
- `cornix rename`: 設定ファイルに意味のある名前を付ける（Claude の提案を 1 件ずつ確かめる）。変更の前後で compile の結果が変わらないことを確かめる

### Vial との相互変換

- `cornix compile` / `decompile` / `cleanup`: `layout.vil` と YAML を変換する。decompile → compile で 16bit 値が元と一致する
- compile が書く `layout.vil` は Vial Web（vial-gui 0.7.5）で読める（Vial に名前のない値は `0xHHHH`）

[Unreleased]: https://github.com/guccyon/cornix-layout/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/guccyon/cornix-layout/releases/tag/v1.0.0
