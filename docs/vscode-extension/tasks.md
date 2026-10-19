# v0.1 の作業の分け方と契約

[roadmap.md](roadmap.md) の「v0.1 の進め方」2〜10 を、責務の境界で分けた作業にしたもの。
同じ段の作業は**同じファイルを編集しない**ので並列に進められる。次の段は、前の段のうち依存する作業がマージされてから始める。

## 共通ルール

- 統合ブランチは `feature/vscode-extension`。作業ごとに `<repo-root>/<ブランチ名>` の worktree を作り、PR はすべて `feature/vscode-extension` 向けに出す。main には直接入れない
- コミット前に `LANG=ja_JP.UTF-8 bundle exec rspec` がすべて通ること（拡張の作業は `editors/vscode/` のテストも）。新しいクラスには spec を書く
- [architecture.md](../architecture.md) の層と依存の向きを守る（Interface は Application だけを参照する。`spec/architecture_spec.rb` が検査する）
- 約束は [protocol.md](protocol.md)。**ここに書いた契約（クラスと公開メソッドの形）は勝手に変えない。** 変える必要があれば PR の説明で提案する
- README.md / README.ja.md は触らない（最後にまとめて書き直す）。実機への書き込みはしない
- 各作業が持つファイルは下の「触るファイル」だけ。ほかの作業のファイルに手を入れたくなったら、PR の説明に書いて相談する
- `lib/cornix.rb` はディレクトリの下を自動で require するので、新しいファイルを足しても編集しなくてよい

## 段 1（並列）

### A. サーバーの土台（ブランチ `vscode/server-foundation`、roadmap の 2）

`cornix serve`、Content-Length の枠、JSON-RPC の振り分けとライフサイクル、エラーの code、`profile/list` / `profile/close`、適合テストの仕組み。

触るファイル: `lib/cornix/interface/editor_server/**`、`lib/cornix/interface/cli/commands/serve.rb`、`lib/cornix/interface/cli/main.rb`（COMMANDS に 1 つ足すだけ）、
`lib/cornix/application/editor/workbench.rb`・`list_profiles.rb`、`spec/interface/editor_server/**`、`spec/application/editor/{workbench,list_profiles}_spec.rb`、
`spec/support/protocol_fixtures.rb`（`spec/spec_helper.rb` で読み込む）、`spec/fixtures/protocol/lifecycle/**`・`profile_list/**`

```ruby
# Interface 層
Interface::EditorServer::Server.new(workbench:, input: $stdin, output: $stdout, error: $stderr).run
Interface::EditorServer::Framing.read(io) #=> Hash | nil（EOF） / .write(io, message)
Interface::EditorServer::RpcError.new(code, message, data = nil)       # ハンドラが送出すると JSON-RPC のエラーになる
Interface::EditorServer::ErrorCodes::INVALID_PARAMS / PROFILE_NOT_FOUND / VERSION_CONFLICT / EDIT_NOT_LOCAL ...  # protocol.md の 9.
# メソッドはハンドラのクラス 1 つにつき 1 つ。サブクラスを定義すると登録される（後の作業はファイルを足すだけで、振り分けの表を編集しない）
class Interface::EditorServer::Handlers::ProfileOpen < Interface::EditorServer::Handler
  rpc 'profile/open'                                                    # 通知なら notification 'workspace/didChangeFiles'
  def call(params, context) = ...                                       # => result（Hash）。context.workbench / context.notify(method, params)
end
Interface::EditorServer::Handler.registry #=> { 'profile/open' => ProfileOpen, ... }

# Application 層
Application::Editor::Workbench.new(root:, env_factory: ->(workspace) { Environment.for(workspace) })
  #open(dir) #=> OpenedProfile(id:, dir:, name:, env:)（id は "p1", "p2" ...）。dir がなければ ProfileNotFound
  #fetch(id) #=> OpenedProfile（なければ ProfileNotFound） / #close(id)
  #versions(id) #=> Hash（file => FileVersion。後の作業が読み書きする「知っている版」）
Application::Editor::ListProfiles.new(root:).call #=> { profiles: [{ dir:, name: }], default: dir | nil }
Application::Editor::ProfileNotFound < Cornix::Error
```

- 適合テスト: `spec/fixtures/protocol/<メソッド>/<名前>.json`（`{ "setup": { "profile": "<spec/fixtures の設定>" }, "request": {...}, "response": {...} }`）を読み、
  protocol.md の 8.2 の比べ方で確かめる共通の RSpec のヘルパー。後の作業はデータを足すだけで使えるようにする

### B. 値の場所と書き換え（ブランチ `vscode/yaml-edits`、roadmap の 5 の Storage 部分）

YAML のノードの位置、値の部分だけの書き換えと挿入、中身を差し替えて読む口、モデル内のパスから Address への写像。

