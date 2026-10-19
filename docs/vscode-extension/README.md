# VS Code 拡張

cornix-layout のプロファイル（設定ディレクトリ）丸ごとを 1 画面で構造化して見せ、補完つきで編集できる VS Code 拡張の設計文書。
仕様は 2026-10-19 の相談ですべて決まり、まず自分用の v0.1 から実装する。

| 文書 | 内容 |
|---|---|
| [spec.md](spec.md) | 背景と目標、仕様（画面・作り・アイコン・検証・範囲）、入力と補完 |
| [adr.md](adr.md) | 設計の決定（ADR 001〜014） |
| [roadmap.md](roadmap.md) | 版ごとの中身と終わったと言える条件、将来の拡張、v0.1 の進め方 |
| [protocol.md](protocol.md) | Ruby のバックエンドと拡張の間のリクエストの約束（v0.1） |
| [tasks.md](tasks.md) | v0.1 の作業の分け方（並列に進める単位）と、作業の間の契約 |

拡張のコードは `editors/vscode/`、バックエンドは `cornix` のサブコマンド（Interface 層の入口と Application 層のユースケース。
[architecture.md](../architecture.md) の層と依存の向きを守る）に置く予定。
