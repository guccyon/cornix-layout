# 同梱のアイコンの出どころとライセンス

編集画面で、同梱のショートカット（`data/shortcuts/`）のアプリと、それを元にした `preset:` のマクロを割り当てたキーに出すアイコン。
どのアプリにどのアイコンを使うかは `data/shortcut_icons.yaml`（ID だけ）、画像とライセンス表記はここに置く（ADR 011）。
取り出し方は `extract.mjs` の先頭のコメント（表にある ID の分だけを npm のパッケージから写し、`src/webview/icons/manifest.ts` を作り直す）。

| ディレクトリ | 素材 | 版 | ライセンス |
|---|---|---|---|
| `simple-icons/` | [Simple Icons](https://simpleicons.org/)（npm `simple-icons`） | 16.35.0 | CC0 1.0（`simple-icons/LICENSE.md`）。ロゴそのものは各社の商標（`simple-icons/DISCLAIMER.md`） |
| `material-icon-theme/` | [Material Icon Theme](https://github.com/material-extensions/vscode-material-icon-theme)（npm `material-icon-theme`） | 5.39.0 | MIT（`material-icon-theme/LICENSE`） |

- SVG は手を加えずに写している。Simple Icons は単色なので、画面では CSS の mask で塗る（色は Simple Icons のデータのブランドの色。黒や白に近い色はテーマの前景色にする）
- `badge:<文字>` のアプリ（CleanShot X、CLIP STUDIO PAINT、Excel、Fusion 360、Illustrator、Photoshop、Premiere Pro、Slack、Windows）は画像を持たず、
  頭文字を色付きの四角に載せたものを CSS で描く（色は `src/webview/icons/badges.ts`。各社のロゴは写していない）
