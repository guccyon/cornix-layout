# プロジェクトの背景

## Cornix と Vial

- Cornix は分割キーボード。左右それぞれ 4 行（row0〜row2 が 6 キー、row3 が 3 キー）+ 親指 3 キー、
  ロータリーエンコーダが左右 1 個ずつ（プッシュ・左右回転）。
- ファームウェアは RMK 0.8 系で、Vial プロトコル 6 に対応する（詳細は [vial_device_protocol](../memories/vial_device_protocol.md)）。
- Vial はキーマップを GUI で編集し、`layout.vil`（JSON）として書き出す・読み込む。

## 解決したい問題

`layout.vil` は 16bit 値相当の名前が 8 行 × 7 列 × 10 レイヤー並ぶ JSON で、直接は編集しにくく、
コメントが書けず、差分のレビューや git での管理も難しい。

このツールは `layout.vil` ⇔ YAML（`config/`）の双方向変換を提供し、
レイヤー・マクロ・タップダンス・コンボを名前付きの個別ファイルで、エイリアスや修飾キー表現を使って書けるようにする。
さらに Vial を使わずに接続中のキーボードへ差分だけを書き込める（`cornix device` / `cornix mcp`）。

## 用語

| 用語 | 意味 |
|---|---|
| レイヤー | 最大 10 枚（0〜9）。`MO(n)` / `LT(n, kc)` などで切り替える |
| マクロ | キーの並び・文字列・待ちを 1 キーで実行（最大 32） |
| タップダンス | タップ / 長押し / ダブルタップ / タップ後長押しで動作を変える（最大 32） |
| コンボ | 複数キーの同時押しで別のキーを出す（最大 32、トリガー 4 キーまで） |
| QMK Settings | tapping_term などの設定。QSID で識別する |
| QSID | Vial の QMK Settings の ID（`data/qmk_settings.yaml`） |

## layout.vil の構造

```json
{
  "version": 1, "uid": 16882930253541522617, "vial_protocol": 6, "via_protocol": 9,
  "settings": { "2": 50, "7": 180, ... },
  "layout": [ [[...7 列...] × 8 行] × 10 レイヤー ],     // キーのない位置は -1
  "encoder_layout": [ [["KC_VOLD", "KC_VOLU"], [ccw, cw]] × 10 ],
  "macro": [ [["tap", "KC_LBRACKET", "KC_RBRACKET", "KC_LEFT"]], ... ],
  "tap_dance": [ ["OSL(4)", "MO(1)", "KC_NO", "KC_NO", 200], ... ],
  "combo": [ ["KC_K", "KC_L", "KC_NO", "KC_NO", "M0"], ... ],
  "layout_options": 0, "alt_repeat_key": [], "key_override": []
}
```

物理配列と論理位置の対応は [coordinate_system](../architecture/coordinate_system.md)。

## 方針

- 人が読めることを優先する（エイリアス、修飾キー表現、名前参照、コメント）
- 既存の設定を壊さない（decompile の上書き防止、rename のバックアップと compile 結果の比較、device の自動バックアップ）
- 往復で値を失わない（decompile → compile で 16bit 値が一致する。知らない値は `0xHHHH` や `DeviceImage#meta` で保つ）