触るファイル: `lib/cornix/storage/yaml_document.rb`（+ `yaml_document/`）、`lib/cornix/storage/file_version.rb`、`lib/cornix/storage/file_source.rb`、
`lib/cornix/storage/text_range.rb`・`text_edit.rb`・`edit_not_local.rb`、
`lib/cornix/storage/config_loader.rb`・`config_repository.rb`・`config_files.rb`・`diagnostic_locator.rb`・`problem.rb`、対応する `spec/storage/**`

```ruby
Storage::FileVersion.of(bytes) #=> "sha256:<小文字の 16 進>"
Storage::YamlDocument.parse(text)
  #range(path) #=> Storage::TextRange(start_line:, start_character:, end_line:, end_character:) | nil   # 列は UTF-16 のコード単位
  #scalar(path) #=> String | nil（その場所の値の表記。注記付きの形なら key の値）
  #replace(path, text) #=> [Storage::TextEdit(range:, new_text:)]   # 値の部分だけ。引用符は protocol.md の 6.3
  #insert(path, text, order:) #=> [Storage::TextEdit]               # order: 同じ親の中のキーの並び（position_map の順など）
  # 書き換えられなければ Storage::EditNotLocal（reason: :multiline | :anchor | :flow_insert, path:）
Storage::TextEdit.apply(text, edits) #=> String
Storage::FileSource::Disk.new(dir) / Storage::FileSource::Overlay.new(base, { rel => text })   # read(rel) / exist?(rel) / list(kind)
Storage::ConfigRepository.new(dir, ..., source: FileSource::Disk.new(dir))   # source を差し替えると保存前の中身で読む（既定は今までどおり）
Storage::DiagnosticLocator#address(model_path) #=> [file, path(Array)] | nil   # Address の形。注記付きでも .key を付けない
Storage::Problem#path #=> Array                                              # location（"sequence[1].keys[0]"）を道筋にしたもの
```

### C. 表示と候補（ブランチ `vscode/candidates`、roadmap の 3 の表示部分と 4）

キーの表示の文字・種類、候補の表と並べ方、候補の分類のデータ、「この入力ならこの候補」のデータのテスト。

触るファイル: `lib/cornix/mapping/key_display.rb`、`lib/cornix/mapping/candidate_catalog.rb`（+ `candidate_catalog/`）、`data/keycode_categories.yaml`（新規）、
`spec/mapping/{key_display,candidate_catalog}_spec.rb`、`spec/fixtures/candidates/**`

```ruby
display = Mapping::KeyDisplay.new(catalog:, notation:)
display.kind(keycode) #=> "basic" | "modified" | ... （protocol.md の KeyKind）
display.display(keycode, references:, layer_names: { 1 => 'Symbols' }) #=> { label:, tap: nil | String, hold: nil | String }
candidates = Mapping::CandidateCatalog.new(catalog:, notation:, shortcut_catalog:, categories: CandidateCatalog.default_categories,
                                           icon_for: ->(app_name) { nil })   # アイコンは段 2 で D の表をつなぐ
candidates.search(query:, context: 'layerKey' | 'encoder', references:, layer_names:, limit: 50)
  #=> CandidateCatalog::Result(items: [Candidate(insert_text:, label:, detail:, category:, icon:, warning:)], truncated:)
candidates.shortcut_tree #=> [{ name:, icon:, categories: [{ name:, items: [{ label:, insert_text:, text:, macro: }] }] }]
```

- `spec/fixtures/candidates/*.yaml` は `{ context:, query:, expect: [insert_text, ...] }`（先頭から順に一致）の並び。TypeScript 版も同じデータで確かめる（ADR 004）

### D. アイコンと QMK 設定の説明のデータ（ブランチ `vscode/data-icons`、roadmap の 6）

触るファイル: `data/shortcut_icons.yaml`（新規）、`data/qmk_settings.yaml`、`lib/cornix/mapping/app_icon_catalog.rb`、`lib/cornix/mapping/qmk_setting_catalog.rb`、
`spec/mapping/{app_icon_catalog,qmk_setting_catalog}_spec.rb`

```ruby
Mapping::AppIconCatalog.default.icon(app_name) #=> "simple-icons:figma" | "material-icon-theme:vscode" | "badge:CS" | nil
Mapping::QmkSettingCatalog::Definition#description / #default   # data/qmk_settings.yaml に足した説明と既定値（なければ nil）
```

- `data/shortcuts/` のすべてのアプリにアイコン ID があることを spec で確かめる（[spec.md](spec.md) の「アイコン」）

### E. 拡張の土台と CI（ブランチ `vscode/extension-scaffold`、roadmap の 7 と 10 の CI）

触るファイル: `editors/vscode/**`（ただし `src/webview/` の画面の中身は段 2 の G）、`.github/workflows/**`、`.gitignore`

