# Cornix Layout（VS Code 拡張）

cornix-layout のプロファイル（設定ディレクトリ）丸ごとを 1 画面で見て、候補から選びながら編集する VS Code 拡張。
v0.1 はレイヤーと QMK 設定、v0.2 はすべての設定ファイル（マクロ・タップダンス・コンボ・ショートカット・位置の名前、項目の追加・削除・名前の変更）を画面で編集できる。
v0.3 は使い勝手（コンボの強調・図からキーを選ぶ・あいまい検索・同梱のショートカットの選択とコピー・preset の展開・押せないコンボの印）。
v0.4 ではレイヤーの追加・削除、実機とつなぐ反映（編集フォームの一番下の節「デバイス転送」から、プレビューのモーダルで違いを見て「確定」）を入れた。
v0.5 では未使用の項目（`index:` のないファイル）の取り出しと未使用にする操作、番号の変更と入れ替え（レイヤーの「＋」と節の「追加」の一覧、見出しの「…」メニュー）を入れ、これらとショートカットの追加を未保存の変更に積むようにした（約束は protocol.md の 15）。
利用者向けの説明は [README.ja.md](../../README.ja.md) の「VS Code の画面で編集する」。
仕様・決定・約束は [docs/vscode-extension/](../../docs/vscode-extension/README.md)。

拡張は `cornix serve`（Ruby のサーバー）を子プロセスとして起動し、標準入出力の JSON-RPC（[protocol.md](../../docs/vscode-extension/protocol.md)）だけで話す。
`cornix` のほかのコマンドは直接叩かない（ADR 003）。実機の操作（v0.4）は別の子プロセス `cornix serve --device [--allow-writes]`（protocol.md の 14）と同じ形で話す（ADR 018）。
書き込みは設定 `cornix.device.allowWrites` が `true` のときだけ `--allow-writes` を付けて起動し、毎回確認のダイアログを出す（ADR 019）。テストはすべて偽の実機で、本物のブリッジは起動しない。

## 必要なもの

- Node.js 22（22.12 以上）か 24 と npm（CI は Node 24）。Node 25 では `npm ci` が vitest の engines（`^22.12 || ^24 || >=26`）に合わず警告（EBADENGINE）を出す（動きはする）。26 以上は警告なし
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
npm run test:integration:ruby  # 統合テストを本物のサーバー（このリポジトリの bin/cornix serve）で（PATH に Ruby が要る。suite/realServer.ts）
npm run package           # .vsix を作る（自分用。code --install-extension cornix-vscode-<版>.vsix で入れる。版は package.json の version）
```

### 動かしてみる

- `editors/vscode` を VS Code のフォルダとして開き、F5（実行とデバッグ）で次のどちらかを選ぶ
  - 「拡張を動かす（偽のサーバー）」: `test/integration/workspace` を開く。`.vscode/settings.json` の `cornix.path` が偽のサーバーを指している
  - 「拡張を動かす（このリポジトリの bin/cornix）」: リポジトリのルートを開き、`bin/cornix serve` とつなぐ
- コマンドラインからなら `npm run build && code --extensionDevelopmentPath="$PWD" test/integration/workspace`
- 左のアクティビティバーの Cornix のアイコンでプロファイルの一覧、コマンドパレットの「Cornix: プロファイルを開く」で編集画面が開く。
  サーバーの標準エラー出力とやりとりの記録は出力パネルの「Cornix」

### 手元で入れて使う（.vsix）

Marketplace には出していないので、.vsix を作って自分の VS Code に入れる。

1. .vsix を作る: `cd editors/vscode && npm ci && npm run package`（`editors/vscode/` の中に `cornix-vscode-<版>.vsix` ができる。版は package.json の version）
2. 入れる: そのまま `editors/vscode/` の中で `code --install-extension cornix-vscode-<版>.vsix`（またはコマンドパレットの「Extensions: Install from VSIX...」）。
   入れ直すときも同じ（版が同じなら上書き）。外すときは `code --uninstall-extension guccyon.cornix-vscode`
3. プロファイルのあるフォルダを開く。たとえば authors-keymap の worktree（`.cornix.yml` に `profile: authors`）をフォルダとして開き、
   ワークスペースを信頼する（Restricted Mode では動かない）
4. 設定 `cornix.path` は、`cornix serve` のある `bin/cornix` を指す。`cornix serve` は main に入っているので、authors-keymap を main に rebase してあれば
   空のまま（開いたフォルダの `bin/cornix`、なければ `PATH` の `cornix`）でよい。開いたフォルダのブランチが古く `cornix serve` がないときは、
   main の worktree などの `bin/cornix` の絶対パスを入れる。ワークスペースの `.vscode/settings.json` に書くと、そのフォルダだけに効く

   ```jsonc
   { "cornix.path": "/path/to/cornix-layout/main/bin/cornix" }
   ```

5. アクティビティバーの Cornix のアイコンか、コマンドパレットの「Cornix: プロファイルを開く」で開く。保存は Ctrl+S（Cmd+S）。
   保存したら `bin/cornix validate` や `bin/cornix compile` は今までどおりターミナルで。実機に書き込むのは編集フォームの一番下の節「デバイス転送」か
   コマンド「Cornix: 実機に反映…」（プレビューで違いを見てから「確定」。書き込みは設定 `cornix.device.allowWrites` を有効にしたときだけ。macOS とブリッジ `tmp/cornix-hid` が要る）

起動できないとき（「cornix のサーバーを起動できませんでした」）は出力パネル「Cornix」を見る。
``undefined method `define' for Data:Class`` などが出ていれば、VS Code が古い Ruby（macOS の `/usr/bin/ruby` 2.6）で動かしている。
Dock から起動した VS Code はログインシェルから環境を読むので、mise や rbenv の Ruby が PATH の後ろに回ることがある。
そのときは使う Ruby を決めたスクリプトを作って `cornix.path` に指定する。

