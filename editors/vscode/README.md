# Cornix Layout（VS Code 拡張）

cornix-layout のプロファイル（設定ディレクトリ）丸ごとを 1 画面で見て、候補から選びながら編集する VS Code 拡張。作っている途中（v0.1）。
仕様・決定・約束は [docs/vscode-extension/](../../docs/vscode-extension/README.md)。

拡張は `cornix serve`（Ruby のサーバー）を子プロセスとして起動し、標準入出力の JSON-RPC（[protocol.md](../../docs/vscode-extension/protocol.md)）だけで話す。
`cornix` のほかのコマンドは直接叩かない（ADR 003）。キーボードの実機には触らない（ADR 014）。

## 必要なもの

- Node.js 24 以上と npm（CI は Node 24）
- VS Code 1.120 以上（CI は 1.120.0 と stable の両方で統合テストを動かす）。ワークスペースはフォルダを 1 つだけ開いたもの（マルチルートでは最初のフォルダを `--root` にする。v0.1 では対象外）
- 本物のサーバーで動かすときは、このリポジトリの Ruby の環境（`bundle install` 済み）。サーバーがなくても、テスト用の偽のサーバーで画面の作業ができる

## 開発の手順

```sh
cd editors/vscode
npm ci                    # 依存を入れる（package-lock.json のとおり）
npm run build             # out/ にビルド（拡張・Webview・偽のサーバー・統合テスト）
npm run watch             # 変わるたびにビルド
npm run typecheck         # 型検査（tsc --noEmit）
npm test                  # 単体テスト（vitest。VS Code なしで動く）
npm run test:integration  # 統合テスト（VS Code をダウンロードして .vscode-test/ に置き、その中で動かす。VSCODE_TEST_VERSION=1.120.0 で版を選べる）
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
| `cornix.path` | 空 | `cornix` の場所。空ならワークスペースの `bin/cornix`、なければ `PATH`。名前だけ（`cornix`）なら `PATH` から、相対パスはワークスペースのフォルダから。見つからなければ設定を開くボタン付きで知らせる。変えると起動し直す |
| `cornix.trace.server` | `off` | `messages` / `verbose` にすると、サーバーとのやりとりを出力パネル「Cornix」に書く |

ワークスペースのコマンドを実行するので、信頼したワークスペースでだけ動く（Restricted Mode では無効）。

## 偽のサーバー（テスト用）

`test/fake-server/` は protocol.md の例を元にしたデータ（`fixtures.ts`。`spec/fixtures/authors_config` の Base と Symbols のレイヤーを写したもの）を、
`cornix serve` と同じ枠（`Content-Length`）と約束で返す Node のプログラム。Ruby のサーバーができる前に画面の作業を進めるのと、統合テストに使う。

- 起動: `test/fake-server/cornix serve --root <ワークスペース>`（先に `npm run build`）。設定 `cornix.path` にこのファイルを指定すると拡張がつなぐ
- ライフサイクルとエラーは Ruby のサーバーに合わせてあり、vitest が `spec/fixtures/protocol/` の `lifecycle` と `profile_list` を偽のサーバーにも流して確かめる（`test/unit/protocolFixtures.test.ts`）
- `profile/list` はワークスペースの `profiles/`・`.cornix.yml`・`config/` を見て返す（Ruby と同じ並びと既定）。snapshot のレイヤーのキー・エンコーダと QMK 設定の値はディスクのファイルの `キー: 値` の行から読み、それ以外（表示の文字・候補など）は固定のデータ
- すべてのメソッドに答える。`profile/planEdits` はディスクのファイルの行を素朴にたどるだけ（ブロック形式の `キー: 値`。ない場所への挿入は -32061）で、Ruby の書き換えの代わりではない
- `profile/validate` は保存済みの問題に変更の問題を足す（読めない表記は構造の error だけ、`Macro(数字)` は定義のないマクロ、`MO(9)` はほかの項目にかかる問題の例）
- 開いたプロファイルごとに「知っている版」を持ち、`workspace/didChangeFiles` と `profile/saved` で版が違えば `profile/didChange` を送る
- わざと崩す: `CORNIX_FAKE_SCENARIO=invalid`（構造検証で読めないプロファイル）、`CORNIX_FAKE_EXIT_ON=<メソッド>`（そのリクエストで落ちる。再起動の確認用）
- 動いている途中で変える: 通知 `$/fake/configure`（`{ scenario?: "default" | "invalid", delays?: { <メソッド>: ミリ秒 } }`。偽のサーバーだけのもの）。統合テストが保存の途中や読めない間を作るのに使う
- params の確かめ方と順（形 → -32060 → 宛先・値の型・baseVersions → -32061）は Ruby のサーバーに合わせ、`spec/fixtures/protocol/` の validate・planEdits・saved は応答が error のデータを、didChangeFiles はすべてを流す
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
      profileDocument.ts  1 つのプロファイル（snapshot と未保存の変更）。保存（6.2）・外での変更（7.3）・ホットエグジット・onchange の検証
      rebase.ts           外での変更の当て直し（7.3）と、場所・値の名前などの道具（vscode に依存しない）
      prompts.ts          保存と外での変更で利用者に聞くこと（統合テストが差し替える）
      profileFiles.ts     設定ディレクトリのファイルの場所と、テキストで開くこと
      pendingChanges.ts   未保存の変更（同じ Address は最後の値だけ）
      profileWatcher.ts   設定ディレクトリの見張り → workspace/didChangeFiles
      profileEditorProvider.ts  カスタムエディタ（CustomEditorProvider）
      webviewRelay.ts     画面からのリクエストの中継（keycode/candidates・keycode/inspect だけ）と「ファイルを開く」のパスの確かめ
    webview/              編集画面（素の TypeScript。上にキーボード図、下にレイヤーの欄）
      main.ts             入口（ホストとのメッセージをつなぐ）
      app.ts              画面の全体（レイヤーの選択・欄の選択を上下で共有、Change をホストに渡す）
      cornixLayout.ts     Cornix の物理配置（論理位置 hand / row / col → 図の座標。ADR 009）
      keyboardView.ts     キーボード図（2 役のキーは tap / hold を上下に、アイコン、印）
      layerEditor.ts      レイヤーの欄
      keyInput.ts         キー入力欄（候補・typed・警告。どこも同じ部品）
      settingsEditor.ts   QMK 設定の欄（整数は数値、真偽値はチェックボックス。説明と既定値）
      metadataView.ts     metadata.yaml と position_map の表示（読むだけ）
      hostClient.ts       ホストへのリクエストの中継（keycode/candidates・keycode/inspect）
      icons/              アイコン ID → 要素（manifest.ts は media/icons/extract.mjs が作る）
  media/                  画面の CSS と同梱のアイコン（SVG とライセンス表記。media/icons/NOTICE.md）
  resources/              アクティビティバーのアイコン
  test/
    unit/                 単体テスト（vitest）
    fake-server/          偽のサーバー
    integration/          統合テスト（@vscode/test-electron）と、そのワークスペース（テストのときは一時ディレクトリに写して使う）
```