- esbuild・vitest・@vscode/test-electron、`vscode-jsonrpc` でサーバーを起動してつなぐ（`cornix.path`、既定はワークスペースの `bin/cornix`、なければ PATH、見つからなければ設定を開くボタン）
- `src/protocol.ts`: protocol.md の型をそのまま TypeScript にしたもの（以降の作業はこれを使う）
- コマンド「Cornix: プロファイルを開く」とアクティビティバー（`profile/list`）、`cornix-profile:` の仮想ドキュメントとカスタムエディタの骨組み（ADR 015。画面は仮のもの）
- 段 2 の画面の作業がサーバーなしで進められるよう、protocol.md の例を返す偽のサーバー（テスト用）
- CI: 変更したパスで Ruby（今の rspec）と Node（`editors/vscode/`）を分ける

## 段 2（A・B・C・D・E のマージのあと、並列）

### F. 読む・候補・解釈のユースケース（`vscode/read-api`、roadmap の 3・4 のつなぎ）

`profile/open`・`keycode/candidates`・`keycode/shortcutTree`・`keycode/inspect` の Application のユースケースとハンドラ、適合テストのデータ。
触るファイル: `lib/cornix/application/editor/{snapshot,candidates,inspect,profile_reading,key_values,diagnostics,unknown_context}*.rb`、
`lib/cornix/interface/editor_server/handlers/{profile_open,keycode_*}.rb`、対応する spec、`spec/fixtures/protocol/{profile_open,keycode_*}/**`
（レビューで、Shortcut(...) の見分けに `Mapping::KeycodeNotation#shortcut_name`、版と読み込みをそろえるのに `Storage::FileSource::Memory` を足した）

```ruby
Application::Editor::Snapshot.new(workbench).call(id) #=> Hash（ProfileSnapshot）。workbench.versions(id) を更新する
Application::Editor::ProfileReading.read(env)         # 設定ファイルを 1 回読んだもの（#files 版、#profile、#problems、#repository、#document(rel)）
Application::Editor::KeyValues.new(env:, profile:)    # #build(keycode, text:, note:) → KeyValue、#parse(text)
Application::Editor::Diagnostics.new(reading, capabilities).call   # → [Diagnostic]（Address と range 付き）
Application::Editor::UnknownContext.check!(context)   # 知らない context（Interface が -32602 にする）
Storage::FileSource::Memory.capture(dir)              # ある時点の設定ファイルの中身だけを見せる（#files は { rel => バイト列 }）
Mapping::KeycodeNotation#shortcut_name(text)          # Shortcut('名前') の形なら名前（parse と同じ読み方）
```

- E からの申し送り: `editors/vscode/src/protocol.ts` は protocol.md の JSON の例から型を決めた。次の点は protocol.md の 5.2〜5.5 に書き足して Ruby と合わせる
  - レイヤーの `description` は書いていなければ `null`（`string | null`）。`encoders` は `left` / `right` とも必ずあり、各操作の `value` は割り当てがなければ `null`
  - `keycode/inspect` の `description` は読めないとき `null`、`keycode/candidates` の `limit` は省ける（省いたときの数を決める。偽のサーバーは 50）、`keycode/shortcutTree` のアプリの `icon` はなければ `null`
  - 偽のサーバー（`editors/vscode/test/fake-server/`）の vitest は `spec/fixtures/protocol/` の `lifecycle` と `profile_list` を流す。F で足すディレクトリも流せるなら `SUPPORTED` に足す

### G. 拡張の画面（`vscode/extension-ui`、roadmap の 8）

キーボード図とレイヤーの編集画面、キー入力欄（候補・`typed`・警告）、マウスを載せたときの説明、アイコン（SVG とライセンス表記を同梱）。
触るファイル: `editors/vscode/src/webview/**`、`editors/vscode/media/**`。サーバーとのやりとりは E の `protocol.ts` と偽のサーバーで確かめる

## 段 3（F・G のマージのあと、並列）

### H. 検証・書き換え・外での変更のユースケース（`vscode/write-api`、roadmap の 5 のつなぎ）

`profile/validate`・`profile/planEdits`・`profile/saved`・`workspace/didChangeFiles` → `profile/didChange`。
触るファイル: `lib/cornix/application/editor/{validate_draft,plan_edits,saved,file_changes}*.rb`、`lib/cornix/interface/editor_server/handlers/{profile_validate,profile_plan_edits,profile_saved,workspace_did_change_files}.rb`、
対応する spec と `spec/fixtures/protocol/**` のそのメソッドの分

