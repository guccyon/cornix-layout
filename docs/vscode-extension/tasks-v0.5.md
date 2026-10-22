# v0.5 の作業の分け方と契約

issue #105（未使用の項目を取り出す・未使用にする・番号の変更）と、ショートカットの追加を未保存の変更にする作業を、責務の境界で分けたもの。
進め方の共通ルールは [tasks.md](tasks.md) の「共通ルール」と [tasks-v0.4.md](tasks-v0.4.md) と同じ（同じ段の作業は同じファイルを編集しない・契約を勝手に変えない・
作業ごとの PR は `feature/vscode-extension` 向け・版ができたら main への PR を 1 つ。main への PR は Tetsuro が .vsix で確かめてからマージする）。

2026-10-22 に Tetsuro とチャットで UI を決め（下の「決めたこと」。画面の案は https://claude.ai/artifact/HnkoBCY41deiqX9TvZzjLs ）、子の Issue #109〜#115 に分けた。
同じ日に統合ブランチ `feature/vscode-extension` を main（#108 のあと）から作り直して実装を始めた。約束は [protocol.md](protocol.md) の 15、理由は ADR 022・023。

## 進み具合

| 段 | 作業 | Issue | PR | 状態 |
|---|---|---|---|---|
| 1 | P. 約束（protocol.md の 15・`protocol.ts`・`src/itemIndex.ts`・偽のサーバー・ADR・この文書） | #109 | — | 作業中 |
| 1 | W0. 画面の共通部品（追加の一覧・「…」メニュー・番号の選択） | #110 | #116 | CI 待ち |
| 2 | R. `cornix serve`（未使用の項目・index とショートカットの行の書き換え・番号の操作と参照の追従・適合テストのデータ） | #111 | — | — |
| 2 | H. ホスト（番号の操作とショートカットの追加を未保存の変更に積む） | #112 | — | — |
| 2 | L. 画面のレイヤー（「＋」・「…」・番号の選択・並び） | #113 | — | — |
| 2 | I. 画面の節（マクロ・タップダンス・コンボ・ショートカットの「追加」と「…」） | #114 | — | — |
| 3 | J. 仕上げ（約束 0.5・拡張 0.5.0・文書・通しの確認・.vsix） | #115 | — | — |

## 決めたこと（2026-10-22、Tetsuro とチャットで）

1. 未使用の項目は使っているものと並べない。レイヤーはタブの末尾の「＋」、マクロ・タップダンス・コンボ・ショートカットは節の「追加」を押すと、
   検索・「新しく作る」・「未使用（N）」・（マクロとショートカットは）同梱から、の一覧が出る。ショートカットの「同梱からコピー」ボタンはこの一覧にまとめる
2. 未使用のまま開いて編集はしない（#105 の本文の「未使用のまま編集する」案はやめた）。未使用を選ぶと末尾の番号（使っているいちばん大きい番号の次。
   上限なら空いている最小）で使い始め、その項目を選ぶ。番号が埋まっていれば未使用の行は選べず、「どれかを未使用にすると選べます」の 1 行を出す
3. 並べ替えは後から番号の変更・入れ替えで行う。番号の変更と入れ替えは 1 つの番号の選択（0〜上限の番号の一覧。空きなら移動、使っている番号なら入れ替え）。
   レイヤーでは「MO(n) などの参照は書き換えない」、マクロ・タップダンスでは「番号の参照も書き換える」をその場で書き添える
4. 操作は見出しの「…」1 つにまとめ、状態に合うものだけ出す（番号を変える… / 未使用にする / 名前を変える / ファイルを開く / 削除…）。
   今の「レイヤーを削除」のリンクと、節の「名前を変える」「削除」のボタンは「…」に入れる
5. 取り出す・未使用にする・番号の変更とショートカットの追加（同梱からのコピーも、名前を入れて足すのも）は、すぐ書かずに未保存の変更に積む（元に戻す・やり直し、Ctrl+S で保存）。
   追加・削除・名前の変更（ファイルの作成・削除・改名）は今どおり確認のあとすぐ書く（ADR 022）
