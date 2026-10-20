# v0.2 の作業の分け方と契約

[roadmap.md](roadmap.md) の v0.2（「すべての設定ファイルを画面だけで編集できる」）を、責務の境界で分けた作業にしたもの。
進め方の共通ルールは [tasks.md](tasks.md) の「共通ルール」と「v0.2 からの進め方」と同じ（同じ段の作業は同じファイルを編集しない・契約を勝手に変えない・
作業ごとの PR は `feature/vscode-extension` 向け・版ができたら main への PR を 1 つ）。

## 進み具合

| 段 | 作業 | PR | 状態 |
|---|---|---|---|
| 0 | 作業の分け方と決めたこと（この文書） | #53 | 済み |
| 1 | P. 約束（protocol.md の 12）・拡張の型（`protocol.ts`）・画面とホストの間のメッセージ（`webviewMessages.ts`） | #56・#57 | 済み |
| 2 | R0. 書いていない位置を KC_NO にする | #58 | 済み |
| 2 | R1. 中身を読む | #60 | 済み |
| 2 | R2. 中身を書き換える | #64 | 済み |
| 2 | R3. 項目の操作 | #63 | 済み |
| 2 | E1. 項目の画面 | #61 | 済み |
| 2 | E2. 図とキー入力欄 | #62 | 済み |
| 2 | E3. ホスト | #65 | 済み |
| 3 | J1. コードの仕上げ（約束の版を `"0.2"` に、型の整理、preset の選び直し、説明の吹き出し、タップダンスの動作・コンボの出すキーの注記の欄、揺れるテスト） | — | 作業中 |
| 3 | J2. 文書（README・CHANGELOG・docs・知見） | — | 作業中 |
| 3 | J. 通しの確認と main への PR | — | これから |

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

## 決めたこと

2026-10-20 に Tetsuro に確認して、どれも推した案に決まった。

1. **位置の名前の表示の切り替えと色**（図の上のトグルボタンで固定の切り替え＋ Alt を押している間だけ一時表示。名前は紫、マクロの `M` の印は橙に変える）
2. **項目の追加・削除・名前の変更**（確認のダイアログのあとすぐファイルに書く。未保存の変更があるときは先に保存を促す。中身の編集はこれまでどおり未保存に積む）
3. **レイヤーの割り当てを消す操作**（YAML の行ごと消して「書いていない」状態にする。図は点線の枠）
4. **書いていない位置の compile**（3 の確認のときに、今の compile が書いていない位置を NoKey ではなく .vil の `-1` にしていると分かった。
   `-1` は `cornix device apply` が飛ばし（前の値が残る）、vial-gui の読み込みは `-1` をそのまま 16bit で送ろうとして失敗しうる。
   2026-10-20 決定: position_map にある位置で書いていないものは compile で KC_NO（0）にする。キーのない枠は今までどおり `-1`。下の R0）

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

protocol.md に「12. v0.2 で足すもの」を足し、上の「約束に足すもの」を型・決まり・エラーまで書く。合わせて `editors/vscode/src/protocol.ts` に型を足す
（v0.1 の型は壊さない。snapshot の新しい項目は省ける形にし、Change の `op` 付きの形は `AnyChange` として別に足す）。
適合テストのデータ（`spec/fixtures/protocol/`）は、そのメソッドを作る段 2 の作業が足す。約束の版（`protocolVersion`）は段 3 で `"0.2"` に上げる。
段 2 の全作業がこの PR の約束と型を前提にする。

触るファイル: `docs/vscode-extension/protocol.md`、`editors/vscode/src/protocol.ts`

## 段 2（並列）

### R0. 書いていない位置を NoKey にする（Ruby）

決めたことの 4。`Mapping::ProfileMapper#to_image` で、position_map にある位置の割り当てがなければ `-1`（nil）ではなく KC_NO にする。
decompile はこれまでどおり NoKey を書く（往復は変わらない）。利用者に見える変更なので CHANGELOG.md の `[Unreleased]` に書き、
docs/domain-model.md の「割り当てのない位置も nil にする」の記述を直す。end_to_end の保存した .vil との差が出れば、その差が書いていない位置だけかを確かめて更新する。

触るファイル: `lib/cornix/mapping/profile_mapper*`、`spec/mapping/profile_mapper*`、`spec/fixtures/`（保存した .vil を更新するときだけ）、`docs/domain-model.md`、`CHANGELOG.md`

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
コードの仕上げ（J1）と文書（J2）は触るファイルを分けて並列に進める。

## 段 2 の PR で決めたこと

約束（protocol.md）の曖昧なところを、各 PR が次のように決めた（protocol.md は変えていない。詳しくは各 PR の「補足」）。

### R0（#58）

- 定義のあるレイヤーでは position_map のすべての位置をまず KC_NO で埋め、その上に割り当てを書く。キーのない枠（プッシュ以外の col 6）と定義のないレイヤーは `-1` のまま。
  エンコーダは前から読み込みで書いていない操作を `NoKey` にしているので変わらない
- `-1` を含む .vil を decompile → compile すると、その位置は `0` になる（保存した .vil の fixtures には定義のあるレイヤーの `-1` がなく、期待値は変わらなかった）

### R1（#60）

