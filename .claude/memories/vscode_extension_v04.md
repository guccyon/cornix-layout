# VS Code 拡張 v0.4 の作業の知見

v0.4 のうち issue #84（下の欄の「キー別」の並べ方・レイヤーの追加と削除・図の「全レイヤー」のトグルの廃止）と、
実機とつなぐ作業（P #94・D3 #95・D2 #96・D1 #97。下の「実機とつなぐ」）で分かったこと。
計画と各 PR で決めたことは docs/vscode-extension/tasks-v0.4.md（「段 2 の PR で決めたこと」）。v0.3 までの知見は [vscode_extension_v03.md](vscode_extension_v03.md)。

## 約束の版

- #84（`profile/planItemEdit` の `kind: "layer"` の `create` / `delete`）は足しただけなので、約束の版は `"0.3"` のまま（Tetsuro の指示。一度 `"0.4"` に上げたが戻した。
  0.4 の開発が進んでいるので、版はむやみに上げない。上げるとしてもリビジョンまで）。`"0.4"` に上げるのは device のサーバーを入れる段 3
- 上げるときに直す場所: `Handlers::Initialize::PROTOCOL_VERSION`、`editors/vscode/src/protocol.ts`、`spec/support/protocol_fixtures.rb` と
  `editors/vscode/test/unit/protocolFixtures.test.ts` の setup の initialize、`spec/fixtures/protocol/lifecycle/*.json`、
  `spec/interface/editor_server/` の各 spec と拡張の `fakeServer*.test.ts`・`connection.test.ts`（「新しい版だけのサーバー」のテストの版は今より新しくする）

## サーバー（Ruby）

- レイヤーのファイル名は `Storage::ConfigFiles.item_path`（decompile と同じ。`Layer N` は `layer`）。ほかの項目の `<番号>_<slug>` とは既定の名前の扱いが違う
- `YamlFile.dump` に同じ Hash を 2 か所で渡すと、YAML のアンカー（`&1` / `*1`）で書かれる。手ごとの空のグループは別々の Hash にする
- 削除の references は `Domain::Keycode.layer_index`（16bit 値の解釈。Raw のレイヤー操作は数えない。#83 の decompile と同じ）
- 適合テストのデータの `setup.files` の値を `null` にするとファイルを消せる（Ruby と拡張の両方の読み手に足した）。authors_config はレイヤーが 10 枚そろっているので、追加のデータは 1 枚消してから

- レイヤーの名前は重なってよい（authors の 5〜9 はどれも Empty）。名前で探すと最初のもの（5）が消えた不具合があり、`delete`・`rename` に `file` を足してファイルのパスで探す
  （`Operation#find_item(kind, name, file:)`、重なりの検査は `taken_names` でレイヤーだけ外す）。Tetsuro の確認で見つかった。
  一度 `index` で探す形にしたが、Tetsuro の指摘で `file` に変えた: #85 で番号のない（null）・同じ名前のファイルが複数できうるので、一意なのはファイルのパスだけ。
  項目を指す約束を足すときは、名前・番号ではなくファイルのパスを使う。マクロ・タップダンス・コンボも #85 のときにそろえる
- 適合テストのデータの `setup.files` のパスはルートから（`profiles/default/layers/...`）。`layers/...` と書くと何も消えない

## 拡張

- キー別では、図の欄（`App#slots`。選んでいるレイヤー）と下の欄（`editorSlots`。全レイヤー）を分け、欄は `slotById`（id → Slot）で引く。
  レイヤーは `slotLayer`（KC_TRNS の説明のレイヤー 0 の値を引くのに使う）。ほかのレイヤーの行を選んだら、図では同じ位置のキーを選ぶ（`boardSlotFor`）
- キー別でレイヤーを選び直すときは下の欄を作り直さない（スクロールと打ちかけを残す）。並べ方を変えたときだけ作り直す
- 偽のサーバーの snapshot のレイヤーは fixtures の 2 枚だけだったので、ディスクにあるほかのレイヤーのファイル（拡張から足したもの）を name と index の行だけ読んで足した（統合テストで追加・削除を通すため）
- 「全レイヤー」のトグルをやめるとき、`model.ts` の `LayerLine` / `layerLineLabel`、`keyboardView.ts` の `layers` と CSS、`keyboardV03.test.ts` の節を消した

## コンテナで画面を見る

- Webview を Playwright で開いて見られる: `acquireVsCodeApi` の stub を置いた HTML から `out/webview.js` を読み、ready が来たら
  `fixtureSnapshot()`（test/unit/webview/fakeHost.ts を esbuild でまとめたもの）を postMessage する。`media/` を `out/` の隣に置く。
  VS Code の色の変数はないので色は確かめられないが、並びと折り返しは分かる。ブラウザは `/opt/pw-browsers/chromium`
- 実機の画面（D3）も同じやり方で見られる。Playwright は `/opt/node-tools/node_modules/playwright/index.mjs` を直接 import し、
  `PLAYWRIGHT_BROWSERS_PATH=/opt/pw-browsers` を付ける。実機の状態は `window.postMessage({ type: 'device', state })` で入れる

## 実機とつなぐ（v0.4 の段 1・段 2）

### 約束と偽のサーバー（P #94）

- ホストと画面の間は `{ type: 'device', state: DeviceViewState }`（ホスト → 画面）と `{ type: 'deviceAction', action }`（画面 → ホスト）だけ。画面は自分では比べない
- 偽の device のサーバーは `test/fake-server/cornix serve --device` で起動する（入口は偽のサーバーと同じ）。状態は環境変数 `CORNIX_FAKE_DEVICE` のシナリオと通知 `$/fake/configure`。
  compile しないので、Ruby の適合テストのデータ（`spec/fixtures/protocol/device/`）は流さない