6. 表記は「未使用（N）」「未使用にする」（「しまう」「しまってある」は使わない）
7. 番号を変えたときの参照（#105 の本文のまま）: マクロ・タップダンスの番号の参照は追従させ、名前の参照とレイヤーの参照は書き換えない。コンボは参照されない

## 作業ごとの契約

段 2 の 4 つは同じファイルを編集しない（`media/webview.css` の末尾だけは L と I の両方が足してよい。まとまりの class の接頭辞を分ける）。

### P（段 1。#109）

- [protocol.md](protocol.md) の 15、ADR 022・023、この文書、[spec.md](spec.md) の「未使用の項目と番号（v0.5）」
- `editors/vscode/src/protocol.ts`: `ProfileSnapshot.unused`（`UnusedItems`・`Unused<T>`）、`ItemEdit` の `use` / `unuse` / `setIndex`（`IndexedKind`）、
  `PlanItemEditParams.changes`、`PlanItemEditResult.changes`
- `editors/vscode/src/itemIndex.ts`（vscode に依存しない）: `INDEX_LIMITS`・`indexAddress`・`effectiveIndex`・`indexChanged`・`arrangeItems`・`snapshotItems`・`nextIndex`・`isPendingItemEdit`。
  ホスト（H）・画面（L・I）・偽のサーバーが同じ規則で使う
- `editors/vscode/src/editor/itemEdits.ts`: `isItemEdit` と `itemEditTitle` に新しい op（形の確かめと見出しの文だけ。流れは H）
- 偽のサーバー（`test/fake-server/`）: `unused`、`["index"]` とショートカットの行の書き換え、新しい op と create（shortcut）の `changes`

### R（段 2。#111）

- 触るのは `lib/` と `spec/` だけ（`spec/fixtures/protocol/` のデータを含む）
- 15.1〜15.3 を Ruby で作る。適合テストのデータを足し、拡張の `test/unit/protocolFixtures.test.ts`（偽のサーバーにエラーの応答だけを流す）も通ること

### H（段 2。#112）

- 触るのは `editors/vscode/src/editor/`（`itemEdits.ts` の文を含む）と `src/webviewMessages.ts`・`src/extension.ts`（要れば）とそのテスト
- 画面からの `itemEdit` のうち `isPendingItemEdit` のものは、`profile/planItemEdit` に今の未保存の変更（`changes`）を付けて送り、返った `changes` を 1 つの編集（元に戻す・やり直しの単位）として未保存の変更の末尾に足す。
  未保存の変更があっても止めない。`unuse` で `references` があるときだけ確認のダイアログ（件数）
- 画面のメッセージは今の `itemEdit`（画面 → ホスト）と未保存の変更の知らせ（ホスト → 画面）のまま。画面は未保存の変更から `itemIndex.ts` で番号を出す

### L（段 2。#113）

- 触るのは `src/webview/app.ts`・`layerEditor.ts`・`model.ts`・`keyboardView.ts`（要れば）とそのテスト、`media/webview.css` の末尾
- W0 の `AddMenu`・`MoreMenu`・`IndexPicker` を組み込む。使っているレイヤーの並び（タブ・図・キー別）は `arrangeItems(snapshotItems(snapshot, 'layer'), pending)` の `used`

### I（段 2。#114）

- 触るのは `src/webview/itemList.ts`・`macroEditor.ts`・`tapDanceEditor.ts`・`comboEditor.ts`・`shortcutEditor.ts`・`itemsModel.ts` とそのテスト、`media/webview.css` の末尾
- 節の一覧は `arrangeItems` の `used`。未保存のショートカットの追加（`["shortcuts", 名前]` の set で、snapshot にない名前）も一覧に出す

### J（段 3。#115）

- 約束の版を `"0.5"`・拡張を 0.5.0 に（直す場所は `.claude/memories/vscode_extension_v04.md` の「約束の版」）、CHANGELOG・README・roadmap・この文書の進み具合、
  本物の `cornix serve` で通しの確認、.vsix
