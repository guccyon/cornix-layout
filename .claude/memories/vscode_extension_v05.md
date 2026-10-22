# VS Code 拡張 v0.5 の作業の知見

## 画面のレイヤー（L #113）

- 画面のレイヤーの並びは `App.layers`（`model.ts` の `arrangeLayers` = `arrangeItems(snapshotItems(snapshot, 'layer'), pending)` の used）だけを見る。
  `snapshot.layers` を直接引くのは「保存済みの番号」がほしいとき（タブの title の「番号を N から変えています」）と、デバイス転送（保存済みの図）だけ。
  `baseLayerValue` と `structureKey` には `{ ...snapshot, layers: this.layers }` を渡す
- `setSnapshot` の速い道（snapshot の JSON が同じなら値だけ描き直す）は、番号の並び（`arrangementKey`）も同じときだけ。
  use / unuse / setIndex は snapshot を変えず pending だけ変わるので、並びの比較を入れないとタブが描き直されない
- 選んでいるレイヤーはファイルで追う（番号を変えても同じレイヤーのまま。入れ替えで番号が変わる）。取り出したレイヤーは `wantedFile` で、並びに現れたら選ぶ
- 「＋」の AddMenu はタブを描き直しても残す（開いたまま snapshot が来ても閉じないように）。タブのボタンは `display: contents` の `.layer-tab-list` に入れて別に描き直す。
  AddMenu のボタンは `item-button` の見た目なので、`.layer-add-menu .layer-tab.layer-add` で border と背景をタブに合わせ直した
- 見出しの「…」も 1 つの MoreMenu を使い回し、番号の選択・名前の変更は見出しの下の `.layer-panel-slot`（renderLayerInfo で作り直さない）に出す。ほかのレイヤーに移る・キー別にすると閉じる
- W0 の `MoreMenuAction` に `note`（右に添える補足。「いま 1」）を足した（`.more-menu-line` / `.more-menu-note`。I のマクロ・タップダンスの「番号を変える…」でも使える）
- 画面を見るとき、stub の HTML には `<div id="app">` が要る（`main.ts` が `getElementById('app')`）。未使用は fixtureSnapshot に `unused.layers`（レイヤーの写しを `index: null` に）を足して入れる