```sh
#!/bin/sh
# ~/bin/cornix-vscode（chmod +x する）
exec "$HOME/.local/share/mise/installs/ruby/latest/bin/ruby" /path/to/cornix-layout/main/bin/cornix "$@"
```

### 同梱する依存のライセンス

`out/extension.js` には実行時の依存（いまは `vscode-jsonrpc` だけ）が esbuild でまとめて入り、元のファイルの著作権表示は残らない。
そのライセンス文は `ThirdPartyNotices.txt` に写して .vsix に入れている（`.vscodeignore` の `!ThirdPartyNotices.txt`）。
`dependencies` を足したり版を上げたりしたら、`node_modules/<パッケージ>/` のライセンス文をここに足し、`npx vsce ls --no-dependencies` で入ることを確かめる。
devDependencies（ビルドとテストの道具）は .vsix に入らないので要らない。アイコンの素材は `media/icons/NOTICE.md`

### 設定

| 設定 | 既定 | 中身 |
|---|---|---|
| `cornix.path` | 空 | `cornix` の場所。空ならワークスペースの `bin/cornix`、なければ `PATH`。名前だけ（`cornix`）なら `PATH` から、相対パスはワークスペースのフォルダから。見つからなければ設定を開くボタン付きで知らせる。変えると起動し直す |
| `cornix.trace.server` | `off` | `messages` / `verbose` にすると、サーバーとのやりとりを出力パネル「Cornix」に書く |
| `cornix.device.allowWrites` | `false` | 実機への書き込み（反映・戻す）を許す。`true` のときだけ device のサーバーを `--allow-writes` 付きで起動する。変えると device のサーバーを止め、次の操作で起動し直す。`false` でも比べるは使える |

ワークスペースのコマンドを実行するので、信頼したワークスペースでだけ動く（Restricted Mode では無効）。

## 偽のサーバー（テスト用）

`test/fake-server/` は protocol.md の例を元にしたデータ（`fixtures.ts`。`spec/fixtures/authors_config` の Base と Symbols のレイヤーを写したもの）を、
`cornix serve` と同じ枠（`Content-Length`）と約束で返す Node のプログラム。Ruby のサーバーができる前に画面の作業を進めるのと、統合テストに使う。

