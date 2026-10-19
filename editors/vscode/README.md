# Cornix Layout（VS Code 拡張）

cornix-layout のプロファイル（設定ディレクトリ）丸ごとを 1 画面で見て、候補から選びながら編集する VS Code 拡張。作っている途中（v0.1）。
仕様・決定・約束は [docs/vscode-extension/](../../docs/vscode-extension/README.md)。

拡張は `cornix serve`（Ruby のサーバー）を子プロセスとして起動し、標準入出力の JSON-RPC（[protocol.md](../../docs/vscode-extension/protocol.md)）だけで話す。
`cornix` のほかのコマンドは直接叩かない（ADR 003）。キーボードの実機には触らない（ADR 014）。

## 必要なもの

- Node.js 24 以上と npm（CI は Node 24）
- VS Code 1.120 以上
- 本物のサーバーで動かすときは、このリポジトリの Ruby の環境（`bundle install` 済み）。サーバーがなくても、テスト用の偽のサーバーで画面の作業ができる

## 開発の手順

```sh
cd editors/vscode
npm ci                    # 依存を入れる（package-lock.json のとおり）
npm run build             # out/ にビルド（拡張・Webview・偽のサーバー・統合テスト）
npm run watch             # 変わるたびにビルド
npm run typecheck         # 型検査（tsc --noEmit）
npm test                  # 単体テスト（vitest。VS Code なしで動く）
npm run test:integration  # 統合テスト（VS Code をダウンロードして .vscode-test/ に置き、その中で動かす）
npm run package           # .vsix を作る（自分用。code --install-extension cornix-vscode-0.1.0.vsix で入れる）
```

### 動かしてみる

- `editors/vscode` を VS Code のフォルダとして開き、F5（実行とデバッグ）で次のどちらかを選ぶ
  - 「拡張を動かす（偽のサーバー）」: `test/integration/workspace` を開く。`.vscode/settings.json` の `cornix.path` が偽のサーバーを指している
  - 「拡張を動かす（このリポジトリの bin/cornix）」: リポジトリのルートを開き、`bin/cornix serve` とつなぐ
- コマンドラインからなら `npm run build && code --extensionDevelopmentPath="$PWD" test/integration/workspace`
- 左のアクティビティバーの Cornix のアイコンでプロファイルの一覧、コマンドパレットの「Cornix: プロファイルを開く」で編集画面が開く。
  サーバーの標準エラー出力とやりとりの記録は出力パネルの「Cornix」

### 設定

| 設定 | 既定 | 中身 |
|---|---|---|
| `cornix.path` | 空 | `cornix` の場所。空ならワークスペースの `bin/cornix`、なければ `PATH`。相対パスはワークスペースのフォルダから。見つからなければ設定を開くボタン付きで知らせる |
| `cornix.trace.server` | `off` | `messages` / `verbose` にすると、サーバーとのやりとりを出力パネル「Cornix」に書く |

ワークスペースのコマンドを実行するので、信頼したワークスペースでだけ動く（Restricted Mode では無効）。

## 偽のサーバー（テスト用）

`test/fake-server/` は protocol.md の例を元にしたデータ（`fixtures.ts`。`spec/fixtures/authors_config` の Base と Symbols のレイヤーを写したもの）を、
`cornix serve` と同じ枠（`Content-Length`）と約束で返す Node のプログラム。Ruby のサーバーができる前に画面の作業を進めるのと、統合テストに使う。

- 起動: `test/fake-server/cornix serve --root <ワークスペース>`（先に `npm run build`）。設定 `cornix.path` にこのファイルを指定すると拡張がつなぐ
- すべてのメソッドに答える。`profile/planEdits` はディスクのファイルの行を素朴にたどるだけ（ブロック形式の `キー: 値`）で、Ruby の書き換えの代わりではない
- `workspace/didChangeFiles` で開いているプロファイルのファイルが来れば `profile/didChange` を返す
- わざと崩す: `CORNIX_FAKE_SCENARIO=invalid`（構造検証で読めないプロファイル）、`CORNIX_FAKE_EXIT_ON=<メソッド>`（そのリクエストで落ちる。再起動の確認用）
- 16bit 値や表示の文字はそれらしい値で、Ruby のサーバーの結果と一致するとは限らない。約束の形の正しさは Ruby の適合テスト（`spec/fixtures/protocol/`）が決める

## 構成

```
editors/vscode/
  package.json            拡張の manifest（表示は日本語だけ）
  esbuild.mjs             ビルド（out/ に出す）
  src/
    extension.ts          入口（コマンド・一覧・編集画面・設定の変更をつなぐ）
    protocol.ts           約束の型（protocol.md をそのまま TypeScript にしたもの。約束を変えたらここも変える）
    webviewMessages.ts    拡張と編集画面（Webview）の間のメッセージ
    server/
      locateCornix.ts     cornix の場所を決める（cornix.path → bin/cornix → PATH）
      connection.ts       JSON-RPC の接続（vscode-jsonrpc）、initialize・shutdown
      cornixServer.ts     子プロセスの起動・標準エラー出力・落ちたときの再起動のボタン
    profiles/             プロファイルの一覧（アクティビティバー）と「プロファイルを開く」
    editor/
      profileUri.ts       cornix-profile:/<名前>?dir=<dir> の仮想ドキュメントの URI（ADR 015）
      profileDocument.ts  1 つのプロファイル（snapshot と未保存の変更）。保存は段 3
      pendingChanges.ts   未保存の変更（同じ Address は最後の値だけ）
      profileWatcher.ts   設定ディレクトリの見張り → workspace/didChangeFiles
      profileEditorProvider.ts  カスタムエディタ（CustomEditorProvider）
    webview/              編集画面（今は profile/open の結果を JSON で見せる仮のもの）
  resources/              アクティビティバーのアイコン
  test/
    unit/                 単体テスト（vitest）
    fake-server/          偽のサーバー
    integration/          統合テスト（@vscode/test-electron）と、そのワークスペース
```

## 作りのメモ

- 編集画面はカスタムエディタ（ADR 015）。プロファイルを `cornix-profile:` の仮想ドキュメントに見立てるので、タブの題はプロファイルの名前になり、
  dirty の印・閉じるときの確認・ホットエグジットは VS Code が面倒をみる。画面の変更は `ProfileDocument#applyChange` に渡すと
  VS Code の編集の履歴に載り、元に戻す・やり直し（Webview にフォーカスがあるときの Ctrl+Z）も効く
- サーバーは最初のリクエストのときに起動する。落ちたら「再起動」のボタンを出し、再起動したら開いていたプロファイルは `profile/open` からやり直す
- 単体テストは vscode に依存しないもの（`locateCornix`・`connection`・`pendingChanges` など）だけ。vscode を使うものは統合テストで確かめる
