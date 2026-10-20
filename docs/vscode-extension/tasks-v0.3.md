# v0.3 の作業の分け方と契約

[roadmap.md](roadmap.md) の v0.3（「手で直すときにテキストを開かなくなる」）を、責務の境界で分けた作業にしたもの。
進め方の共通ルールは [tasks.md](tasks.md) の「共通ルール」と [tasks-v0.2.md](tasks-v0.2.md) と同じ（同じ段の作業は同じファイルを編集しない・契約を勝手に変えない・
作業ごとの PR は `feature/vscode-extension` 向け・版ができたら main への PR を 1 つ。main への PR は Tetsuro が .vsix で確かめてからマージする）。

## 進み具合

| 段 | 作業 | PR | 状態 |
|---|---|---|---|
| 1 | P. 作業の分け方と決めたこと（この文書）・約束（protocol.md の 13）・拡張の型 | — | 作業中 |
| 2 | R1. 候補（あいまい検索・よく使うキーを上に）と矢印の表示 | — | これから |
| 2 | R2. preset を手順に展開・押せないコンボ | — | これから |
| 2 | E1. 図（位置の名前・空きの見た目・コンボ・全レイヤーの表示・図からキーを選ぶ） | — | これから |
| 2 | E2. 欄と節（`（なし）` を消す・節を畳む・同梱ショートカットを選ぶ／コピー・コンボのキーを図から・展開のボタン・押せない印） | — | これから |
| 3 | J1. コードの仕上げ（約束の版を `"0.3"` に、拡張の版を 0.3.0 に、通しの確認） | — | これから |
| 3 | J2. 文書（README・CHANGELOG・docs・知見） | — | これから |
| 3 | J. main への PR（Tetsuro の確認のあとマージ） | — | これから |

## v0.3 で入れるもの

roadmap の v0.3 の行と「v0.3 への申し送り」を、画面の単位に並べ直したもの。

| # | 中身 | 出所 | 作業 |
|---|---|---|---|
| 1 | 「位置の名前」のボタンにマウスを載せている間も位置の名前を出す | 申し送り | E1 |
| 2 | 位置の名前の出所が `position_map.yaml` で、そこを変えるとラベルが変わることを画面で分かるようにする | 申し送り | E1 |
| 3 | `Up` / `Left` / `Right` / `Down` を `↑` / `←` / `→` / `↓` で見せる | 申し送り | R1 |
| 4 | 割り当てを解除したキーを NoKey と同じ見た目（枠はあり、中は空白）にする | 申し送り | E1 |
| 5 | コンボを図で見せる（決めたことの 1） | 申し送り | E1 |
| 6 | 割り当てを解除した欄の placeholder `（なし）` を出さない | 申し送り | E2 |
| 7 | 最初に開いたとき、レイヤー以外の節を畳む。`▶` / `▼` の印 | 申し送り | E2 |
| 8 | 同梱のショートカットを一覧から選べる導線（決めたことの 2） | 申し送り | E2 |
| 9 | キーの位置ごとに全レイヤーを並べる表示への切り替え（決めたことの 3） | roadmap | E1 |
| 10 | あいまい検索（決めたことの 7） | roadmap | R1 |
| 11 | よく使うキーを上に（決めたことの 4） | roadmap | R1 |
| 12 | コンボのキーを図から選ぶ | roadmap | E1（図の選ぶ状態）・E2（コンボの画面のボタン） |
| 13 | preset を手順に展開（決めたことの 6） | roadmap | R2・E2 |
| 14 | 同梱ショートカットを自分のものにコピー（決めたことの 2） | roadmap | E2 |
| 15 | 押せないコンボの印（決めたことの 5） | roadmap | R2・E1・E2 |

## 決めたこと

2026-10-20 にチャットでまとめを出し、推した案で進めている（違えば Tetsuro が言う）。