- 起動: `test/fake-server/cornix serve --root <ワークスペース>`（先に `npm run build`）。設定 `cornix.path` にこのファイルを指定すると拡張がつなぐ
- ライフサイクルとエラーは Ruby のサーバーに合わせてあり、vitest が `spec/fixtures/protocol/` の `lifecycle` と `profile_list` を偽のサーバーにも流して確かめる（`test/unit/protocolFixtures.test.ts`）
- `profile/list` はワークスペースの `profiles/`・`.cornix.yml`・`config/` を見て返す（Ruby と同じ並びと既定）。snapshot のレイヤーのキー・エンコーダと QMK 設定の値はディスクのファイルの `キー: 値` の行から読み、それ以外（表示の文字・候補など）は固定のデータ
- v0.2 の中身（マクロ・タップダンス・コンボ・ショートカット）は、ディスクのファイルの一覧と `name:` `index:` `description:` の行から作り、fixtures に同じファイル・同じ名前のものがあればその中身を使う。手順などの中身はディスクから読まないので、書き換えたあとも snapshot の手順は fixtures のまま
- すべてのメソッドに答える。`profile/planEdits` はディスクのファイルの行を素朴にたどるだけ（ブロック形式の `キー: 値`。ない場所への挿入は -32061）で、Ruby の書き換えの代わりではない。v0.2 の `op` 付きの Change は `yamlLines.ts` で当てる（並びの Change があるファイルはファイル全体を 1 つの書き換えにする）
- `profile/planItemEdit` は追加・削除・名前の変更・位置の名前の変更に答える（レイヤーの追加・削除も。足したレイヤーのファイルは name と index の行だけ読んで snapshot に出す）。名前を `VerifyFail` か同梱の形（`アプリ:カテゴリ:ラベル`）のショートカットの名前に変えると -32061（`verify`）
- `profile/validate` は保存済みの問題に変更の問題を足す（読めない表記は構造の error だけ、`Macro(数字)` は定義のないマクロ、`MO(9)` はほかの項目にかかる問題の例）
- 開いたプロファイルごとに「知っている版」を持ち、`workspace/didChangeFiles` と `profile/saved` で版が違えば `profile/didChange` を送る
- わざと崩す: `CORNIX_FAKE_SCENARIO=invalid`（構造検証で読めないプロファイル）、`CORNIX_FAKE_EXIT_ON=<メソッド>`（そのリクエストで落ちる。再起動の確認用）
- 動いている途中で変える: 通知 `$/fake/configure`（`{ scenario?: "default" | "invalid", delays?: { <メソッド>: ミリ秒 } }`。偽のサーバーだけのもの）。統合テストが保存の途中や読めない間を作るのに使う
- params の確かめ方と順（形 → -32060 → 宛先・値の型・baseVersions → -32061）は Ruby のサーバーに合わせ、`spec/fixtures/protocol/` の validate・planEdits・saved・planItemEdit は応答が error のデータを、didChangeFiles はすべてを流す
- 16bit 値や表示の文字はそれらしい値で、Ruby のサーバーの結果と一致するとは限らない。約束の形の正しさは Ruby の適合テスト（`spec/fixtures/protocol/`）が決める

## 偽の device のサーバー（テスト用）

`test/fake-device-server/server.ts` は device のサーバー（`cornix serve --device`。protocol.md の 14）の偽物。本物のキーボードもブリッジも使わない。
実機とプロファイルを「場所 → 値の表記」の表としてプロセスの中に持ち、違う場所を `DeviceChange` にして返す。反映すると実機の表がプロファイルの表になり、
戻すとバックアップの表になる（ファイルには書かない。プロファイルのファイルも読まないので、保存しても比べる結果は変わらない）。

- 起動: `test/fake-server/cornix serve --device --root <ワークスペース> [--allow-writes]`（偽のサーバーと同じ入口。`--device` のときこちらになる）。
  `cornix.path` に偽のサーバーを指定してあれば（`test/integration/workspace`）、拡張の反映のプレビューなどがこれとつながる
- 既定の違いは 6 件（`DEFAULT_DIFFERENCES`。偽のサーバーの Base / Symbols のレイヤーのキー 3 つ・左のエンコーダの左回し・マクロ・`tapping_term`）。プレビューのモーダルの図の枠と一覧を確かめられる
- シナリオは環境変数 `CORNIX_FAKE_DEVICE`（`scenarioConfig`）で選ぶ

  | シナリオ | 振る舞い |
  |---|---|
  | `default`（空） | 既定の違いがある |
  | `same` | 違いがない（プレビューは「実機はこのプロファイルと同じです」） |
  | `compileFailed` | `device/compare`・`device/apply` が `-32075` |
  | `rejected` | `QK_BOOT` を含む計画として `-32073` |
  | `writeFail` | 2 件書いたところで `-32072` |
  | `slow` | 進み具合の 1 歩を 200 ミリ秒にする（読む間の取り消しを試す） |
  | `unavailable:platform` / `bridge` / `notConnected` / `timeout` | どの `device/*` も `-32070`（その理由） |

  例: `CORNIX_FAKE_DEVICE=slow code --extensionDevelopmentPath="$PWD" test/integration/workspace`
