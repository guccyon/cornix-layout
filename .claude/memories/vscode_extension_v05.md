# VS Code 拡張 v0.5 の作業の知見

## サーバー（Ruby。R #111）

- 未使用の項目の中身は `Storage::UnusedFile#item`（`ConfigLoader#check_unused` が仮の index 0 で読んだ値オブジェクト。問題があれば nil）。
  Snapshot はレイヤー・マクロ・タップダンス・コンボの組み立てを「項目とファイル」を受け取る形（`Snapshot#layer(layer, file, ...)`・`Items#macro(item, file)` など）にして、使っている項目と同じものを使い回し、`index: nil` を重ねる
- `ProfileReading#files` は shortcuts.yaml がなければ `"shortcuts.yaml" => nil`（`SHORTCUTS_FILE`）。settings と同じ扱い
- `["index"]` の宛先は `Targets#add_indexes`（番号の付いた種類のファイルすべて。order を `['name', 'index', ほかのキー]` にして、行がなければ name の後、name がなければ最初のキーの前に足す）。
  まだない名前の `["shortcuts", 名前]` は `check: :new_shortcut`（名前の決まりは `StateCheck#new_shortcut_size`）。未使用のレイヤーのキーも宛先にした（use のあと保存前に編集できるように）
- use / unuse / setIndex と create（shortcut）は `ItemEdits#plan_pending`: params の changes を `PlanEdits::Draft` で当てた reading で操作を決め（`Indexing` の 3 つのクラス）、
  返す Change も当てた reading で diagnostics を出す。版の食い違いはいつもディスクの reading と比べる（Draft の reading の files は当てたあとの版なので使わない）
- setIndex の番号の参照の書き換えは `ItemEdits::NumberedReference`（Macro(n) / M<n> / TapDance(n) / TD(n) / 0xHHHH）。照合は compile の照合ではなく「どの欄も同じ項目（マクロ・タップダンスはファイル）を指すか」（`verify_targets!`）。
  もとから定義のない番号を指す欄は比べない
- `ConfigRepository#locator` が address のたびに DiagnosticLocator を作り直して全ファイルを読み直していたので、Slots（全部の欄）が test_config で 4 秒かかっていた。
  中身の変わらない `FileSource::Memory` のときだけ使い回すようにして 0.05 秒になった（delete・unuse・setIndex の速さに効く）
- 適合テストのデータは `/tmp` などに置いた小さな生成のスクリプトで response を埋めた。エラーのデータは既存に合わせて `message` を書かない（偽のサーバーと文言が違うため）。
  偽のサーバーで通らなかったのは planEdits のショートカットの名前の検査だけで、`test/fake-server/server.ts` に 5 行足した
- コンテナでは `LANG=ja_JP.UTF-8 LC_ALL=C.UTF-8 RUBYOPT=-EUTF-8` を付けないと、実行の順によって文字コードで落ちる（v0.2 のメモのとおり。`LANG` だけだと config_editor_spec なども落ちる）

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

## ホスト（H #112）

- 番号の操作（use / unuse / setIndex）とショートカットの追加（create の shortcut）は `ProfileDocument#applyItemEdit` の入口で `isPendingItemEdit` に分け、
  `applyPendingItemEdit` が planItemEdit に `changes`（今の未保存の変更）を付けて送り、返った `changes` を 1 つの編集として足す。
  続けて押されても前の結果を当てた状態で決めるよう、この操作は 1 つずつ通す（`pendingItemEdit` の Promise の鎖）。返るまでに snapshot か未保存の変更が変わったら 2 回まで決め直す
- 1 つの編集（元に戻す・やり直しの単位）の作り方は `src/editor/editHistory.ts` の `recordEdit` に出した（vscode に依存しないので vitest で undo / redo を確かめられる）。
  `applyChange` もこれを通る（Change 1 つの編集）。並びが変わっていなければ前後の配列に戻し、変わっていれば Change ごとに（undo は後ろから）今の snapshot に対して当てる
- 保存済みの値（`snapshotValueAt`）の直し: `["index"]` は項目の index（未使用は snapshot.unused にあって null）、未使用の項目の中身も引く
  （引かないと、取り出したレイヤーのキーを変えた変更が保存のときに「場所が見つからない」になる）、まだないショートカットの名前は null（shortcuts.yaml が files にあれば。版が null でもよい）。
  null を返すので、当て直し（rebase.ts）でも「外で同じ名前を足した」は選ばせる・何もなければそのまま当て直す、になる。ファイルが消えた index は undefined で当て直せない
