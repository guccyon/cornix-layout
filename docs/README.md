# 設計文書

cornix-layout の内部の設計と仕組みの文書。使い方は [README.ja.md](../README.ja.md)、開発のルールは [.claude/CLAUDE.md](../.claude/CLAUDE.md)。

| 文書 | 内容 |
|---|---|
| [background.md](background.md) | Cornix と Vial、解決したい問題、用語、layout.vil の構造 |
| [architecture.md](architecture.md) | 方針、レイヤーと依存の向き、データの流れ、コード規約 |
| [domain-model.md](domain-model.md) | Profile と値オブジェクト、Keycode と 16bit 値、座標系、意味検証、Profile ⇄ DeviceImage の対応、設定ファイルの形式 |
| [notation.md](notation.md) | キーコードの表記（修飾キー表現、Macro / TapDance の参照、名前付きショートカット） |
| [validation.md](validation.md) | 構造検証と意味検証 |
| [rename.md](rename.md) | `cornix rename` と `bin/rename_file` |
| [cli.md](cli.md) | サブコマンドの体系と、cornix 自体の場所を通す `cornix self`（設計。issue #59） |
| [device.md](device.md) | キーボードの直接操作（`cornix device`）と MCP サーバー・VS Code 拡張からの入口（`cornix serve --device`）、RMK 0.8 の挙動と安全設計 |
| [vscode-extension/](vscode-extension/README.md) | VS Code 拡張の仕様・ADR・ロードマップと、バックエンドとのリクエストの約束（v0.1〜v0.4。v0.4 は実機と比べる・反映・戻す） |
| [tasks.md](tasks.md) | 主なクラスの公開メソッド（契約）とリファクタの経緯 |
