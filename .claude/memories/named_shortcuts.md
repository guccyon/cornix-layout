# 名前付きショートカット（Shortcut('名前')）の設計判断

- nape_pro-layout の `Shortcut('名前')` を移植した。仕様の詳細は [docs/notation.md](../../docs/notation.md)
- nape は `Assignment(keycode, label, shortcut)` で「どの位置が Shortcut で書かれたか」を持つが、cornix はキーコードを包まず
  注記も別の `notes` に持つ（[key_notes](key_notes.md)）ので、Shortcut で書かれたかどうかは持たない。compile 結果には関係しない。
  その代わり書き出し（`Formatter`）は「値が定義のちょうど 1 つと一致するか」だけで `Shortcut('名前')` にする
- そのため、同じ値を `Shortcut` を使わずに直接書いた位置も、保存し直すと `Shortcut('名前')` になる（nape の pull と同じ規則）
- shortcuts.yaml の値の書き方（`Command + Shift + [` など）は、保存し直しても同じキーコードなら残す
  （正規形 `Shift + Command + [` に書き換えると利用者の書き方が消えるため）
- `Profile#references` は `shortcuts:` も返す。shortcuts.yaml を書くときは `shortcuts: {}` にした References を使う
  （そうしないと定義の値が自分自身の `Shortcut('名前')` で書かれてしまう）
- 同梱のショートカット（`data/shortcuts/`、cornixhub の一覧）は `Profile#shortcuts` に入れず、References の `preset_shortcuts` として
  読むときだけ使う。書き出し（Formatter）にも使うと、利用者が直接書いた `Command + B` まで `Shortcut('Xcode:一般:ビルド')` に化けるため
- 名前は `アプリ:カテゴリ:ラベル`。データファイルは入れ子にして `:` でつなぐ（参照は文字列 1 つなので入れ子にできる）。
  cornixhub のラベルに `:` はなく、カテゴリを省くと同じアプリ内でラベルが衝突する（Windows の「検索」など）
- #14 で「ショートカットの値にマクロ・タップダンスを書いてスロットを自動割り当てする」案を検討したが、利用者の判断で見送った。
  ショートカットは「1 シーケンスに名前を付けたもの」のままにし、複数の手順のもの（cornixhub のマクロ）は同梱データに `macro:` で入れて、
  macros/ のファイルの `preset:` で使う（番号は利用者が決める。スロットの数が利用者から見えなくなるのを避けるため）。
  プリセットの手順は名前参照を含まないので循環参照は起きない
