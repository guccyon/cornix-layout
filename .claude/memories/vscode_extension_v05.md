# VS Code 拡張 v0.5 の作業の知見

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