- B からの申し送り: QMK 設定の値は `data/qmk_settings.yaml` の型に直してから `YamlDocument#replace` / `#insert` に渡す（文字列だと `"180"` と書かれる）。ファイルへの変更が 1 つならその結果をそのまま、複数なら 1 つずつ当てて読み直し `TextEdit.diff` で元のテキストに対する書き換えにする
- `Storage::Problem#path` は位置の文字列から作るので、キーに `.` `[` `]` を含みうる `shortcuts.yaml` の問題では道筋を信じず Address と range を付けない
- F からの申し送り: 保存前の中身での検証は `ProfileReading` の読み方（`FileSource::Memory` に変更を `Overlay` で重ねる）と `Diagnostics` を使える。
  `keycode/inspect` の意味検証は、値をコンボの出力に置いて `Profile#diagnostics` を回している（規則がキーの場所によらないことに頼る）。
  Domain に 1 つのキーコードだけを確かめる公開メソッド（`Profile#keycode_diagnostics(keycode, capabilities)` など）を足したら置き換える
  （`spec/application/editor/inspect_spec.rb` がレイヤーのキーに置いたときの結果と比べている）

```ruby
Application::Editor::PlanEdits.new(workbench).call(id, base_versions:, changes: [PlanEdits::Change(file:, path:, value:)])
  #=> { files: [{ file:, baseVersion:, create:, edits: }], diagnostics: }   # 失敗は PlanEdits::VersionConflict / InvalidChange / NotLocal
Application::Editor::ValidateDraft.new(workbench).call(id, base_versions:, changes:) #=> { diagnostics: }
Application::Editor::PlanEdits::Draft.new(reading, settings_catalog).apply(base_versions, changes)
  #=> Result(files: [FileEdit], texts: { file => 当てたあとの中身 }, reading: 当てたあとの中身で読み直した ProfileReading)
Application::Editor::PlanEdits::Targets.new(reading, settings_catalog).fetch(file, path)   # profile/open に出てくる Address だけ
Application::Editor::Saved.new(workbench).call(id, files:) #=> Result(snapshot:, changed:)（changed が空でなければ profile/didChange）
Application::Editor::FileChanges.new(workbench).call(paths) #=> [{ profileId:, files:, snapshot: }]（profile/didChange の params）
Application::Editor::ProfileReading#text(rel) / #with_files({ rel => text })   # H で足した（保存前の中身を重ねて読み直す）
```

- H で決めたこと（protocol.md の 5.6・6.1・6.4・7 の「決めたこと」に書いた）: `baseVersions` はいまのディスクの版と比べる、
  変更のあるファイルはすべて `baseVersions` に要る、確かめる順は -32060 → -32602 → -32061、`profile/validate` も書き換えられない変更は -32061、
  `files` は書き換えのあるファイルだけ、`profile/didChange` は `profile/saved` の応答の前に届く、`workspace/didChangeFiles` は知らせに入っていない設定ファイルの違いも入れる
- 書き換えたあとの compile の結果が手で直したときと同じことは `spec/application/editor/plan_edits_compile_spec.rb`（authors_config の写し）が確かめる
- I への申し送り: 偽のサーバーは `spec/fixtures/protocol/` の `profile_validate` `profile_plan_edits` `profile_saved` `workspace_did_change_files` を流せる。
  外で変わったときに `profile/didChange` を送る場合は、適合テストのデータに途中でファイルを書き換える手順がないので入っていない
  （`setup.before` にファイルを書く手順を足すなら protocol.md の 8.2 と `spec/support/protocol_fixtures.rb` を変える相談が要る）

### I. 拡張の保存と外での変更（`vscode/extension-save`、roadmap の 9）

dirty と Ctrl+S（protocol.md の 6.2）、外での変更の扱い（7.3）、QMK 設定とメタデータの表示。
触るファイル: `editors/vscode/src/`（`webview/` の QMK 設定・メタデータの部品を含む）。G の画面の部品は使うが書き換えない（要るときは相談）

- E からの申し送り（`editors/vscode/src/editor/profileDocument.ts` の TODO）
  - 保存: `ProfileDocument#save` に 6.2 の流れを入れる。3〜4 の間は `document.watcher.hold()` で見張りの知らせを溜める
  - 元に戻す: 編集ごとに前の値と新しい値を持ち、snapshot の値と同じになれば変更から外す作りにしてある。保存のあとの undo はディスクの値に対する変更として残る
  - 外での変更（7.3）: 「外の変更を残す」は `changes.clear()` ではなく revert を通す（CustomEditor の dirty は保存か revert でしか消えない）
  - ホットエグジット: バックアップに変更を作ったときの `files` を入れてあり、戻すと `document.backupFiles` に入る。今の `snapshot.files` と違えば 7.3 と同じ扱いにする

## 段 4

### J. 通しの確認（roadmap の 10）

.vsix を作って手元で入れ、自分のプロファイルで「レイヤーを画面だけで直して保存でき、compile の結果が手で直したときと同じ、変えていない行が変わらない」を確かめる。
直しが要れば小さな PR にする。そのあと `feature/vscode-extension` → main の PR を作る