- 動いている途中で変える: 通知 `$/fake/configure`（params は `FakeDeviceConfig`。`differences`・`unavailable`・`compileFailed`・`rejected`・`failWriteAfter`・`remaining`・`stepMs`・`warnings`。書いた項目だけ変わる）。単体テストと統合テストが使う
- `--allow-writes` なしなら `device/apply`・`device/restore` は `-32074`（本物と同じ）。token は計画の中身から作り、比べたあとに表が変われば `-32071`
- Ruby の適合テストのデータ（`spec/fixtures/protocol/device/`）は compile が要るので流さない。約束の形の正しさは Ruby の適合テストが決める

## 構成

```
editors/vscode/
  package.json            拡張の manifest（表示は日本語だけ）
  ThirdPartyNotices.txt   .vsix に入る依存（out/extension.js）のライセンス文
  esbuild.mjs             ビルド（out/ に出す）
  src/
    extension.ts          入口（コマンド・一覧・編集画面・設定の変更をつなぐ）
    protocol.ts           約束の型（protocol.md をそのまま TypeScript にしたもの。v0.2 の形は 12 節、v0.3 は 13 節。約束を変えたらここも変える）
    deviceProtocol.ts     device のサーバーとの約束の型（protocol.md の 14。型だけで、Webview と偽の device のサーバーからも読む）
    webviewMessages.ts    拡張と編集画面（Webview）の間のメッセージ（change・edit・itemEdit、snapshot と pending など。v0.4 の device（状態）と deviceAction（ボタン）、keyboard（KeyboardSpec））
    keyboard/             キーボード固有の情報（KeyboardSpec。ADR 026、docs/vscode-extension/keyboard-spec.md）
      spec.ts             型と純粋な関数（indexLimit・boardSize・rotationOrigin。Webview からも読む）
      cornix.ts           Cornix の値（区画・グループ・配置・個数・表示名。Webview は import しない）
      index.ts            プロファイルに使う spec を選ぶ（ホスト側。今は常に Cornix）
    server/
      locateCornix.ts     cornix の場所を決める（cornix.path → bin/cornix → PATH）
      connection.ts       JSON-RPC の接続（vscode-jsonrpc）、initialize・shutdown
      serverProcess.ts    子プロセスの起動・つなぎ方・標準エラー出力・落ちたときの再起動のボタン（編集のサーバーと device のサーバーで共通）
      cornixServer.ts     編集のサーバー（cornix serve）。メソッドの呼び口（planItemEdit も）
      deviceServer.ts     device のサーバー（cornix serve --device [--allow-writes]。最初の device/* で起動し、残す）
    device/               実機への反映（v0.4。プレビュー → 確定。ADR 020）
      deviceController.ts コマンド「実機に反映…」・保存の促し・通知・設定の変更（VS Code の部分）
      deviceFlow.ts       反映の流れ（保存の促し → 読む → プレビュー → 確定で書く、読む間だけの取り消し、検証のエラーなら実機を読む前に止める。vscode に依存しない）
      deviceStates.ts     反映の途中の状態（読む・プレビュー・書く。プレビューのあとで設定ファイルの版が変われば古い。vscode に依存しない）
      deviceTexts.ts      通知に出す文（結果・実機が使えないときの直し方。vscode に依存しない）
      deviceSettings.ts   設定 cornix.device.allowWrites と、device のサーバーの起動の引数（vscode に依存しない）
    profiles/
      openProfile.ts      コマンド「Cornix: プロファイルを開く」（1 つならそれを、複数なら QuickPick で選ぶ）
      profileItems.ts     profile/list の結果を一覧と QuickPick に並べる形にする（vscode に依存しない）
      profileTreeProvider.ts  アクティビティバーの「プロファイル」の一覧（ADR 008）
    editor/
      profileUri.ts       cornix-profile:/<名前>?dir=<dir> の仮想ドキュメントの URI（ADR 015）
      profileDocument.ts  1 つのプロファイル（snapshot と未保存の変更）。保存（6.2）・外での変更（7.3）・ホットエグジット・onchange の検証・項目の操作（12.5）
      pendingChanges.ts   未保存の変更（AnyChange の当てる順の 1 本の並び。並びの外の値は同じ場所で畳む。ADR 017）
      rebase.ts           外での変更の当て直し（7.3）と、場所・値の名前などの道具（vscode に依存しない）
      itemEdits.ts        項目の操作の確認のダイアログの文と、失敗の知らせの文（vscode に依存しない）
      textDiagnostics.ts  テキストで開いたときの波線（snapshot の diagnostics をファイルごとにする。vscode に依存しない）
      prompts.ts          保存・外での変更・項目の操作で利用者に聞くこと（統合テストが差し替える）
      profileFiles.ts     設定ディレクトリのファイルの場所と、テキストで開くこと
      profileWatcher.ts   設定ディレクトリの見張り → workspace/didChangeFiles
      profileEditorProvider.ts  カスタムエディタ（CustomEditorProvider）。画面への snapshot と pending、DiagnosticCollection（cornix）
      webviewRelay.ts     画面からのリクエストの中継（keycode/candidates・keycode/inspect・keycode/shortcutTree だけ。shortcutTree はプロファイルによらないので params を使わない）と「ファイルを開く」のパスの確かめ
    webview/              編集画面（素の TypeScript。上にキーボード図、下にレイヤーの欄と節）
      main.ts             入口（ホストとのメッセージをつなぐ。下のペインの節を sections に並べる）
      app.ts              画面の全体（レイヤーの選択・欄の選択を上下で共有、Change をホストに渡す。図からキーを選ぶ状態 pickKey）
      model.ts            レイヤーの欄と図に描くものを snapshot と未保存の変更から組み立てる（DOM に依存しない）
      dom.ts              DOM を作る小さな道具
      keyboardView.ts     キーボード図（配置は KeyboardSpec の keys / encoders から引く。Cornix の配置は keyboard/cornix.ts、図の大きさは keyboard/spec.ts の boardSize。2 役のキーは tap / hold を上下に、アイコン、印、位置の名前の表示、KC_TRNS の下のレイヤー 0 の値、コンボのボタン）
      comboHighlight.ts   コンボのトリガーのキーを今のレイヤーで割り当てた位置を探す（図の強調。DOM に依存しない）
      layerEditor.ts      レイヤーの欄（キー入力欄・注記の欄・割り当てを消す ✕・位置の名前の変更）
      keyInput.ts         キー入力欄（候補・typed・警告。どこも同じ部品。候補の params と組み立て欄のオプション）
      modifierBuilder.ts  修飾キー式・LT・Mod-Tap の組み立て欄（keycode/inspect で確かめてから入れる）
      itemList.ts         マクロ・タップダンス・コンボ・ショートカットの節の共通の部品（一覧と編集欄、追加・削除・名前の変更の入口）
      itemsModel.ts       節に描くものを snapshot と pending から組み立てる（並びの Change を当てる。DOM に依存しない）
      macroEditor.ts      マクロの節（手順の追加・削除・上下、手順のキー、delay・text、preset と手順に展開）
      presetPicker.ts     同梱のショートカットの木（アプリ → カテゴリ → ラベル）から選ぶ（マクロの preset、キー入力欄の「同梱から選ぶ…」、ショートカットの「同梱からコピー」）
      tapDanceEditor.ts   タップダンスの節（4 つの動作と注記、tapping_term）
      comboEditor.ts      コンボの節（同時に押すキー・出すキーと注記、図から選ぶ、押せないコンボの ⚠）
      shortcutEditor.ts   自分のショートカットの節（名前ごとの値、同梱からコピー）
      settingsEditor.ts   QMK 設定の欄（整数は数値、真偽値はチェックボックス。説明と既定値）
      metadataView.ts     metadata.yaml と position_map の表示（読むだけ）
      inspector.ts        keycode/inspect の結果のとっておき（同じ表記は 1 回だけ聞く）
      tooltip.ts          説明の吹き出し（マウスを載せた要素かフォーカスした要素の下に 1 つ）
      deviceView.ts       実機への反映（編集フォームの一番下の節「デバイス転送」、反映のプレビューのモーダル、違う欄・タブを探す関数）
      hostClient.ts       ホストへのリクエストの中継（keycode/candidates・keycode/inspect・keycode/shortcutTree）と、変更・項目の操作の送り口
      icons/              アイコン ID → 要素（manifest.ts は media/icons/extract.mjs が作る。badges.ts は自前のバッジ）
  media/                  画面の CSS（webview.css）と同梱のアイコン（SVG とライセンス表記。media/icons/NOTICE.md）
  resources/              アクティビティバーのアイコン
  test/
    unit/                 単体テスト（vitest）。webview/ は画面の部品（fakeHost.ts が偽のサーバーのデータで答える HostClient、itemFixtures.ts が中身の snapshot）
    fake-server/          偽のサーバー（cornix が入口、main.ts・server.ts が本体、fixtures.ts がデータ、yamlLines.ts が v0.2 の Change を当てる素朴な行の書き換え）。--device なら偽の device のサーバー
    fake-device-server/   偽の device のサーバー（server.ts。上の「偽の device のサーバー」）
    integration/          統合テスト（@vscode/test-electron）と、そのワークスペース（テストのときは一時ディレクトリに写して使う）。
                          suite/index.ts は偽のサーバー、suite/realServer.ts は本物のサーバー（spec/fixtures/authors_config を写して使う）、道具は suite/support.ts。
                          workspace/profiles/default にはレイヤーのほかマクロ・タップダンス・コンボ・shortcuts.yaml もある（偽のサーバーが一覧と名前を読む）
```