## 作りのメモ

- 編集画面はカスタムエディタ（ADR 015）。プロファイルを `cornix-profile:` の仮想ドキュメントに見立てるので、タブの題はプロファイルの名前になり、
  dirty の印・閉じるときの確認・ホットエグジットは VS Code が面倒をみる。画面の変更は `ProfileDocument#applyChange` に渡すと
  VS Code の編集の履歴に載り、元に戻す・やり直し（Webview にフォーカスがあるときの Ctrl+Z）も効く
- 保存・undo・外での変更・ホットエグジットの状態と遷移は下の「ProfileDocument の状態」
- 値を決めるたびに `profile/validate` を呼び、その結果を画面に送る snapshot の `diagnostics` に入れる（ほかの項目にかかる問題も参照している側の欄に出る）
- サーバーは最初のリクエストのときに起動する。落ちたら「再起動」のボタンを出し、再起動したら開いていたプロファイルは `profile/open` からやり直す
- 単体テストは vscode に依存しないもの（`locateCornix`・`connection`・`pendingChanges` など）だけ。vscode を使うものは統合テストで確かめる

## ProfileDocument の状態（保存・undo・外での変更・ホットエグジット）

`src/editor/profileDocument.ts` が持つもの。方針は「利用者の変更を黙って捨てない」と「外での変更を黙って上書きしない」で、問いを閉じたときは変更を残す側に倒す。