- `keycode/candidates` の `all: true` は context によらず効く。`macroKey` の `all: true` で出すマクロ・タップダンスは `M0` / `TD(4)` の形（マクロのファイルは名前参照を読まないため）。ショートカットは出さない
- `exclude` が読めない表記なら何も除かない。その欄の読み方で読み、16bit 値が同じ候補を除く
- `comboTrigger` の「ベースレイヤーにあるキー」はレイヤー 0 のキーの位置の値（KC_NO・KC_TRNS とエンコーダは除く）。`shortcutValue` では修飾キー式を候補に出さず、修飾キーと基本キーを上に出す
- 項目の `description: ''` は `null`（レイヤーは v0.1 のまま `""`）。手順とコンボのキーの `value` は、ファイルの表記が取れなければ正規形で埋める

### R2（#64）

- 宛先にできない op（`output_key` の `remove`、QMK 設定の `remove` など）は `changes[i].address`、注記を書けない場所の `field: "note"` は `changes[i].field` の `-32602`
- 割り当てのない場所への注記の `set` は `-32602`（同じ並びで先にキーを `set` すれば書ける）。書いていないキーの `remove`・注記のないところの注記の `remove` は書き換えなし
- 並びの中の位置は前の Change を当てたあとの中身で確かめるので、位置の誤りが前の Change の `-32061` より後に分かることがある（5.6 の確かめる順の、並びの位置だけの例外）
- ブロック形式の注記付きの形の注記の `remove` は `note:` の行だけを消す。挿入するマクロの手順の `keys` はフロー表記（`keys: [KC_A]`）。
  ブロックの並びへの挿入は前の要素のすぐあと、移動は要素の前のコメントの行ごと
- 前に別の内容がある行（`- action: tap` の行の項目など）は行ごと消せないので `-32061`（reason は約束に足さず `"flowInsert"`）

### R3（#63）

- `baseVersions` の照合は中身の変わるファイル（作る・消す・改名を含む）だけ。今あるファイルで `baseVersions` にないものは `-32602`（`field: "baseVersions"`）、作るファイルは書かなくてよく書くなら `null`。
  宛先の誤り（`-32602`）や `-32061` のときは、その前に送られたすべての版を比べ、食い違えば `-32060` を返す（古い中身を見ていたせいで名前が見つからないことを版の食い違いとして知らせるため）
- 確かめる順: params の形 → 宛先と名前（`-32602`）/ 局所的に書き換えられるか（`-32061`）→ 書き換えるファイルの版（`-32060`）→ `baseVersions` の抜け（`-32602`）→ compile の照合（`-32061` verify）
- `files` の並びは操作の対象のファイルが先、参照を置き換えたファイルはそのあと。`create` はいつも入れ、`delete` / `renameTo` はそのときだけ。
  1 つのファイルへの書き換えが 1 回ならその範囲、2 回以上なら `TextEdit.diff` にまとめる。改名するファイルの `edits` は元のファイルでの位置
- 名前の改行も `-32602`。今と同じ名前への変更は `files: []`。重なりは同じ種類の中だけで見る（ショートカットは `shortcuts.yaml` の名前だけと比べ、同梱と同じ名前は許す）
- `renamePosition` の `references` は `[]`。名前は position_map と同じ書き方（英数字と `_` `-`）に限り、compile の照合もする
- 同梱に同じ名前のあるショートカットを消したときは、参照がそちらを指すだけなので `references` は `[]`
- 構造検証で読めないプロファイルの項目の操作は `-32602`（`field: "edit"`）

### E1（#61）・E2（#62）

- 中身の欄の `all` / `exclude` は、E1 では HostClient の包み（`withCandidateParams`）、E2 では `KeyInput` のオプション `candidateParams` で渡した（段 3 でそろえる）
- `preset` の選び直しは、`keycode/shortcutTree` の中継がないので名前を打つ文字の欄にとどめた（段 3 で階層の選択に）
- 割り当てを消した欄は空で「（なし）」、図は点線の枠。キー入力欄を空にして決めても消さず ✕ を案内する
- TD の印も橙なのでマクロの印と同じ色になるが、TD の印は定義が見つからないタップダンスにだけ付くのでそのままにした
- 段 3 で見ること: 組み立て欄の大きさ、注記の欄と ✕ の出し方、Alt での一時表示（Windows / Linux で Alt がメニューバーにフォーカスを移さないか）

### E3（#65）

- 未保存の変更は `AnyChange` の当てる順の 1 本の並び（`PendingChanges`）。並びの外の `set` / `remove` は同じ場所（Address と `field`）の前の変更をその位置で置き換えて畳み、
  保存済みの値に戻れば持たない。並びを指す Change（`insert` / `move` と、道筋に番号のある `set` / `remove`）は畳まずに足した順のまま
- まだ書いていない位置の割り当ての `set` は、同じ行の注記の `set` より前に入れる。書いていない位置の `set` のあとの `remove` は両方を打ち消す
- 保存したあとの並びの要素の `set` / `remove` の undo は、前の値が分からないので戻さない（逆の Change を作れる `insert` と `move` だけ戻す）
- 並びを指す Change のあるファイルが外で変わったら、そのファイルの Change はまとめて「当て直せないもの」にする
- 偽のサーバーの中身（マクロの手順など）はディスクから読まない（ファイルの一覧と `name:` `index:` `description:` の行だけ）
