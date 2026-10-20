# VS Code 拡張 v0.2 の作業の知見

v0.2（すべての設定ファイルを画面だけで編集できる）の作業で分かったこと。v0.1 までの知見は [vscode_extension.md](vscode_extension.md)、
作業の分け方と段 2 の PR で決めたことの一覧は docs/vscode-extension/tasks-v0.2.md。

## クラウドのコンテナでの確かめ方

- `bundle exec rspec` はこのコンテナでは動かない。rspec-core の exe を直接 ruby で動かす:
  `LANG=ja_JP.UTF-8 LC_ALL=C.UTF-8 RUBYOPT=-EUTF-8 bundle exec ruby $(bundle info rspec-core --path)/exe/rspec`
  - コンテナに ja_JP.UTF-8 のロケールがないので、`RUBYOPT=-EUTF-8`（と `LC_ALL=C.UTF-8`）がないと、実行の順によって end_to_end などが文字コードの違いで落ちる
  - `spec/storage/yaml_file_spec.rb:61` は手元（コンテナ）の Ruby 3.3 の psych のせいで作業の前から落ちる。CI の Ruby 4.0 では通る。この 1 件だけなら問題なし
- 拡張の統合テスト（`npm run test:integration` / `:ruby`）はコンテナでは走らない（VS Code の配布元 update.code.visualstudio.com がプロキシで 403）。
  ビルドが通るところまで確かめ、統合テストは PR の CI（vscode.yml の `node`）で初めて走る。統合テストを足した PR は CI の結果を見てから直す前提で出す
  （E3 では、undo で作り直す変更に `op: "set"` が付いて v0.1 の形の期待と合わないことが CI で分かった）

## 偽のサーバー（editors/vscode/test/fake-server/）

- `yamlLines.ts` の `quote`（書く値に引用符が要るか）で `\w` を使うと、JavaScript の `\w` は `u` フラグを付けても ASCII だけなので、
  日本語の値（`description: 角括弧`）が `"角括弧"` と引用符付きになり、本物のサーバー（`ScalarFormat`）と食い違って統合テストが落ちた。`[\p{L}\p{N}_]` を使う
- 項目の説明（`description:`）はディスクから読む。fixtures の固定の説明のままだと、保存したあとの snapshot で書いた説明が未保存の変更として残る。
  ほかの中身（マクロの手順など）はディスクから読まない（ファイルの一覧と `name:` `index:` `description:` の行だけ）ので、書き換えのあとも fixtures のまま
- 偽のサーバーはまず `value` の型を見るので、`op: "remove"` などの error のデータは Ruby と答えが食い違う。そういうものは適合テストのデータ（`spec/fixtures/protocol/`）に入れず RSpec に書いた（R2）

## 並列の PR をぶつけない

- 段 2 の 7 つの PR（R0〜R3、E1〜E3）は、段 1 で約束（protocol.md の 12、#56）と型（`protocol.ts` の `AnyChange` など、`webviewMessages.ts` の `edit` / `itemEdit` / `pending`、#57）を
  先にマージしてから並列に始めた。どの作業も「約束と型は変えない、触るファイルを決める」で進め、約束の曖昧なところは各 PR の「補足」に解釈を書いて、段 3 でまとめた
- 画面（E1・E2）とホスト（E3）の間の新しいメッセージを段 1 で足しておいたので、E1・E2 は E3 を待たずに `pending` を当てる側を作れた（`pending` がなければ v0.1 の `changes` を使う）
- 型の不足（`DraftParams.changes` が `Change[]` のまま、候補の params の渡し方が E1 と E2 で違う）は、その段では型だけ合わせて段 3 にまとめて回した

## profile/planItemEdit の解釈（R3、#63）

- `baseVersions` は中身の変わるファイル（作る・消す・改名）だけ比べる。今あるファイルで `baseVersions` にないものは `-32602`（`field: "baseVersions"`）、作るファイルは省くか `null`。
  ただし宛先の誤り（`-32602`）や `-32061` のときは、送られたすべての版を先に比べて、食い違えば `-32060` を返す（古い画面のせいで名前が見つからないのを版の食い違いとして知らせる）
- 確かめる順: params の形 → 宛先と名前（`-32602`）/ 局所的に書けるか（`-32061`）→ 書き換えるファイルの版（`-32060`）→ `baseVersions` の抜け（`-32602`）→ compile の照合（`-32061` verify）
- `files` の形: 操作の対象のファイルが先、参照を置き換えたファイルはそのあと（読んだ順）。`create` はいつも入れ、`delete: true` と `renameTo` はそのときだけ。
  1 つのファイルへの書き換えが 1 回ならその範囲、2 回以上なら `TextEdit.diff` で元の中身との差分にまとめる。改名するファイルの `edits` は元のファイルでの位置
  （拡張は先に `renameFile` してから新しい名前に当てる）
- 参照の置き換えは `Storage::ConfigEditor.reference_pattern` / `replace_references_in`（テキストの上で呼べるように分けた。`Shortcut` も扱う）。docs/rename.md の「部品」

## 未保存の変更は 1 本の並び（E3、#65。ADR 017）

- `PendingChanges` は `AnyChange` を当てる順に並べた 1 本の並び。並び（マクロの手順・キー、コンボのキー）の中を指す Address は、前の変更を当てたあとの位置で数える
- 畳み方: 並びの外の `set` / `remove` は、同じ場所（Address と `field`。注記は割り当てと別の場所）の前の変更を**その位置で**置き換え、保存済みの値に戻れば持たない。
  並びを指す Change（`insert` / `move` と、道筋に番号のある `set` / `remove`）は畳まずに足した順のまま
- 順の決まり: まだ書いていない位置の割り当ての `set` は、同じ行の注記の `set` より前に入れる（注記だけの `set` はサーバーが `-32602`）。
  書いていない位置の `set` のあとの `remove` は両方を打ち消す。行を消す `remove` のあとの `set` は `remove` を残す（消した注記を戻さないため）
- undo・redo は編集の前後の並び（配列そのもの）に戻す。保存や外での変更で並びが変わったあとは、並びの外は値で当て直し、並びの `insert` / `move` は逆の Change を足す
  （要素の `set` / `remove` は前の値が分からないので戻さない）。外で変わったファイルに並びの Change があれば、そのファイルの Change はまとめて「当て直せないもの」
- 画面へは snapshot と一緒に `pending`（全部）を送り、`changes` は v0.1 の形（並びの外の `set` だけ）のまま残した

## 統合テストで外からファイルを書くとき（J1 で分かったこと）

- サーバーを止めている間でも、画面の要求（keycode/inspect の中継など）が来ると `ensureStarted` がサーバーを起こし、`profile/open` が走る
- `vscode.workspace.fs.writeFile` は書いている途中（切り詰めた直後）の中身を読まれうる。外での変更は一時ファイルに書いてから置き換える（`support.ts` の `replaceOutside`）。
  決まった時間を待つのではなく、見張りがそのファイルの知らせを送り終えるのを待つ（`ProfileWatcher#onDidSend`）
