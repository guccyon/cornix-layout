# v0.4 の作業の分け方と契約

[roadmap.md](roadmap.md) の v0.4（「実機への反映を画面から行える」）を、責務の境界で分けた作業にしたもの。
進め方の共通ルールは [tasks.md](tasks.md) の「共通ルール」と [tasks-v0.3.md](tasks-v0.3.md) と同じ（同じ段の作業は同じファイルを編集しない・契約を勝手に変えない・
作業ごとの PR は `feature/vscode-extension` 向け・版ができたら main への PR を 1 つ。main への PR は Tetsuro が .vsix で確かめてからマージする）。

2026-10-21 に v0.4 の範囲を「まず設計だけ」と決め、チャットでまとめを出して Tetsuro の OK をもらった（この文書と protocol.md の 14、ADR 018・019）。
2026-10-22 に Tetsuro の指示で実装を始めた（統合ブランチ `feature/vscode-extension` を main から作り直した）。同じ日に段 1・段 2（#94〜#97）を統合ブランチに入れ、段 3 に入った。
同じ日、Tetsuro が .vsix を見て画面と流れを変えた（下の「Tetsuro の確認で変えたこと」。ADR 020）。「決めたこと」と「画面」は最初の形のまま残し、変えたところはそちらに書く。

## 進み具合

| 段 | 作業 | PR | 状態 |
|---|---|---|---|
| 0 | 設計（この文書・protocol.md の 14・ADR・roadmap・spec） | — | 済み |
| — | K. 下の欄の「キー別」の並べ方とレイヤーの追加・削除（issue #84。実機とは別の作業。足しただけなので約束の版は `"0.3"` のまま） | — | 済み |
| 1 | P. 約束の型（`editors/vscode/src/deviceProtocol.ts`）と偽の device のサーバー | #94 | 済み |
| 2 | D1. device のサーバー（Ruby。`cornix serve --device`） | #97 | 済み |
| 2 | D2. 拡張のホスト（device のサーバーの起動・コマンド・確認のダイアログ・設定） | #96 | 済み |
| 2 | D3. 画面（違うキーの色・差分の一覧・「実機と同じ／違う」の印・ボタン） | #95 | 済み |
| 3 | J1. 版を上げる・通しの確認・統合テスト | #98 | 済み |
| 3 | J2. 文書（README・CHANGELOG・docs・知見） | #99 | 済み |
| 3 | T. Tetsuro の確認で変えたこと（節「デバイス転送」・反映のプレビューのモーダル・比べると戻すをやめる・検証のエラーで確定できない） | — | 作業中 |
| 3 | J. main への PR（Tetsuro の確認のあとマージ） | — | Tetsuro の確認待ち |

## v0.4 で入れるもの

| # | 中身 | 作業 |
|---|---|---|
| 1 | 「比べる」: 保存済みのプロファイルを compile し、実機を読んで差分を出す（読むだけ） | D1・D2・D3 |
| 2 | 「反映」: 差分を見せて確認のダイアログのあと書き込む（バックアップ → 書く → 読み直して検証） | D1・D2・D3 |
| 3 | 「戻す」: バックアップの一覧から選び（既定は最新）、反映と同じ流れで戻す | D1・D2 |
| 4 | 違うキーを図で色付けし、差分の一覧（キー・エンコーダ・マクロ・タップダンス・コンボ・設定）を出す | D3 |
| 5 | 「実機と同じ／違う N 件／未確認」の印（状態バーと図の上） | D2・D3 |
| 6 | 書き込みの許可の設定 `cornix.device.allowWrites`（既定は無効） | D2 |
| 7 | 実機が使えないとき（macOS 以外・ブリッジが未ビルド・つながっていない）の案内 | D1・D2 |
| 8 | 下の欄の「レイヤー別 / キー別」の切り替え（v0.3 の図の「全レイヤー」のトグルを置き換える）、レイヤーの追加・削除（[spec.md](spec.md) の「画面」、[protocol.md](protocol.md) の 14.9） | K |

入れないもの（[roadmap.md](roadmap.md) の「将来の拡張」へ）: 実機から取り込む（pull）、マトリクステスター、物理キーを押して割り当てる、マクロの記録、Key Override と Alt Repeat Key の編集。

## 決めたこと

2026-10-21 にチャットでまとめを出し、Tetsuro の OK をもらった。

1. **範囲**: 比べる（読むだけ）・反映・戻すの 3 つ。
   選ばなかった案: 実機から取り込む pull も入れる（decompile が設定を書き直すので、注記・コメント・未保存の変更との関係を決めるのが重い。次の版以降で考える）。
   マトリクステスターも v0.4 に入れる（期間が延びる。次の版の候補にする）
