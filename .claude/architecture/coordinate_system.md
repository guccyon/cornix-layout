# 座標系（論理位置と layout.vil の物理位置）

Cornix の配列の知識はすべて `Domain::PositionMap`（`lib/cornix/domain/position_map.rb`）に置く。
他のクラスは行・列の計算をしない（ProfileMapper も `PositionMap#matrix` / `#position_at` / `#encoder_push_matrix` だけを使う）。

## 論理位置: `Domain::KeyPosition(hand:, row:, col:)`

- `hand` は `:left` / `:right`、`row` は 0〜3、`col` は 0〜5
- row0〜row2 は col 0〜5 の 6 キー、row3 は col 0〜2 の 3 キー
- 親指キー（position_map.yaml の `thumb_keys`）は **row 3 の col 3〜5**（`KeyPosition#thumb?`）
- 列は左右とも**物理的に左から右**の順（position_map.yaml の並び順と同じ）

```yaml
left_hand:
  row0: [tab, Q, W, E, R, T]          # (left, 0, 0..5)
  row3: [lctrl, command, option]      # (left, 3, 0..2)
  thumb_keys: [left, middle, right]   # (left, 3, 3..5)
right_hand:
  row0: [Y, U, I, O, P, backspace]    # (right, 0, 0..5)
  row3: [left, down, right]           # (right, 3, 0..2)
  thumb_keys: [left, middle, right]   # (right, 3, 3..5)
```

シンボルは「手 + グループ（row0〜row3, thumb_keys）」の中で一意。グループが違えば同じ名前でよい
（既定でも右手の row3 と thumb_keys に `left` / `right` がある）。レイヤーファイルのパスは `left_hand.thumb_keys.left` の形。

## 物理位置: layout.vil の `layout[layer][row][col]`（8 行 × 7 列）

```
Row 0: 左 row0 (col 0-5)                          + -1
Row 1: 左 row1 (col 0-5)                          + -1
Row 2: 左 row2 (col 0-5)                          + 左エンコーダ push (col 6)
Row 3: 左 row3 (col 0-2) + 左親指 (col 3-5)       + -1
Row 4: 右 row0 (逆順: col 5-0)                    + -1
Row 5: 右 row1 (逆順)                             + 右エンコーダ push (col 6)
Row 6: 右 row2 (逆順)                             + -1
Row 7: 右 row3 (逆順: col 2-0) + 右親指 (逆順: col 5-3) + -1
```

## 変換規則（`PositionMap#matrix(position)` → `[row, col]`）

| 位置 | 物理 row | 物理 col |
|---|---|---|
| 左手（親指を含む） | row | col（そのまま。親指は 3〜5） |
| 右手 row0〜row2 | row + 4 | 5 - col |
| 右手 row3 | 7 | 2 - col |
| 右手 親指（col 3〜5） | 7 | 5 - (col - 3) |
| エンコーダ push | 左 (2, 6)・右 (5, 6)（`ENCODER_PUSH`） | |

例: 右手 row0 の `Y`（col 0）→ `[4, 5]`、`backspace`（col 5）→ `[4, 0]`、右手親指 `left`（col 3）→ `[7, 5]`。

- `PositionMap#position_at(row, col)` は逆変換。キーのない位置（col 6 の -1、プッシュ）は nil
- エンコーダの回転（ccw / cw）はマトリクスではなく layout.vil の `encoder_layout[layer][左, 右]` に入る
  （`Image::EncoderRecord`）。プッシュだけがマトリクス上のキー
- layout.vil の `-1` は `Image::DeviceImage` では nil。ProfileMapper は割り当てのない位置も nil にする

## テスト

- `spec/domain/position_map_spec.rb`: 全位置の物理座標（layout.vil の物理配列）と逆変換
- `spec/mapping/profile_mapper/*`: レイヤー・エンコーダの配置、旧 compile 結果との一致