| 持つもの | 中身 |
|---|---|
| `snapshot` | 画面の基準（未保存の変更はこれに対する差）。`baseVersions` はこの `files` から取る |
| `changes` | 未保存の変更（Address ごとに最後の値。snapshot の値と同じになれば外れる） |
| `saving` / `deferred` | 保存の途中と、その間に届いた `profile/didChange` の snapshot（保存のあとに扱う） |
| `external` / `resolving` | どちらを残すか聞いている外での変更（聞いている間に次が来れば snapshot だけ新しくする）と、聞いている流れ |
| `changeBase` | 外の変更で読めなくなったときの、変更を作ったときの snapshot（読めるまで聞かずに待つ） |
| `waitingBackup` | ホットエグジットから戻したら読めなかったときの、バックアップの版と値（読めるまで待つ。もう一度バックアップするときも受け継ぐ） |
| `epoch` | 外の変更を取り込んだ回数（そのあとの undo の扱いを変える） |

遷移:

```
画面で値を決める ─ applyChange → changes に足す・VS Code の編集の履歴に載せる → profile/validate
   undo: 前の値に戻す。ただし前の値が snapshot の値で、そのあと外の変更を取り込んでいたら（epoch が変わった）今の snapshot の値に戻す

Ctrl+S ─ save
   止める（知らせて CancellationError、dirty のまま）: 読めない・聞いている途中・テキストで dirty・構造の error・-32060・-32061・
     場所の見つからない変更（もう一度聞いて、捨てるときだけ続ける）・ディスクか TextDocument の版が baseVersion と違う（当てる直前にも確かめる）
   当てて保存 → profile/saved → snapshot を差し替え、保存した場所は「今の画面の値」を新しい snapshot に当て直す
     → 残った変更があれば、VS Code が保存点を置いたあとに編集を 1 つ足して dirty に戻す
   -32060 で profile/didChange が来なければ profile/open で開き直して、外での変更と同じ扱い

profile/didChange（保存の途中なら deferred に溜めて保存のあと）
   変更がない → 黙って描き直す
   新しい snapshot が読めない → changeBase を覚えて読めない表示にし、聞かずに待つ
   waitingBackup がある → 読めるようになったので、バックアップの版と値で下の「聞く」へ（reason: backup）
   それ以外 → 聞く（chooseSide）
       画面の変更を残す（閉じたときも）→ rebaseChanges: そのまま当て直す / 同じ場所が外でも変わった → 項目ごとに選ばせる（閉じたら画面の値）/
         場所がない → 捨てるか選ばせる（閉じたら残し、保存のときにもう一度聞く）。聞いている間の revert・undo・入力は活かす
       外の変更を残す → 編集画面を前に出して VS Code の revert を通す（dirty を消す。聞いている間に来たいちばん新しい snapshot を使う）

ホットエグジット ─ backup: 変更・変更を作ったときの files・その場所の値（saved）を書く
   戻す: 読めない → waitingBackup で待つ / 変更が触るファイルの版が違う → 聞く（reason: backup）/ 同じ → そのまま

サーバーの再起動 ─ profile/open からやり直す。変更があって、版が違う・読めない・待っている・聞いている途中なら外での変更と同じ扱い
```