1. **コンボの図での見せ方**: 図の上にコンボの番号のボタンを並べ、押す（固定）かマウスを載せている（一時）間、そのコンボのトリガーのキーだけを強調する。同時に 1 つ。
   トリガーは位置ではなくキーコードなので、今のレイヤーでそのキーコードを割り当てた位置を強調する（`KC_TRNS` はレイヤー 0 の値で見る）。
   ボタンの説明（ツールチップ）にコンボの名前・トリガー・出すキー。押せないコンボのボタンには ⚠。
   選ばなかった案: トグル 1 つで全コンボを色分けして同時に強調（数が多いと図が散らかる）
2. **同梱ショートカットの導線**: キー入力欄の候補の一覧の下に「同梱から選ぶ…」を置き、マクロの `preset:` で使っている階層の選択（`presetPicker.ts`。アプリ → カテゴリ → ラベル、アイコン付き）を開いて
   `Shortcut('アプリ:カテゴリ:ラベル')` を入れる（手順の定義しかない `macro: true` の項目は出さない）。
   ショートカットの節には「同梱からコピー」を置き、同じ選択で選んだものを `shortcuts.yaml` に足す（名前はラベル、値は同梱の表記 `text`。
   `profile/planItemEdit` の `create`・`kind: "shortcut"`。約束は変えない）。コピーしても既存の参照は書き換えない
3. **全レイヤーの表示**: 「位置の名前」の隣に「全レイヤー」のトグル。表示中は各キーの面に、レイヤーごとの値を `番号 ラベル` の小さな行で上から並べる。
   `KC_TRNS`・NoKey・書いていない位置の行は省く。今選んでいるレイヤーの行を強調する。表示中にキーを押したときの動きは今と同じ（下の欄へ移る）。
   位置の名前の表示とは同時に出さない（あとから押したほうに切り替える）
4. **よく使うキーを上に**: 当てはまり方（完全一致・前方一致・部分一致・あいまい一致）が同じ候補の中で、そのプロファイルの全レイヤー・エンコーダ・マクロ・タップダンス・コンボで
   使っている回数が多いものを上にする（同じ回数なら今の並び）。context ごとに上に出すもの（`data/keycode_categories.yaml` の `contexts`）は今までどおり先
5. **押せないコンボ**: トリガーのキーがすべてそろうレイヤーが 1 つもないコンボ（各レイヤーで、そのレイヤーに割り当てたキーコードに、`KC_TRNS` の位置はレイヤー 0 の値を足して見る）。
   意味検証の警告（validate と画面の両方に出る）にし、snapshot のコンボに `reachable` を足す。トリガーが `KC_NO` だけのコンボ（作ったばかり）は警告しない
6. **preset を手順に展開**: マクロの画面に「手順に展開」のボタン。`profile/planItemEdit` の新しい op `expandPreset` で、`preset:` の行を同梱の定義の `sequence:` に置き換える。
   項目の操作と同じく確認のダイアログのあとすぐ書き、前後の compile の結果（16bit 値）が同じでなければ書かない
7. **あいまい検索**: 前方一致・部分一致に当たらないとき、query の文字を順に含む（間を飛ばしてよい）ものを、それらの下に出す（`lbr` → `KC_LBRACKET`）。
   大文字小文字・`_`・空白は区別しない。飛ばした文字の少ないものを上に

## 約束（protocol.md）に足すもの

[protocol.md](protocol.md) の「13. v0.3 で足すもの」に書いた。形の見通し:

- `profile/planItemEdit` の `ItemEdit` に `{ op: "expandPreset"; kind: "macro"; name: string }`
- snapshot の `combos` の各項目に `reachable: boolean`
- 意味検証の警告「押せないコンボ」（`address` はコンボの `trigger_keys`）
- 候補の並び（あいまい一致・使っている回数）。形は変えない
- `KeyValue.display` の矢印のラベル（`↑` `←` `→` `↓`）。形は変えない

## 段 1（直列）

### P. 約束を決める

この文書、protocol.md の 13、`editors/vscode/src/protocol.ts` の型、`App#pickKey` の入れ物（E2 が main.ts でつなぐため。中身は E1）。

触るファイル: `docs/vscode-extension/tasks-v0.3.md`・`protocol.md`、`editors/vscode/src/protocol.ts`、`editors/vscode/src/webview/app.ts`（`pickKey` の入れ物だけ）

## 段 2（並列）

### R1. 候補と矢印の表示（Ruby）

