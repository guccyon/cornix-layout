# 割り当ての注記（note）

nape_pro-layout の `{ key: <表記>, note: <注記> }` に合わせて追加した（2026-10-18）。

- 書ける場所: レイヤーのキー・エンコーダの操作、タップダンスの動作、コンボの `output_key`。
  コンボの `trigger_keys` とマクロの `keys` は対象外（割り当てではなくキーの並び）
- Domain はキーコードをそのまま持ち、注記は別の `notes` Hash（場所 => String）で持つ
  （`Layer#notes`（KeyPosition）、`EncoderBinding#notes` / `TapDance#notes`（操作名）、`Combo#notes`（`:output_key`））。
  nape の `Assignment(keycode, label)` のようにキーコードを包まなかったのは、`ProfileMapper#to_image`・diagnostics・
  Shortcut 対応（KeycodeNotation が Keycode を返す）をそのままにするため。compile の結果は注記で変わらない
- 読み書きは `Storage::Schema::KeycodeField#read_assignment` / `#write_assignment`。空の note は注記なし
- `ProfileMapper::Inheritance#notes` / `#encoder_notes`: previous の同じ場所でキーコードが同じときだけ注記を引き継ぐ（nape の pull と同じ）。
  decompile は空の config/ にしか書かないので previous を渡さず、注記は書かない
- rename（`ConfigEditor#replace_references`）はテキスト置換なので、注記の文中にある `Macro('旧名')` も新しい名前に書き換わる（意図どおり）
- `DiagnosticLocator` は値が注記付きの形なら位置に `.key` を付ける（構造検証の位置と揃える）
