# 空のレイヤーのファイルの省略（issue #83）

- compile は定義のないレイヤーを「ファイルがあって何も書いていないレイヤー」と同じ値にする（position_map の位置とエンコーダは KC_NO、キーのない枠は -1）。
  `-1` のままだと `cornix device apply` が飛ばして古い割り当てが残るため
- decompile は `Layer#blank?`（キーとエンコーダがすべて KC_NO。KC_TRNS は空ではない）のレイヤーを書かない。
  ただしレイヤー 0 と `Profile#referenced_layer_indexes`（MO / TG / TO / OSL / LT / LM など。レイヤー・エンコーダ・マクロ・タップダンス・コンボのキーから）は書く。
  判定は ImageReader が Profile を作ったあとに行う（参照はどこからでもよいので、全体を読んでからでないと決まらない）
- 検証の「レイヤー N がありません」はやめ、レイヤー 0 がないときだけ警告する
- 落とし穴: authors の `*_empty.yml` は spec/fixtures/authors_config ではエンコーダに割り当てがあり空ではない。
  authors-keymap の 8 と 9 は 4_ipad_base.yml のレイヤー操作（fn キーと OSL(9)）が指すので、空でも decompile が書く。消せるのは 5〜7
- `spec/interface/cli/top_level_commands_spec.rb:144`（snapshots の相対パス）は macOS の手元では main でも落ちる（/var と /private/var の違い）。この変更とは関係ない
