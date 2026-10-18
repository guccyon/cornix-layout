# ドメインアーキテクチャへの作り直し（refactor/domain-architecture）の知見

旧コード（`models/`, `converters/`, `loaders/`, `writers/`, `compiler.rb`, `decompiler.rb`, `keycode_parser.rb`,
`modifier_expression_compiler.rb`, `model_validator.rb`, `file_renamer.rb`, `device/keyboard.rb` など）はすべて削除し、
`lib/cornix/{domain,image,mapping,planning,storage,device,application,interface}` に置き換えた。
設計は [docs/architecture.md](../../docs/architecture.md)、公開メソッドの契約は [docs/tasks.md](../../docs/tasks.md)。

## 正解の基準

- 旧コードで求めた値を消す前に `spec/fixtures/expected/` に保存し、spec はそれと比べる
  （`vial_codes.tsv.gz` = 全 16bit 値の旧 .vil 表記、`config_keycodes.yaml` = 設定の全キーコードの旧値、
  `macro_buffers.json`, `fake_device_snapshot.json`, `mcp_tools.json`, `*.values.json`）
- authors-keymap の config（`spec/fixtures/authors_config`）を旧コードで compile した結果が `spec/fixtures/authors_baseline.vil`。
  `spec/end_to_end_spec.rb` が 16bit 値で一致することを CI でも確かめる。authors-keymap の worktree は不要
- .vil どうしは文字列ではなく 16bit 値（`Image::DeviceImage`）で比べる。同じ値の別表記（`KC_PGDN` / `KC_PGDOWN`）があるため

## 旧実装から変えた振る舞い（意図的）

- 修飾キー式: Vial が読めない名前（`LCS`, `LCSG`, `RCAG` …）を .vil に書いていた・右 Ctrl+Shift+Alt を MEH にしていたのを直した。
  左右の修飾キーの混在はエラー
- `TO(n)` は書き方によらず `0x5200 + n`（旧実装は表にない書き方だけ ON_PRESS を足していた）
- decompile はエイリアスのない修飾キー付きキーを修飾キー表現で書き、設定は名前の形で書く（旧実装は QMK 形式・QSID の番号）
- `Combo(...)` 参照と macro の `beep` はエラー（旧実装は受け付けたが値にできなかった）
- エラーは標準エラー出力に `エラー: …`（`Interface::Cli::Main`）
- rename は compile 結果（16bit 値）を前後で比べて検証し、名前参照はテキスト置換で入れ子の中も書き換える
- cleanup はカレントディレクトリではなく `Environment#root` の下を消す
- `data/keycodes.yaml` の shifted に QMK の長い名前（`KC_LEFT_PAREN` など）を追加（旧コードはマクロ text 展開で書き出していた）

## 落とし穴

- validate と compile が別の経路でキーコードを解決すると、検証が通っても値が化ける（旧実装でコンボ・エンコーダに実例）。
  いまはどちらも `ConfigRepository#load`（`KeycodeNotation#parse` を 1 回だけ）を通るので、新しい項目もこの経路に載せる
- 依存の向きは `spec/architecture_spec.rb` が検査する。Domain / Image / Mapping / Planning に I/O を入れない