2. **仕組み**: 実機の操作は `cornix serve` とは別のプロセス（`cornix serve --device`。同じ枠の JSON-RPC で `device/*` のメソッドだけを持つ）で行う（ADR 018）。
   `cornix serve` はリクエストを届いた順に 1 つずつ処理するが、実機を全部読むと BLE で約 10 秒かかる（[device.md](../device.md)）。同じプロセスだとその間は候補や検証が止まる。
   選ばなかった案: 同じプロセスの中で別のスレッドにする（状態の共有と止め方が複雑になる）。拡張から CLI（`cornix apply`）を呼ぶ（y/N の確認を挟み、出力の文を読むことになる。ADR 003 にも反する）
3. **反映の流れ**: 未保存の変更があれば先に保存してもらう（保存しないなら止める）。そのあと
   compile → 実機を読んで差分（進み具合を出す）→ 違うキーを図に色付け・一覧に出す → 確認のダイアログ（件数と警告。モーダル）→
   token を付けて書き込みを頼む → サーバーが計画し直して token を確かめ → バックアップ → 書く → 読み直して検証。
   CLI・MCP の apply と同じ `Application::DeviceApply`（`expected_token`）を使う。差分がなければダイアログを出さずに「実機と同じです」と知らせる
4. **戻す**: `tmp/.../device_backups/` のバックアップの一覧から選ぶ（既定は最新。日時と、反映の前に取ったものかを添える）。そのあとは反映と同じ確認の流れ（`Application::DeviceRestore`）。
   戻す前にも今の状態をバックアップするので、続けてもう一度戻すと戻す前に戻る
5. **安全**（ADR 019）:
   - 書き込みは設定 `cornix.device.allowWrites` が `true` のときだけ。既定は `false`。`false` のまま「反映」「戻す」を押すと、設定を開くボタン付きで案内する（「比べる」はいつでも使える）
   - 拡張は `allowWrites` が `true` のときだけ device のサーバーを `--allow-writes` 付きで起動する。付けずに起動したサーバーは書き込みのメソッドを `-32074` で断る（拡張の不具合や偽の操作でも書かない二重の止め）
   - 毎回の確認のダイアログは省けない（「次から聞かない」は付けない）
   - テストはすべて偽の実機（`spec/device/fake_rmk_device.rb` と、拡張の偽の device のサーバー）で行う。統合テストも本物のブリッジは起動しない
   - boot 系のキーコードの拒否・送信の許可リスト・範囲の検査は今の `Device` 層のまま（[device.md](../device.md) の「安全設計」）
6. **「実機と同じ／違う」の印**: 自動では読まない（10 秒かかり、BLE もふさぐため）。「比べる」と反映・戻すのあとだけ更新し、保存したら「未確認」に戻す。
   選ばなかった案: 開いたときと保存したときに自動で比べる
7. **実機が使えないとき**: ボタンは出し、押したら理由と直し方を出す（macOS 以外 → 使えない、ブリッジが未ビルド → ビルドの手順、つながっていない → つないでからもう一度）。
   選ばなかった案: 使えないときはボタンを隠す（なぜ出ないのかが分からない）

## 画面

- 図の上（「位置の名前」の並び。「全レイヤー」のトグルは K でやめた）に「比べる」「反映」「戻す」のボタンと、印「実機: 同じ／違う N 件／未確認」を置く。状態バーにも同じ印（押すと「比べる」）
- 比べたあと、違うキー（今のレイヤーで、そのレイヤーの値が実機と違う位置）を橙の枠（`--vscode-charts-orange`）で囲む。ほかのレイヤーに違いがあればレイヤーのタブに点を付ける
- 差分の一覧は図の下に畳める節「実機との差分」として出す。行は「場所: 実機の値 → このプロファイルの値」（キーは `レイヤー名 / 位置の名前`、値は表記）。行を押すと該当の欄へ移る
- 進み具合: 読む・書く・読み直すの段階と件数を、VS Code の通知の進み具合（`withProgress`）に出す。読む間は取り消せる（書き始めたら取り消せない）
- 結果: 反映のあとは「N 件を書き込みました（バックアップ: …）」。読み直しで違いが残ったら警告にして、残った行を一覧に出す。途中で切れたら、書いた件数とバックアップの場所を出し、もう一度反映すれば続きからそろうことを伝える

## Tetsuro の確認で変えたこと（2026-10-22。ADR 020）

