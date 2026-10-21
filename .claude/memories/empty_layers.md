# 空のレイヤーのファイルの省略（issue #83）

- compile は定義のないレイヤーを「ファイルがあって何も書いていないレイヤー」と同じ値にする（position_map の位置とエンコーダは KC_NO、キーのない枠は -1）。
  `-1` のままだと `cornix device apply` が飛ばして古い割り当てが残るため
- decompile は `Layer#blank?`（キーとエンコーダがすべて KC_NO。KC_TRNS は空ではない）のレイヤーを書かない。
  ただしレイヤー 0 と `Profile#referenced_layer_indexes`（MO / TG / TO / OSL / LT / LM など。レイヤー・エンコーダ・マクロ・タップダンス・コンボのキーから）は書く。
  判定は ImageReader が Profile を作ったあとに行う（参照はどこからでもよいので、全体を読んでからでないと決まらない）。
  Raw として読まれたレイヤー操作（FN_MO13 など）は数えない。走査の対象は ProfileDiagnostics#keycode_entries とそろえる
- 検証の「レイヤー N がありません」はやめ、レイヤー 0 がないときだけ警告する
- 落とし穴: authors の `*_empty.yml` は spec/fixtures/authors_config ではエンコーダに割り当てがあり空ではない。
  authors-keymap の 8 と 9 は 4_ipad_base.yml のレイヤー操作（fn キーと OSL(9)）が指すので、空でも decompile が書く。消せるのは 5〜7
- `spec/interface/cli/top_level_commands_spec.rb:144`（snapshots の相対パス）は macOS の手元では main でも落ちる（/var と /private/var の違い）。この変更とは関係ない
- 実機での確認（2026-10-22）: 番号に抜けのあるプロファイルを apply・Vial で読み込んでも番号はずれず、あとから中身も入れられた。抜けは許し、警告しない（docs/device.md の「番号の抜けのあるプロファイル」）。
  試験用のプロファイルは今の状態を `init --from` で設定にし、消す番号への参照を NoKey などに替えて作った。レイヤー 4 は TD(0) の OSL(4) が指すので、空にすると戻れなくなるおそれがあり残した
- 読み出しで 1 度だけタップダンス 22 の値が化けた（読み直すと正しい）。BLE の応答の取り違えとみられる
