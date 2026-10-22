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