決めたことの 4・7 と、v0.3 で入れるものの 3。`Mapping::CandidateCatalog` の当てはめにあいまい一致を足し、同じ当てはまり方の中を使っている回数で並べる
（回数は `Application::Editor::Candidates` がプロファイルから数えて渡す。Mapping は I/O をしない）。
`Mapping::KeyDisplay` の基本キーのラベルで、`KC_UP` / `KC_LEFT` / `KC_RIGHT` / `KC_DOWN` を矢印にする（decompile の名前・別名の表は変えない）。

触るファイル: `lib/cornix/mapping/candidate_catalog*`・`key_display.rb`、`lib/cornix/application/editor/candidates.rb`（+ 新しいファイル）、
`data/keycode_categories.yaml`（要れば）、対応する spec、`spec/fixtures/protocol/`（候補と、ラベルが変わる snapshot のデータ）

### R2. preset の展開と押せないコンボ（Ruby）

決めたことの 5・6。`expandPreset` は `Application::Editor::ItemEdits` に op を足す（`item_edits/expand_preset.rb`）。
押せないコンボは Domain で判定し（`Domain::ProfileDiagnostics` の警告と、snapshot が使う判定。I/O なし）、`Application::Editor::Snapshot` の `combos` に `reachable` を足す。

触るファイル: `lib/cornix/domain/profile_diagnostics.rb`（+ 新しいファイル）、`lib/cornix/application/editor/item_edits*`・`snapshot*`、
`lib/cornix/interface/editor_server/handlers/profile_plan_item_edit.rb`（op の受け付け）、対応する spec と `spec/fixtures/protocol/`、`docs/validation.md`（警告を足す）

### E1. 図（拡張・Webview）

v0.3 で入れるものの 1・2・4・5・9・12（図の側）。位置の名前のボタンのホバー、出所の説明（ボタンの説明と、表示中に図の下に「名前は position_map.yaml のもの。
変えるとラベルが変わる。キーを押すとここで変えられる」の 1 行）、書いていない位置を NoKey と同じ枠に、コンボのボタンと強調、全レイヤーの表示、
`App#pickKey(onPick)`（図のキーを押すとそのキーの今のレイヤーの表記を返して選ぶ状態を抜ける。Esc か戻り値の関数で抜ける。選ぶ状態の間は図の上に「キーを押して選ぶ（Esc で戻る）」）。

触るファイル: `editors/vscode/src/webview/keyboardView.ts`・`app.ts`・`model.ts`・`tooltip.ts`（+ 新しいファイル `comboHighlight.ts` など）、
`editors/vscode/media/webview.css`（図の部分。足すときは `/* v0.3 図 */` の下）、対応する `test/unit/`

### E2. 欄と節（拡張）

v0.3 で入れるものの 6・7・8・12（コンボの画面の側）・13（ボタンとホスト）・14・15（一覧の印）。
コンボの画面の「図から選ぶ」は `pickKey` を options でもらい（main.ts で `(onPick) => app.pickKey(onPick)` を渡す）、選んだ表記をトリガーの末尾に足す（`insert`）。

触るファイル: `editors/vscode/src/webview/layerEditor.ts`・`keyInput.ts`・`presetPicker.ts`・`itemList.ts`・`macroEditor.ts`・`comboEditor.ts`・`shortcutEditor.ts`・`settingsEditor.ts`・`metadataView.ts`・`main.ts`、
`editors/vscode/src/editor/itemEdits.ts`・`prompts.ts`（展開の確認）、`editors/vscode/src/webviewMessages.ts`（要れば）、
`editors/vscode/media/webview.css`（欄の部分。足すときは `/* v0.3 欄 */` の下）、対応する `test/unit/`。偽のサーバー（`test/` の fake）の `expandPreset` も

## 段 3

- J1: 約束の版を `"0.3"`、拡張の版を `0.3.0` に。通しで使って直すもの。統合テストの追加
- J2: README（英日）・CHANGELOG・spec.md・roadmap.md（v0.3 を済みに）・`.claude/memories/`
- J: `.vsix` を作り、main への PR。Tetsuro の確認を待つ