- `PendingChanges#add` / `assign` は、行を消したあとの set を残す決まり（注記のため）を `["index"]` では使わない（注記がない）。未使用にして同じ番号で取り出し直すと何も持たない
- 確認のダイアログは unuse で references があるときだけ（`describeUnuse`。文は「未保存の変更に積みます」で、「すぐにファイルに書きます」は出さない）。編集の名前は `pendingItemEditLabel`（「レイヤー iPad Base を使い始める」）。
  番号の操作はファイルで指すので、見出しの名前は snapshot（使っているもの・未使用のもの）から引いて `itemEditTitle(edit, name)` に渡す
- 統合テストはコンテナでは今も走らない（update.code.visualstudio.com がプロキシで JSON を返さない）。足した 2 つ（ショートカットの追加の undo → redo → 保存、未保存の変更があるときの unuse の確認）は CI で見る
- 偽のサーバーの表記の解釈は fixtures.ts の表にある文字列だけを読む（ない表記は構造の error）。統合テストで保存まで通す値は表にあるものにするか表に足す。
  `Command + Shift + ]` が表になく、planEdits が構造の error を返して runSave が止まり、CI の統合テストが「保存 を待ちきれませんでした」で落ちた。単体テストでも planEdits の `structureErrors` が空であることまで確かめると、コンテナで気づける

## 画面の節（I #114）

- 節の項目は、番号のある種類（マクロ・タップダンス・コンボ）ではファイル、ショートカットでは名前で見分ける（`ItemSection#itemKey`）。
  未使用の項目と名前が重なることがあり、名前では選んでいる項目を取り違える。テストの `select(name)` と `selected` は名前のまま
- 一覧は `arrangeItems(snapshotItems(snapshot, kind), pending).used`。未保存の変更の知らせも `snapshot` のメッセージ（同じ snapshot と新しい pending）で
  `update` に来るので、「頼んだ項目が一覧に現れたら選ぶ」（`wanted`。use はファイル、create・rename は名前）は render の中だけで足りる
- 見出しの番号は未保存の `["index"]` で変わるが、欄は作り直さない（shape に番号を入れない）。描いた時の項目を閉じ込めず、`currentItem` から読む
  （閉じ込めると古い番号のまま。番号の選択の「今」もずれる）
- 未保存で足したショートカット（`["shortcuts", 名前]` の set で snapshot にない名前）は `itemsModel.ts` の `shortcutItems` で値 null の項目にして並べる。
  `shortcutView` の保存済みの値は空になり、未保存の値で描ける
- マクロの「同梱から」は create の `preset`（12.5 に前からあり、Ruby も対応済み）で作る。名前はラベル、重なれば名前の欄を preset 付きで開く。
  名前の重なりは使っている項目・未保存のショートカット・未使用の項目の名前で見る
- 「…」の操作は選んだ後で `MoreMenu` が閉じてボタンにフォーカスを戻してから呼ぶので、名前の欄や番号の選択はその後でフォーカスを取れる。
  番号の選択は見出しのすぐ下の `.item-index-slot` に置き、欄の作り直し（`disposeDetail`）で閉じる
- `media/webview.css` の `.shortcut-copy`（v0.3 の「同梱からコピー」）は使わなくなったが、末尾以外は触らない取り決めなので残した（J で消せる）

## 仕上げ（J #115）

- 約束の版を `"0.5"`・拡張を 0.5.0 に上げた場所は v0.4 のメモの「約束の版」の一覧のとおりで足りた（`sed` でまとめて置き換え、`grep "'0\.4'\|\"0\.4\"\|0\.4\.0"` で残りなし）。
  それに加えて `spec/support/device_protocol_fixtures.rb`・`spec/fixtures/protocol/device/lifecycle/*.json`・`pendingItemEdits.test.ts`・`fakeServerUnused.test.ts` にも版がある。
  `connection.test.ts` の「新しい版だけのサーバー」は今の版より新しく（`['0.6', '1.0']`）。`Cornix::VERSION` は上げない（CHANGELOG の [Unreleased] に足すだけ）
- 通しの確認は、`bin/cornix serve --root <作業用>` を Python の小さなクライアント（Content-Length の枠）で動かした。作業用のプロファイルは authors_config の写しに、
  未使用のレイヤー・マクロ・タップダンスと、番号の参照（`Macro(2)` / `M5` / `TD(4)`）を足し、`layers/9_empty.yml` を消して空きを作った。
  use ×3 → setIndex ×3（未保存の番号との入れ替えを含む）→ create shortcut → unuse → planEdits → 当てる（列は UTF-16）→ saved → open し直す、が通り、
  compile の結果を元と「マクロ・タップダンスの中身」で比べても、動かした番号のほかは同じだった
