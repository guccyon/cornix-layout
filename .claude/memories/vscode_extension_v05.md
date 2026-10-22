# VS Code 拡張 v0.5 の作業の知見

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