## 作りのメモ

- 編集画面はカスタムエディタ（ADR 015）。プロファイルを `cornix-profile:` の仮想ドキュメントに見立てるので、タブの題はプロファイルの名前になり、
  dirty の印・閉じるときの確認・ホットエグジットは VS Code が面倒をみる。画面の変更は `ProfileDocument#applyChange` に渡すと
  VS Code の編集の履歴に載り、元に戻す・やり直し（Webview にフォーカスがあるときの Ctrl+Z）も効く
- 保存・undo・外での変更・ホットエグジットの状態と遷移は下の「ProfileDocument の状態」
- 値を決めるたびに `profile/validate` を呼び、その結果を画面に送る snapshot の `diagnostics` に入れる（ほかの項目にかかる問題も参照している側の欄に出る）
- 画面へは snapshot と一緒に `pending`（未保存の変更の全部を当てる順に）を送る。`changes` は v0.1 と同じ（並びの外の割り当て・設定の `set` だけ）
- 項目の追加・削除・名前の変更（`ProfileDocument#applyItemEdit`）は未保存に積まない（ADR 016）。未保存の変更があれば先に保存を促し、`profile/planItemEdit` → 確認のダイアログ →
  1 つの `WorkspaceEdit`（`createFile` / `deleteFile` / `renameFile` と `replace`。改名は先に `renameFile` してから新しい名前に書き換えを当てる）→ 保存 → `profile/saved`
