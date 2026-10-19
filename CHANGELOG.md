# 変更履歴

このプロジェクトの主な変更を記録します。書式は [Keep a Changelog](https://keepachangelog.com/ja/1.1.0/) に、
バージョンの付け方は [Semantic Versioning](https://semver.org/lang/ja/) に従います。
バージョンは `lib/cornix/version.rb` の `Cornix::VERSION` で、`cornix --version` で表示できます。

## [Unreleased]

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
