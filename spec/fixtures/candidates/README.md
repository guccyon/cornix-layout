# 「この入力ならこの候補」のデータ

`keycode/candidates`（[protocol.md](../../../docs/vscode-extension/protocol.md) の 5.3）の候補の並びを確かめるデータ（[ADR 004](../../../docs/vscode-extension/adr.md)）。
Ruby は `spec/mapping/candidate_catalog_spec.rb` が読む。将来の TypeScript 版も同じデータと同じ判定で確かめるので、ここに読み方の約束を書く。

## 形

各ファイル（`*.yaml`）は項目の並び。項目は次のキーを持つ（YAML のアンカー `&` / `*` で `references` を使い回してよい）。

| キー | 省略 | 意味 |
|---|---|---|
| `context` | 不可 | `layerKey` / `encoder` |
| `query` | 不可 | 入力中の文字（文字列。`0x7E40` のような値は YAML で整数になるので引用符で囲む） |
| `expect` | 不可 | 候補の `insertText` の並び |
| `absent` | 可 | 結果に出てはいけない `insertText` の並び |
| `warning` | 可 | `insertText` → 理由。その候補があり、`warning` が理由の文字と同じ |
| `category` | 可 | `insertText` → 分類。その `insertText` の候補が 1 件以上あり、どれもその分類 |
| `references` | 可 | プロファイルの名前の一覧（下） |
| `limit` | 可 | 既定は 50 |

## 判定

- `expect`: 結果の先頭から `expect` の件数だけ取り出したものが `expect` と順序ごと一致する。`expect: []` なら結果は 0 件
- `absent` / `warning` / `category` は結果の全体（`limit` で切ったあと）で確かめる
- 結果の `truncated` は確かめない

## references

`profile/open` の結果の `references` と同じ形。

```yaml
references:
  layers: [{ index: 1, name: Symbols }]       # layer の候補（レイヤーごとの MO / TG / ...）と detail
  macros: [{ index: 0, name: Bracket Pair }]   # Macro('名前')
  tapDances: [{ index: 4, name: Tab Escape }]  # TapDance('名前')
  shortcuts: [{ name: 前のタブへ, text: 'Shift + Command + [' }]   # 利用者のショートカット（shortcuts.yaml）
```

- `shortcuts[].text` はキーコードの表記として読み（マクロなどの名前は使わない）、その値を定義にする
- `references` がない項目は「レイヤー・マクロ・タップダンス・利用者のショートカットがどれもない」プロファイル。
  どちらの場合も `Shortcut(...)` を使える場面として扱い、同梱のショートカット（`data/shortcuts/`）はいつも候補に入る
