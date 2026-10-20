# VS Code 拡張の作業の知見

設計は docs/vscode-extension/（spec / adr / roadmap / protocol / tasks）。v0.1 は統合ブランチ `feature/vscode-extension` に作業ごとの PR を集めて main に入れた。v0.2 からも版ごとに同じ統合ブランチに PR を集め、版ができたら main への PR にする（docs/vscode-extension/tasks.md の「v0.2 からの進め方」）。

## QMK 設定の既定値は RMK の値
- Cornix の実機は RMK 0.8 系。`data/qmk_settings.yaml` の `default` は vial-qmk や QMK ではなく RMK v0.8.3 の
  `rmk/src/config/mod.rs`（Default）と `rmk/src/host/via/vial.rs`（QSID との対応）から取った
  （tapping_term 250、oneshot_timeout 1000、tap_code_delay 20 など）。実機から decompile した
  `spec/fixtures/authors_decompiled_config/settings/qmk_settings.yaml` は作者が変えた値なので既定値の根拠にはならない
  （tapping_term・hold_on_other_key_press・chordal_hold が既定値と違う）
- 説明文も RMK の振る舞いに合わせた（flow_tap はファームウェアで flow tap が有効なときだけ、permissive_hold と hold_on_other_key_press が両方 true なら後者が優先）

## YAML の値だけの書き換え（Storage::YamlDocument）
- 「同じ値」は表記の文字だけでなく読んだときの型も比べる（`"-"` → `-` は書き換えないが、`"true"` → `true` は書き換える）
- 同じファイルのまだない同じ見出しの下に 2 つ足すときは、1 つずつ当てて読み直し、`TextEdit.diff` で元のテキストに対する書き換えにする（1 つの文書から作った edits を並べると見出しが 2 回できる）
- `Problem.path_of` は shortcuts.yaml の名前に `.` `[` `]` を含むと違う道筋を返す（schema/ が location を文字列で作るため）

## CI と必須チェック
- main の ruleset は `rspec` を必須チェックにしている。ワークフローを `paths-ignore` で丸ごと飛ばすとチェックが待ちのままになり PR がマージできないので、
  rspec.yml はいつも動かし、ジョブの中で変わったパスを見て手順を飛ばす形にした
- 拡張の CI（vscode.yml、ジョブ名 `node`）も 2026-10-20 に必須チェックに足した。rspec と同じく、いつも報告し関係のない PR では手順を飛ばして成功で終える
- vscode.yml の node ジョブは、本物のサーバーでの統合テスト（`npm run test:integration:ruby`）のために Ruby を入れる（gem は使わないので bundle install しない）。
  そのため lib/ と bin/cornix の変更でも動かす

## 通しの確認（J）で分かったこと
- VS Code（テストで起動したものも、Dock から起動したものも）はログインシェルから環境を読み直すので、mise の Ruby が PATH の後ろに回り、
  `bin/cornix` の `#!/usr/bin/env ruby` が macOS の `/usr/bin/ruby` 2.6 を選んで `Data.define` で落ちることがある。
  統合テストは runTest.ts が使う Ruby を決めたスクリプトを cornix.path にする。利用者向けには editors/vscode/README.md に同じ回避を書いた
  （`extensionTestsEnv` で PATH を渡しても VS Code が上書きするので効かない）
- `.vscodeignore` で `!media/**` のあとに `media/icons/extract.mjs` を書いても vsce は除外しない。入れるものを拡張子で書く
- 本物のサーバーでの通し: authors のプロファイルの写しでキー・エンコーダ・QMK 設定を 10 か所変えて保存し、変えていない行は変わらず、
  手で直した写しと compile の結果（.vil）がバイト単位で一致した。もとが引用符付きの値（`colon: "-"`）は新しい値も引用符付きで書く（`"Minus"`）
