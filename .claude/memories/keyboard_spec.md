# KeyboardSpec（#137〜#141）の作業の知見

2026-10-31。拡張のキーボード固有の情報を `editors/vscode/src/keyboard/` にまとめた。中身の説明は `docs/vscode-extension/keyboard-spec.md`、決定は ADR 026。

## 決めたこと（Issue の案から変えたところ）

- `Slot.hand` は消さずに残し、`section` / `sectionLabel` を足した。サーバーとのやりとり（`renamePosition`）と値の照合（`keyAt`・`baseLayerValue`・実機の違いの照合）は約束の hand で行うため。画面の並びと見出しは section だけで決める
- 図にないキー（spec に配置のない位置）の区画は、同じ手のほかのキーの区画、それもなければ手の名前（`model.ts` の `sectionOf`）。編集フォームには出る
- 図の高さは範囲だけだと 4.717448（回した親指の角）なので、Cornix の spec に `padding.bottom` を持たせて今までの 4.75 に合わせた（1px も変えないため）。旧式の出力は `test/unit/legacyCornixLayout.ts` に期待値として残した
- Webview は `keyboard` のメッセージを受けてから画面を組み立てる（`main.ts` の `buildScreen`）。テストは `new App(root, { keyboard: CORNIX, host })` のように spec を渡す
- 反映のプレビューのモーダル（`TransferDialog`）にも spec をまるごと渡す（表示名・図の配置・区画）

## 進め方で分かったこと

- このリポジトリは merge commit を許していない（squash と rebase だけ）。統合ブランチに子 PR を積むとき、前の子を squash でマージしたら、次の子は `git rebase --onto origin/<統合ブランチ> <前の子の先端>` で載せ替えてから push する
- サブエージェントの worktree（`isolation: worktree`）は `.claude/worktrees/` にでき、`git add -A` で埋め込みのリポジトリとしてコミットに入ってしまう。コミットの前に `git worktree remove` で消すか、パスを指定して add する
- サブエージェントの worktree は main の先端から作られることがある。始めるコミットを brief に書いておくと、そこから作り直してくれる
- K2 の画面の比較は、変更前後の `.keyboard` を Playwright でライト / ダークで撮って `cmp` でバイト単位まで一致を見た（手順は vscode_extension_v04.md）