- 偽の device のサーバーの `device/backups` は、Ruby と同じく実機が使えなくても一覧を返すようにそろえる（段 3 の J1）

### 画面（D3 #95）

- 違うキーの橙の枠は `::after` で重ねる。キーの要素は `overflow: hidden` なので、`outline` や子の要素だと欠ける
- エンコーダは円全体ではなく、違う帯（左回し・押し込み・右回し）だけを囲む（円全体だとどの操作が違うのか分からない）
- `allowWrites` が `false` でも「反映」「戻す」は隠さず破線にする（押すとホストが案内する。隠すと理由が分からない）

### ホスト（D2 #96）

- 子プロセスの管理は `src/server/serverProcess.ts` に出し、編集のサーバー（`cornixServer.ts`）と device のサーバー（`deviceServer.ts`）で共通にした
- vscode-jsonrpc の `sendRequest` に token を渡すと、取り消したときに `$/cancelRequest` を送り、サーバーの `-32800` を待って reject する。
  読む間だけ取り消せるようにするには、`withProgress` の token を直接渡さず、自前の `CancellationTokenSource` を挟んで読む間だけ転送する
- `withProgress` の `cancellable` はあとから変えられない（書き始めても取り消しのボタンは出たまま。押しても転送しない）
- vscode に依存するモジュールを import すると vitest で失敗する。流れ（`deviceFlow.ts`）・文（`deviceTexts.ts`）・状態（`deviceStates.ts`）・設定（`deviceSettings.ts`）は
  vscode に依存しないファイルに分け、`deviceController.ts` だけが vscode を使う
- 決めた細部: 反映は毎回比べ直してから確認のモーダル（「N 件を書き込む」。次から聞かないはなし）。比べたときの設定ファイルの版と違えば未確認に戻す。戻すのあとは未確認。
  設定が変わったら device のサーバーは止めるだけ（次のリクエストで起動し直す）。ブリッジの案内は `xcode-select --install` と `swiftc -O ext/cornix_hid/main.swift -o tmp/cornix-hid`

### サーバー（Ruby。D1 #97）

- `cornix serve --device [--allow-writes]`。`Interface::EditorServer::Handler` に `servers`（`:editor` / `:device`）を持たせて振り分ける。中身は `Application::Editor::DeviceOperations`、
  変更を位置に直すのは `DeviceChanges`。実機の失敗の型は `DeviceUnavailable`（`reason`）・`WriteIncomplete`・`PlanChanged`・`PlanRejected`（`lib/cornix/errors.rb`）
- 取り消しはスレッドを使わない。進み具合（`Device::Reader` / `Writer` の progress）を送るたびに、標準入力を待たずに読んで `$/cancelRequest` を拾う。
  読み取りのスレッドで拾う形にしたら、テストの StringIO と GVL のせいで結果が揺れた
- device の適合テストの token は、書き込む場所と目標の値だけで決まるので、データ（`spec/fixtures/protocol/device/`）にそのまま書ける。
  `spec/fixtures/test_config` を変えたら、これらのデータの token も直す
- バックアップの名前は、同じ秒に重なると `-2` などの連番が付く（テストで続けて取ると起きる）
- 偽の実機は `spec/device/fake_cornix_device.rb`（FakeRmkDevice を Cornix の大きさにし、`fail_write_after`・`ignore_writes`・`unavailable` を足したもの）
- コンテナでの rspec は `LANG=ja_JP.UTF-8 bundle exec ruby $(bundle info rspec-core --path)/exe/rspec`。spec/storage などで psych の違いによる失敗が出るが、
  ベースのブランチでも同じで CI では通る

## Tetsuro の確認で作り直した反映（ADR 020）

- 2026-10-22、.vsix を見た Tetsuro の指摘で、図の上の「比べる」「反映」「戻す」と印・状態バーをやめ、編集フォームの一番下の節「デバイス転送」と
  反映のプレビューのモーダル（確定 / やめる）にした。比べるは反映の前に見るだけ、戻すは Undo や git で設定を戻して反映し直せば足りる、という使い方の話
- 画面の上のボタンを増やす前に、その操作の頻度と、ほかの操作の一部で足りないかを聞くとよい（今回は 3 つのボタンが 1 つの流れにまとまった）
- 状態は `DeviceViewState = { transfer, busyElsewhere, allowWrites }`。`transfer` は `reading` / `preview` / `writing`。読む・書く進み具合は VS Code の通知ではなくモーダルに出す
- モーダルは `document.body` に置き、編集画面の `#app` に `inert` を付ける（モーダルを `#app` の中に置くと一緒に操作できなくなる）。
  モーダルの図は `KeyboardView` をもう 1 つ作って使い回す（作るたびに Alt の keydown の listener が増えるので、作るのは 1 回）
- 確定はプレビューの token のまま `device/apply`。プレビューのあとで snapshot の `files` が変わったら `stale`（読んでいる間に変わっても、読み終えたときに stale にする）。
  検証のエラー（snapshot の diagnostics の error、`invalid` は 1 件以上）があれば、画面は確定を押せなくし、ホストも止める
- 画面のモーダルを Playwright で見るとき、VS Code の色の変数がないと背景が透けるので、`var(--vscode-…, #252526)` のように最後の値を付けておく
