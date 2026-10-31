# キーボード固有の情報（KeyboardSpec）

VS Code 拡張は、キーの数・図の配置・個数の上限など、キーボードごとに違う情報を型 `KeyboardSpec` の値から取る（[ADR 026](adr.md)、Issue #137）。
今の値は Cornix だけで、拡張に内包している（`cornix serve` からは取らない）。約束（[protocol.md](protocol.md)）は変えていない。

## 置き場所

| ファイル | 中身 |
|---|---|
| `editors/vscode/src/keyboard/spec.ts` | 型（`KeyboardSpec`・`KeyRect` など）と純粋な関数（`indexLimit`・`boardSize`・`rotationOrigin`）。Webview からも読む |
| `editors/vscode/src/keyboard/cornix.ts` | Cornix の値 `CORNIX`。Webview は import しない |
| `editors/vscode/src/keyboard/index.ts` | `keyboardSpecFor(profileDir)`: プロファイルに使う spec を選ぶ（ホスト側。今は常に Cornix） |

ホスト（`editor/profileEditorProvider.ts`）は Webview の `ready` のあと、最初の `snapshot` より前に `{ type: 'keyboard', spec }`（`webviewMessages.ts`）を送る。
Webview（`webview/main.ts`）はそれを受けてから画面を組み立て、`App`・各節・図・編集フォーム・反映のプレビューに渡す。
Webview が spec のデータを import しないことは `test/unit/keyboardSpec.test.ts` が確かめる。spec は postMessage で送れるよう、データだけで関数を持たない。

## 項目

| 項目 | 意味 | Cornix の値 |
|---|---|---|
| `id` / `displayName` | キーボードの ID と表示名（「接続中の Cornix に書き込みます」などの文言） | `cornix` / `Cornix` |
| `limits` | レイヤー・マクロ・タップダンス・コンボの数、コンボで同時に押すキーの数 | 10 / 32 / 32 / 32 / 4（本体の `Domain::Capabilities::CORNIX`） |
| `sections` | 区画（左右の手を一般化したもの）の並びと見出し。編集フォームの節の順 | `left` 左手 / `right` 右手 |
| `groups` | position_map のグループの見出し。spec にないグループ名はそのまま出す | `row0`〜`row3` 1〜4 段目、`thumb`（旧名 `thumb_keys`）親指 |
| `keys` | 図のキー。文字列の ID、区画、矩形（`KeyRect`）、約束の位置との対応 `match: { hand, row, col }` | 48 キー（`L-r0c0` など） |
| `encoders` | 図のエンコーダ。ID、区画、見出し、外枠、約束の `layer.encoders` との対応 `match: { side }` | 左右に 1 つずつ |
| `padding` | 図の右と下の余白（図の大きさは `boardSize` がキーとエンコーダの範囲から出す） | 下に 0.032552（今までの 16.4 × 4.75 に合わせる） |

`KeyRect` は Vial の KLE に寄せた形（単位は u。`x, y, w, h` と回転の角度 `r`・中心 `rx, ry`）。`rx` / `ry` がなければ矩形の中心まわりに回す。
座標は図の左上を (0, 0) とする。

画面の欄（`webview/model.ts` の `Slot`）は区画 `section` を持ち、並びと見出しはそれで決める。
約束の `hand` も持つが、サーバーとのやりとり（位置の名前の変更など）と値の照合だけに使う。
サーバーの位置から spec のキーへは `match` で引き、spec にない位置は図に描かない（編集フォームには出す）。

## 新しいキーボードを足すときに直す場所

1. `src/keyboard/<名前>.ts` に spec の値を書く（区画・グループ・配置・個数・表示名）
2. `src/keyboard/index.ts` の `keyboardSpecFor` で、そのプロファイルにその spec を選ぶようにする（選び方はまだ決めていない。プロファイルの設定・サーバーから取るなど）
3. cornix 本体（Ruby）の論理座標（`KeyPosition`・`PositionMap`・`Capabilities::CORNIX`）と約束の `hand` / `encoders.left|right` は Cornix の形のままなので、左右の手のないキーボードには本体の一般化が先に要る（#137 の対象外）

拡張の中でキーボードによらないので spec に寄せていないもの:

- 約束の `hand` と `layer.encoders` の `left` / `right`（`protocol.ts`・`model.ts` の `ENCODER_SIDES`）
- 設定ファイルの `left_hand` / `right_hand` の見出し（`editor/rebase.ts`・`editor/itemEdits.ts`）
- 修飾キーの左右（`webview/modifierBuilder.ts`）、レイヤーの並び替えの ◀▶ の向き
- 「Bluetooth では 10 秒ほど」（RMK 0.8 と通信の速さによる）
- ツールとしての「Cornix」（コマンド名、出力パネル、`cornix serve`、クラス名）
