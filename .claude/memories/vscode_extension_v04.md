# VS Code 拡張 v0.4 の作業の知見

v0.4 のうち issue #84（下の欄の「キー別」の並べ方・レイヤーの追加と削除・図の「全レイヤー」のトグルの廃止）で分かったこと。
実機とつなぐ作業の計画は docs/vscode-extension/tasks-v0.4.md。v0.3 までの知見は [vscode_extension_v03.md](vscode_extension_v03.md)。

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
