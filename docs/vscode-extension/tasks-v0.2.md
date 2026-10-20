# v0.2 の作業の分け方と契約

[roadmap.md](roadmap.md) の v0.2（「すべての設定ファイルを画面だけで編集できる」）を、責務の境界で分けた作業にしたもの。
進め方の共通ルールは [tasks.md](tasks.md) の「共通ルール」と「v0.2 からの進め方」と同じ（同じ段の作業は同じファイルを編集しない・契約を勝手に変えない・
作業ごとの PR は `feature/vscode-extension` 向け・版ができたら main への PR を 1 つ）。

## v0.2 で入れるもの

roadmap の v0.2 の行を、画面の単位に並べ直したもの。

| # | 中身 | 主に作る側 |
|---|---|---|
| 1 | マクロ・タップダンス・コンボ・ショートカットの中身の画面と編集（spec.md の「ファイルの種類ごと」の v0.2 の行） | 両方 |
| 2 | 項目の追加・削除・名前の変更（マクロ・タップダンス・コンボ・ショートカット・レイヤーの名前と説明） | 両方 |
| 3 | `position_map` の名前の編集と、図で位置の名前を見せる表示（roadmap の「v0.2 の候補: position_map」） | 両方 |
| 4 | 注記（`{ key:, note: }` の note）の編集 | 両方 |
| 5 | 割り当てを消す操作（protocol.md の 11 の 7 の先送り分） | 両方 |
| 6 | 修飾キー式・`LT`・Mod-Tap の組み立て欄 | 拡張 |
| 7 | `KC_TRNS` のキーに下のレイヤーの値を薄く出す | 拡張 |
| 8 | 候補の行のアイコン | 拡張 |
| 9 | テキストで開いたときの波線（同じ検証の結果を `DiagnosticCollection` で） | 拡張 |

v0.3 に回すもの（roadmap のまま）: コンボのキーを図から選ぶ、preset を手順に展開、同梱ショートカットのコピー、押せないコンボの印、あいまい検索。

## 決めること（2026-10-20 に Tetsuro に確認中。決まったらこの節を「決めたこと」にする）

括弧の中が推している案。決まるまではこの案で作り始め、違えば直す。

1. **位置の名前の表示の切り替えと色**（2026-10-20 決定: 図の上のトグルボタンで固定の切り替え＋ Alt を押している間だけ一時表示。名前は紫、マクロの `M` の印は橙に変える）
2. **項目の追加・削除・名前の変更**（推: 確認のダイアログのあとすぐファイルに書く。未保存の変更があるときは先に保存を促す。中身の編集はこれまでどおり未保存に積む）
3. **レイヤーの割り当てを消す操作**（推: YAML の行ごと消して「書いていない」状態にする。図は点線の枠）

自分で決めたこと（違えば言ってもらう）:

- `KC_TRNS` の下に出すのはベースレイヤー（レイヤー 0）の値。どのレイヤーが有効かは実行時に決まり、ふだんはベースに落ちるため。説明（ツールチップ）に「レイヤー 0 の値」と書く
- 名前の変更は `Application::RenameFiles` と同じく、参照をテキストで書き換え、前後の compile の結果（16bit 値）が同じことを確かめる。違えば書かずにエラー
- 位置の名前の変更は、`position_map.yaml` の値と、全レイヤーのファイルの `mapping` の下のキーをまとめて書き換える（compile の結果は変わらない）
- 削除した項目への参照は止めずに、参照している側にエラーを出す（spec.md の「検証」のとおり）。削除の確認のダイアログで参照の数を見せる

## 約束（protocol.md）に足すもの

段 1 で protocol.md に書いて決める。ここでは形の見通しだけ。

- `profile/open` の結果に `macros` `tapDances` `combos` `shortcuts` の中身を足す。各値は v0.1 のレイヤーのキーと同じく `{ address, value: KeyValue }`。
  名前・説明・`tapping_term`・マクロの `delay` / `text` も Address 付きで返す。`positionMap` の各位置に、名前を書いている場所の Address を足す
- Change を広げる（後方互換。`op` を省けば v0.1 と同じ `set`）
  ```ts
  type Change =
    | { op?: "set"; address: Address; value: string | number | boolean; field?: "key" | "note" }
    | { op: "remove"; address: Address }                                  // 割り当て・注記・手順・キーを消す
    | { op: "insert"; address: Address; index: number; value: unknown }   // 並び（マクロの手順・キー、コンボのキー）に足す
    | { op: "move"; address: Address; from: number; to: number };         // 並びの中で動かす
  ```
- 項目の操作のメソッド `profile/planItemEdit`（追加・削除・名前の変更・位置の名前の変更）。結果は `profile/planEdits` の `files` に
  `delete: true` と `renameTo` を足した形（拡張は 1 つの `WorkspaceEdit` で当てて保存し、`profile/saved` で知らせる）
- `keycode/candidates` の `context` に `macroKey` `tapDanceAction` `comboTrigger` `comboOutput` `shortcutValue` を足す（並びは `data/keycode_categories.yaml` の `contexts`）
- `-32061` の reason に足すものがあれば足す（並びの中への挿入でフロー表記のときなど）

