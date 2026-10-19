# VS Code 拡張の作業の知見

設計は docs/vscode-extension/（spec / adr / roadmap / protocol / tasks）。作業は統合ブランチ `feature/vscode-extension` に PR で集める。

## QMK 設定の既定値は RMK の値
- Cornix の実機は RMK 0.8 系。`data/qmk_settings.yaml` の `default` は vial-qmk や QMK ではなく RMK v0.8.3 の
  `rmk/src/config/mod.rs`（Default）と `rmk/src/host/via/vial.rs`（QSID との対応）から取った
  （tapping_term 250、oneshot_timeout 1000、tap_code_delay 20 など）。実機から decompile した
  `spec/fixtures/authors_decompiled_config/settings/qmk_settings.yaml` とも一致する
- 説明文も RMK の振る舞いに合わせた（flow_tap はファームウェアで flow tap が有効なときだけ、permissive_hold と hold_on_other_key_press が両方 true なら後者が優先）

## YAML の値だけの書き換え（Storage::YamlDocument）
- 「同じ値」は表記の文字だけでなく読んだときの型も比べる（`"-"` → `-` は書き換えないが、`"true"` → `true` は書き換える）
- 同じファイルのまだない同じ見出しの下に 2 つ足すときは、1 つずつ当てて読み直し、`TextEdit.diff` で元のテキストに対する書き換えにする（1 つの文書から作った edits を並べると見出しが 2 回できる）
- `Problem.path_of` は shortcuts.yaml の名前に `.` `[` `]` を含むと違う道筋を返す（schema/ が location を文字列で作るため）

## CI と必須チェック
- main の ruleset は `rspec` を必須チェックにしている。ワークフローを `paths-ignore` で丸ごと飛ばすとチェックが待ちのままになり PR がマージできないので、
  rspec.yml はいつも動かし、ジョブの中で変わったパスを見て手順を飛ばす形にした
- 拡張の CI（vscode.yml、ジョブ名 `node`）は必須チェックになっていない（ruleset の変更はユーザーの判断）