- 気づいたこと（直していない）: unuse で名前の参照（`Macro('名前')`）が壊れると、未保存の変更を当てた reading が「読めない値あり」（`ProfileReading#complete?` が false）になり、
  そのあとの項目の操作（use / unuse / setIndex / create shortcut も、すぐ書く create / delete / rename も）が「プロファイルに読めない値があるので、項目を操作できません」で断られる。
  名前の参照が見つからないことは解析の失敗なので、ADR 021 の扱い（v0.4 の delete でも同じ）。参照を直せば戻る。文言は「保存してください」だが未保存の変更で直してもよい
- `media/webview.css` の `.shortcut-copy`（v0.3 の「同梱からコピー」）を消した。`.key-input-presets .preset-picker-panel` と並べて書いていた 1 か所も外す
- .vsix は `npm run package`（`vsce package --no-dependencies`）。中身は 32 ファイル（`extract.mjs` は入らない）。`/mnt/project-files/` へは `mkdir -p …/` と `cp` で置けた

## 足したレイヤーの空の行（`row1: {}`）への書き込み（Tetsuro の確認で見つかった）

- create（layer）は `YamlFile.dump` で空のグループを `row1: {}`（フロー表記）と書く。`YamlDocument#insert` はフロー表記の中への挿入を `EditNotLocal(:flow_insert)` にしていたので、足したレイヤーのキーを決めると保存できなかった（v0.4 から）
- 中身のない 1 行の `{}` だけは値なしの見出しと同じ扱い（`insert_under_empty`。`{}` を消して下に字下げして足す）にした。中身のあるフロー表記は今までどおり止める。適合テストは `profile_plan_edits/insert_into_empty_flow.json`
- 偽のサーバーと単体テストでは create（layer）のあとにキーを書く流れがなかったので気づけなかった。新しい形のファイルを書く操作を足したら、そのファイルに planEdits を通すテストも足す

## 読めない値があるときの項目の操作（ADR 024。Tetsuro の確認で見つかった）

- 未使用にした項目を名前で指す欄（`Macro('X')` で X が未使用）は「未使用です」の読めない値になり、`ProfileReading#complete?` が偽になる。以前は `Operation#call` が complete? でなければ全部止めたので、取り出し直すこともできなかった
- `Operation#requires_complete?` を足し、前後の compile を比べる Rename・RenamePosition・ExpandPreset だけ真。ほかは読めない値を NoKey にした profile で決める。setIndex の照合（`verify_targets!`）も `after.ok?` で比べる（読めない欄は前後とも NoKey）

## サーバーの reorder とレイヤーの参照の追従（R2。ADR 025）

- setIndex と reorder は `Renumbering`（indexing.rb）にまとめた。`moves`（元の番号 => 新しい番号）を一度に作り、各欄を元の番号で引いて書き換えるので、入れ替わる番号どうしでも取り違えない（欄ごとに 1 回だけ見る）
- レイヤーの番号は Domain の `Keycode.layer_index` ではなく、`KeycodeCodec#layer_of` / `#with_layer`（16bit 値の LT・LM・レイヤー操作の欄）で読む。
  `LT1(NoKey)` のような基本キーでない LT は Raw に読まれて `layer_index` では落ちるが、番号を付け替えると指す先が変わるので数える必要がある。unuse / delete の数え方（`layer_index`）は変えていない
- 照合（`ItemEdits#verify_targets!`）では、レイヤー操作の指す先を `[:layer, レイヤーのファイル, 番号を 0 にした 16bit 値]` にした。中身のレイヤー同士を比べると、中のレイヤー操作も書き換わるので一致しない（spec の `expect_moved_layers` も番号を除いて比べる）
- `targets` で「定義のない番号を指す」（nil）と「レイヤー操作でない」を分けるのに false を返している（`nil || keycode` にすると壊れた参照まで比べてしまう）
- reorder で使っている項目の番号が重なっていたら `"edit"` で止めた（どちらを指す参照か決まらない）。偽のサーバーはこれを確かめないので、適合テストのデータにはせず spec だけ
- 適合テストのデータは、`baseVersions: "AUTO"` と書いたリクエストを流して、返った Change の宛先の版で埋める小さなスクリプト（scratchpad。ProtocolFixtures.prepare / run を使う）で作った。
  `JSON.pretty_generate` で書けば既存のデータと同じ形になる（空の配列は今の json では `[]`）
- 拡張の偽のサーバー（P2）は reorder のエラー（edit.files）を同じに返すので、`protocolFixtures.test.ts` は直さずに通った