## 段 1（直列。この PR のあと）

### P. 約束を決める（ブランチは作業ごと、PR は `feature/vscode-extension` 向け）

protocol.md を v0.2 に上げ、上の「約束に足すもの」を型・決まり・エラーまで書く。合わせて `editors/vscode/src/protocol.ts` の型と、
`spec/fixtures/protocol/` に新しいメソッドと context の適合テストのデータを足す（Ruby の実装がないうちは `pending`）。
段 2 の全作業がこの PR の型とデータを前提にする。

触るファイル: `docs/vscode-extension/protocol.md`、`editors/vscode/src/protocol.ts`、`spec/fixtures/protocol/**`

## 段 2（並列）

### R1. 中身を読む（Ruby）

`profile/open` の `macros` `tapDances` `combos` `shortcuts` と `positionMap` の Address、`keycode/candidates` の新しい context。

触るファイル: `lib/cornix/application/editor/snapshot.rb`・`key_values.rb`・`candidates.rb`・`unknown_context.rb`（+ 新しいファイル）、
`lib/cornix/mapping/candidate_catalog*`、`data/keycode_categories.yaml`、`lib/cornix/storage/diagnostic_locator.rb`、対応する spec

### R2. 中身を書き換える（Ruby）

Change の `op`（`remove` / `insert` / `move`）と `field: "note"`。値だけの書き換えを、並びの要素と行の削除に広げる（コメントと字下げを保つ。
できないときは `-32061`）。注記のない形に note を足すとき（`tab: Escape` → `tab: { key: Escape, note: … }`）の形も決める。

触るファイル: `lib/cornix/application/editor/plan_edits/**`、`lib/cornix/storage/yaml_document*`・`text_edit.rb`・`edit_not_local.rb`、
`lib/cornix/interface/editor_server/handlers/profile_plan_edits.rb`・`draft_params.rb`、対応する spec

### R3. 項目の操作（Ruby）

`profile/planItemEdit`。追加（次の空いている index とファイル名、`bin/rename_file` の名前の付け方）、削除（参照の数を返す）、
名前の変更（`RenameFiles` の置換と compile の照合を使う）、位置の名前の変更。

触るファイル: `lib/cornix/application/editor/item_edits*`（新規）、`lib/cornix/interface/editor_server/handlers/profile_plan_item_edit.rb`（新規）、
必要なら `lib/cornix/application/rename_files.rb`（中身を呼べるように分けるだけ）、対応する spec

### E1. 項目の画面（拡張・Webview）

下のペインにマクロ・タップダンス・コンボ・ショートカットの節。各節は一覧と、選んだ項目の編集欄（キー入力欄は v0.1 の `KeyInput` に context を渡す）。
マクロは手順の並び（追加・削除・上下に動かす）、`delay` / `text` の欄。追加・削除・名前の変更のボタンはホストへのメッセージを出すだけ（流れは E3）。

触るファイル: `editors/vscode/src/webview/` の新しいファイル（`macroEditor.ts` `tapDanceEditor.ts` `comboEditor.ts` `shortcutEditor.ts` `itemList.ts` など）、
`editors/vscode/src/webview/main.ts`（`sections` に足すだけ）、対応する `test/unit/`

### E2. 図とキー入力欄（拡張・Webview）

位置の名前の表示（切り替えと色）、位置の名前の欄の編集、`KC_TRNS` の下のレイヤーの値、候補の行のアイコン、修飾キー式・`LT`・Mod-Tap の組み立て欄、
割り当てを消す操作と注記の欄（レイヤーの編集画面）。

触るファイル: `editors/vscode/src/webview/keyboardView.ts`・`keyInput.ts`・`layerEditor.ts`・`model.ts`・`tooltip.ts`・`app.ts`、
新しいファイル（`modifierBuilder.ts` など）、Webview の CSS、対応する `test/unit/`

### E3. ホスト（拡張・Extension Host）

Change の `op` を未保存の変更として持つ（同じ Address の畳み方、元に戻す）、項目の操作の流れ（確認のダイアログ → `profile/planItemEdit` →
ファイルの作成・削除・改名を含む `WorkspaceEdit` → `profile/saved`）、テキストの波線（`DiagnosticCollection`）。

触るファイル: `editors/vscode/src/editor/**`、`editors/vscode/src/server/cornixServer.ts`、`editors/vscode/src/webviewMessages.ts`、
`editors/vscode/test/fake-server/**`、対応する `test/unit/` と `test/integration/`

E1・E2・E3 は `webviewMessages.ts` の新しいメッセージを E3 が先に足す（E1・E2 はそれを使う）。ぶつかりそうなら段 1 の P で型だけ足しておく。

## 段 3

### J. 通しの確認と main への PR

.vsix を作って手元で入れ、自分のプロファイルで「すべての設定ファイルを画面だけで編集できる」を確かめる（マクロを 1 つ作って手順を足し、
名前を変え、レイヤーに割り当てて保存し、compile の結果が手で直したときと同じ。変えていない行が変わらない）。
README.md / README.ja.md と CHANGELOG.md、docs の v0.2 の記述を整えて、`feature/vscode-extension` → main の PR を作る。