.vsix を見た Tetsuro の指摘: 図の上の「比べる」「反映」「戻す」と印がごちゃごちゃする。反映はしょっちゅう使わないので、編集フォームの一番下の節に押し込めばよい。
比べるのは反映の前に違いを見るためだけで、プレビューを見て最後に「確定」を押せばよい。戻すはエディタの Undo や git で設定ファイルを戻して反映し直せば足りる
（バックアップから戻すなら、コンパイル済みのデータからより設定ファイルで確かめながら戻したい）。反映の最中にソースを変えさせたくないので、プレビューはモーダルにして確定かやめるまで編集できなくする。
検証のエラーがあるときは確定を押せなくする。

- 入口: 編集フォームの一番下の畳める節「デバイス転送」の「反映のプレビュー…」と、コマンド「Cornix: 実機に反映…」だけ。コマンド「実機と比べる」「実機をバックアップから戻す」と状態バーの印はやめた
- 流れ: 保存を促す → 実機を読む（モーダルに進み具合と「やめる」）→ プレビュー（モーダルに図・タブの件数・一覧・警告、「確定」「やめる」）→ 確定で `device/apply`（プレビューの token）→ 結果を通知に出してモーダルを閉じる。
  決めたこと 3 の確認のダイアログ（VS Code のモーダル）はプレビューの「確定」に置き換えた（決めたこと 5 の「毎回の確認」は、毎回プレビューを通ることで守る）
- 確定を押せないとき: 書き込みを許していない（決めたこと 5。プレビューはできる）、検証のエラーがある（画面とホストの両方で止める）、プレビューのあとで設定ファイルが変わった（「もう一度比べる」）
- 決めたこと 4（戻す）と 6（「実機と同じ／違う」の印）はやめた。device のサーバーの `device/backups`・`device/compareBackup`・`device/restore` は約束に残す（拡張からは使わない。CLI の `cornix restore` と同じ中身）
- 別のマシンで変えた実機の内容と比べて、違いを選んでプロファイルに取り込む使い方は、リストアではなくマージに近いので次の版以降の候補にした（roadmap.md）
- 状態は `DeviceViewState` を `{ transfer, busyElsewhere, allowWrites }` にし、`transfer` は `reading` / `preview` / `writing` のどれか（webviewMessages.ts）。画面からの操作は `preview` / `confirm` / `cancel` / `openSettings`

## 約束（protocol.md）に足すもの

[protocol.md](protocol.md) の「14. v0.4 で足すもの」に書いた。形の見通し:

- `cornix serve --device [--allow-writes]`: device のサーバー。`initialize` は同じ（`capabilities.device: true`、`capabilities.deviceWrites`）
- `device/compare`（読むだけ）・`device/apply`・`device/backups`・`device/compareBackup`（読むだけ）・`device/restore`
- `device/progress` の通知（サーバー → 拡張）
- エラー `-32070` DeviceUnavailable・`-32071` PlanChanged・`-32072` WriteIncomplete・`-32073` PlanRejected・`-32074` WritesNotAllowed・`-32075` CompileFailed

## 段 1（直列）

### P. 約束の型と入れ物

`editors/vscode/src/deviceProtocol.ts`（14 の型）、偽の device のサーバー（`editors/vscode/test/fake-device-server/`。
`test/fake-server/cornix serve --device` で起動する。状態は環境変数 `CORNIX_FAKE_DEVICE` と通知 `$/fake/configure`）、
`spec/fixtures/protocol/device/` のデータの形（protocol.md の 14.10。データそのものは D1 が書く）。

P で約束に足したもの: `DeviceChange.key`（論理位置 hand / row / col。図と欄は位置をこれで引く）、`DeviceBackup.kind`（一覧に出す種類は
`pre-apply`・`pre-restore`・`backup`・`legacy`）、`changes` の並び。
ホストと画面の間のメッセージ（`webviewMessages.ts`）も P で決めた: ホスト → 画面 `{ type: 'device', state: DeviceViewState }`（状態・違い・操作中・書き込みの許可）、
画面 → ホスト `{ type: 'deviceAction', action: 'compare' | 'apply' | 'restore' }`。D2 が送り・受け、D3 が描き・押す。

## 段 2（並列）

### D1. device のサーバー（Ruby）

