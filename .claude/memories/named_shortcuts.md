# 名前付きショートカット（Shortcut('名前')）の設計判断

- nape_pro-layout の `Shortcut('名前')` を移植した。仕様の詳細は [features/reference_system.md](../features/reference_system.md)
- nape は `Assignment(keycode, label, shortcut)` で「どの位置が Shortcut で書かれたか」を持つが、cornix の Layer は
  位置 → Keycode だけなので持たない。Layer に注記の層を足すと影響が大きく、compile 結果には関係しないため見送った。
  その代わり書き出し（`Formatter`）は「値が定義のちょうど 1 つと一致するか」だけで `Shortcut('名前')` にする
- そのため、同じ値を `Shortcut` を使わずに直接書いた位置も、保存し直すと `Shortcut('名前')` になる（nape の pull と同じ規則）
- shortcuts.yaml の値の書き方（`Command + Shift + [` など）は、保存し直しても同じキーコードなら残す
  （正規形 `Shift + Command + [` に書き換えると利用者の書き方が消えるため）
- `Profile#references` は `shortcuts:` も返す。shortcuts.yaml を書くときは `shortcuts: {}` にした References を使う
  （そうしないと定義の値が自分自身の `Shortcut('名前')` で書かれてしまう）
