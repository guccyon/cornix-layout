# v0.4 の作業の分け方と契約

[roadmap.md](roadmap.md) の v0.4（「実機への反映を画面から行える」）を、責務の境界で分けた作業にしたもの。
進め方の共通ルールは [tasks.md](tasks.md) の「共通ルール」と [tasks-v0.3.md](tasks-v0.3.md) と同じ（同じ段の作業は同じファイルを編集しない・契約を勝手に変えない・
作業ごとの PR は `feature/vscode-extension` 向け・版ができたら main への PR を 1 つ。main への PR は Tetsuro が .vsix で確かめてからマージする）。

2026-10-21 に v0.4 の範囲を「まず設計だけ」と決め、チャットでまとめを出して Tetsuro の OK をもらった（この文書と protocol.md の 14、ADR 018・019）。
実装はまだ始めていない。

## 進み具合

| 段 | 作業 | PR | 状態 |
|---|---|---|---|
| 0 | 設計（この文書・protocol.md の 14・ADR・roadmap・spec） | — | 済み |
| 1 | P. 約束の型（`editors/vscode/src/deviceProtocol.ts`）と偽の実機のサーバーの入れ物 | — | これから |
| 2 | D1. device のサーバー（Ruby。`cornix serve --device`） | — | これから |
| 2 | D2. 拡張のホスト（device のサーバーの起動・コマンド・確認のダイアログ・設定） | — | これから |
| 2 | D3. 画面（違うキーの色・差分の一覧・「実機と同じ／違う」の印・ボタン） | — | これから |
| 3 | J1. 版を上げる・通しの確認・統合テスト | — | これから |
| 3 | J2. 文書（README・CHANGELOG・docs・知見） | — | これから |
| 3 | J. main への PR（Tetsuro の確認のあとマージ） | — | これから |

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

- 図の上（「位置の名前」「全レイヤー」の並び）に「比べる」「反映」「戻す」のボタンと、印「実機: 同じ／違う N 件／未確認」を置く。状態バーにも同じ印（押すと「比べる」）
- 比べたあと、違うキー（今のレイヤーで、そのレイヤーの値が実機と違う位置）を橙の枠（`--vscode-charts-orange`）で囲む。ほかのレイヤーに違いがあればレイヤーのタブに点を付ける
- 差分の一覧は図の下に畳める節「実機との差分」として出す。行は「場所: 実機の値 → このプロファイルの値」（キーは `レイヤー名 / 位置の名前`、値は表記）。行を押すと該当の欄へ移る
- 進み具合: 読む・書く・読み直すの段階と件数を、VS Code の通知の進み具合（`withProgress`）に出す。読む間は取り消せる（書き始めたら取り消せない）
- 結果: 反映のあとは「N 件を書き込みました（バックアップ: …）」。読み直しで違いが残ったら警告にして、残った行を一覧に出す。途中で切れたら、書いた件数とバックアップの場所を出し、もう一度反映すれば続きからそろうことを伝える

## 約束（protocol.md）に足すもの

[protocol.md](protocol.md) の「14. v0.4 で足すもの」に書いた。形の見通し:

- `cornix serve --device [--allow-writes]`: device のサーバー。`initialize` は同じ（`capabilities.device: true`、`capabilities.deviceWrites`）
- `device/compare`（読むだけ）・`device/apply`・`device/backups`・`device/compareBackup`（読むだけ）・`device/restore`
- `device/progress` の通知（サーバー → 拡張）
- エラー `-32070` DeviceUnavailable・`-32071` PlanChanged・`-32072` WriteIncomplete・`-32073` PlanRejected・`-32074` WritesNotAllowed・`-32075` CompileFailed

## 段 1（直列）

### P. 約束の型と入れ物

`editors/vscode/src/deviceProtocol.ts`（14 の型）、偽の device のサーバー（`editors/vscode/test/fake-device-server/`）の入れ物、
`spec/fixtures/protocol/device/` のデータの形（偽の実機の状態と、リクエストと応答）。

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

## 段 3

- J1: 約束の版を `"0.4"`、拡張の版を `0.4.0` に。通しの確認（偽の実機で比べる → 反映 → 戻す）。統合テストの追加
- J2: README（英日）・CHANGELOG・spec.md・roadmap.md（v0.4 を済みに）・device.md（拡張からの入口）・`.claude/memories/`
- J: `.vsix` を作り、main への PR。Tetsuro の確認を待つ（実機での確認は Tetsuro が行う。こちらからは書き込まない）