- テキストの波線は `profile/open` / `profile/saved` / `profile/didChange` の snapshot の `diagnostics` だけを出す（未保存の変更の検証の結果はファイルの位置と合わないので出さない）
- サーバーは最初のリクエストのときに起動する。落ちたら「再起動」のボタンを出し、再起動したら開いていたプロファイルは `profile/open` からやり直す
- 単体テストは vscode に依存しないもの（`locateCornix`・`connection`・`pendingChanges` など）だけ。vscode を使うものは統合テストで確かめる
  （vscode を import するモジュールを読むと vitest が失敗するので、実機の操作も流れ・文・状態は `src/device/` の別のファイルに分けた）
- 実機の操作（v0.4）: 画面のボタンもコマンドも `DeviceController` に来る。状態（`DeviceViewState`）はホストが持って画面と状態バーに送り、画面は自分では比べない（自動では読まない）。
  device のサーバーへの取り消しは、`withProgress` の token を直接渡さず自前の `CancellationTokenSource` を挟んで読む間だけ渡す（vscode-jsonrpc は token を渡すと `$/cancelRequest` を送り、`-32800` を待って reject する）

## ProfileDocument の状態（保存・undo・外での変更・ホットエグジット）

`src/editor/profileDocument.ts` が持つもの。方針は「利用者の変更を黙って捨てない」と「外での変更を黙って上書きしない」で、問いを閉じたときは変更を残す側に倒す。

| 持つもの | 中身 |
|---|---|
| `snapshot` | 画面の基準（未保存の変更はこれに対する差）。`baseVersions` はこの `files` から取る |
| `changes` | 未保存の変更（`PendingChanges`。当てる順の 1 本の並び。並びの外の値は同じ場所で畳み、snapshot の値と同じになれば外れる。並びの Change は足した順のまま） |
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