`Interface::EditorServer` の枠と振り分けを使い、`--device` のときは `device/*` だけを登録する（`Interface::EditorServer::DeviceHandlers` など）。
中身は今のユースケース（`DeviceDiff` / `DeviceApply` / `DeviceRestore` / `ListBackups`）と `Compile` を呼び、変更を位置（レイヤー・位置の名前）に直すのは
Application の新しい結果オブジェクト（`Application::Editor::DeviceChanges` など。マトリクスの座標 → 位置は `Domain::PositionMap`）。
進み具合は `Device::Reader` / `Writer` に省略可能なコールバックを足して通知に流す。取り消しは読む間だけ受け付ける。
適合テストは `spec/fixtures/protocol/device/` を FakeRmkDevice（`Environment.new(device_opener: ...)`）で流す。

### D2. 拡張のホスト

device のサーバーの起動（必要になったときに起動し、使い終わっても残す。`allowWrites` が変わったら起動し直す）、コマンド（「Cornix: 実機と比べる／反映／戻す」）、
未保存の変更の保存の促し、確認のダイアログ（件数・警告・書き込み先のキーボード名）、バックアップの選択（QuickPick）、`withProgress`、状態バー、設定 `cornix.device.allowWrites`。

### D3. 画面

ボタンと印、違うキーの橙の枠、レイヤーのタブの点、「実機との差分」の節、行から欄へ移る動き。Webview とホストの間のメッセージを足す（`webviewMessages.ts`）。

## 段 2 の PR で決めたこと

上の「決めたこと」と「画面」の曖昧なところを、各 PR が次のように決めた（約束に足したものは protocol.md の 14 にも書いた）。

### P（#94）

- 上の「P. 約束の型と入れ物」に書いたもの（`DeviceChange.key`・`DeviceBackup.kind`・`changes` の並び、ホストと画面の間のメッセージ）
- 偽の device のサーバーは compile しない。実機とプロファイルを「場所 → 値の表記」の表としてプロセスの中に持ち、反映すると実機の表がプロファイルの表になる（ファイルには書かない）

### D3（#95）

- 違うキーは橙の枠を `::after` で重ねる（キーの要素は `overflow: hidden` なので `outline` だと欠ける）。エンコーダは円全体ではなく、違う帯（左回し・押し込み・右回し）だけを囲む
- `allowWrites` が `false` でも「反映」「戻す」は出し、枠を破線にする（押すとホストが案内する）。操作の最中はボタンを押せなくし、何をしているかを印に出す

### D2（#96）

- 子プロセスの起動・つなぎ方・落ちたときの再起動は `src/server/serverProcess.ts` にまとめ、編集のサーバーと device のサーバーで共通にした
- 反映は、比べた直後でも毎回比べ直してから確認のモーダルを出す（ボタンは「N 件を書き込む」。「次から聞かない」は付けない）
- 取り消しは読む間だけ。`withProgress` の `cancellable` はあとから変えられないので、自前の `CancellationTokenSource` を挟み、書き始めたら取り消しをサーバーへ渡さない
- 比べたときの設定ファイルの版と今の版が違えば「未確認」に戻す。戻すのあとは「未確認」
- 設定（`cornix.device.allowWrites`・`cornix.path`）が変わったら device のサーバーは止めるだけで、次のリクエストで起動し直す
- ブリッジがないときの案内は `xcode-select --install` と、手でビルドするなら `swiftc -O ext/cornix_hid/main.swift -o tmp/cornix-hid`

### D1（#97）

- `Interface::EditorServer::Handler` に `servers`（`:editor` / `:device`）を持たせ、`--device` のときは `device/*` だけを登録する。中身は `Application::Editor::DeviceOperations`、変更を位置に直すのは `Application::Editor::DeviceChanges`
- 実機の失敗を型で分ける（`Cornix::DeviceUnavailable`（`reason`）・`WriteIncomplete`・`PlanChanged`・`PlanRejected`）。`Device::Reader` / `Writer` に進み具合のコールバックを足した
- 取り消しはスレッドを使わず、進み具合を送るたびに標準入力を待たずに読んで拾う
- バックアップの名前は同じ秒に重なると `-2` などの連番を付ける
- 偽の実機は `spec/device/fake_cornix_device.rb`、適合テストは `spec/fixtures/protocol/device/`（42 件。protocol.md の 14.10）

## 段 3

- J1: 約束の版を `"0.4"`、拡張の版を `0.4.0` に。通しの確認（偽の実機で比べる → 反映 → 戻す）。統合テストの追加
- J2: README（英日）・CHANGELOG・spec.md・roadmap.md（v0.4 を済みに）・device.md（拡張からの入口）・`.claude/memories/`
- J: `.vsix` を作り、main への PR。Tetsuro の確認を待つ（実機での確認は Tetsuro が行う。こちらからは書き込まない）
