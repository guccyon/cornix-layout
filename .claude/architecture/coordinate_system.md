# 座標変換システム設計

## 概要

Cornixキーボードの論理座標と物理座標の変換システムを設計します。PositionMap を拡張し、全ての座標計算を集約します。

## 論理座標 vs 物理座標

### 論理座標（Logical Coordinates）

**定義**: ユーザーから見た自然な配置（position_map.yaml のシンボル順序）

**特徴**:
- 左手・右手で独立した座標系
- row0-3, thumb_keys で構造化
- 順序は position_map.yaml の定義順

**例**:
```yaml
left_hand:
  row0: [tab, Q, W, E, R, T]  # 論理col: 0-5
  row1: [caps, A, S, D, F, G]
  row2: [lshift, Z, X, C, V, B]
  row3: [lctrl, command, option]  # 論理col: 0-2
  thumb_keys: [left, middle, right]  # 論理idx: 0-2
```

論理座標の表現:
- `{ hand: :left, row: 0, col: 1 }` → 'Q'
- `{ hand: :left, row: 3, col: 0 }` → 'lctrl'
- `{ hand: :left, thumb_idx: 0 }` → 'left'

### 物理座標（Physical Coordinates）

**定義**: layout.vil (QMK) での配列インデックス

**特徴**:
- 8行×7列の2次元配列
- 左手: row 0-3, 右手: row 4-7
- ハードウェア固有の配置（右手は逆順）

**マッピング**:
```
物理配列 layout[8][7]:
  Row 0: 左手 row0 (Cols 0-5) + -1
  Row 1: 左手 row1 (Cols 0-5) + -1
  Row 2: 左手 row2 (Cols 0-5) + エンコーダーL push (Col 6)
  Row 3: 左手 row3 (Cols 0-2) + 左手 thumb_keys (Cols 3-5) + -1
  Row 4: 右手 row0 (Cols 5-0, 逆順) + -1
  Row 5: 右手 row1 (Cols 5-0, 逆順) + エンコーダーR push (Col 6)
  Row 6: 右手 row2 (Cols 5-0, 逆順) + -1
  Row 7: 右手 row3 (Cols 2-0, 逆順) + 右手 thumb_keys (Cols 5-3, 逆順) + -1
```

---

## PositionMap 拡張設計

### 現在のPositionMap

```ruby
# lib/cornix/position_map.rb (既存)
class PositionMap
  def initialize(yaml_path)
    @data = YAML.load_file(yaml_path)
  end

  def left_hand
    @data['left_hand']
  end

  def right_hand
    @data['right_hand']
  end

  def encoders
    @data['encoders']
  end

  # ... シンボル取得メソッド
end
```

### 拡張メソッド（新規追加）

```ruby
# lib/cornix/position_map.rb (拡張: +35行)
class PositionMap
  # === 既存メソッド ===
  # (変更なし)

  # === 新規メソッド ===

  # 論理行 → 物理行
  # @param hand [Symbol] :left または :right
  # @param logical_row [Integer] 0-3
  # @return [Integer] 物理行 (0-7)
  def physical_row(hand, logical_row)
    raise ArgumentError, "Invalid hand: #{hand}" unless [:left, :right].include?(hand)
    raise ArgumentError, "Invalid logical_row: #{logical_row}" unless (0..3).include?(logical_row)

    hand == :right ? logical_row + 4 : logical_row
  end

  # 論理列 → 物理列（右手の逆順処理を内包）
  # @param hand [Symbol] :left または :right
  # @param logical_row [Integer] 0-3
  # @param logical_col [Integer] 0-5 (row0-2), 0-2 (row3)
  # @return [Integer] 物理列 (0-5 または 0-2)
  def physical_col(hand, logical_row, logical_col)
    raise ArgumentError, "Invalid hand: #{hand}" unless [:left, :right].include?(hand)
    raise ArgumentError, "Invalid logical_row: #{logical_row}" unless (0..3).include?(logical_row)

    # 左手: そのまま
    return logical_col if hand == :left

    # 右手: 逆順処理
    max_col = (logical_row == 3) ? 2 : 5  # row3は3要素（0-2）、それ以外は6要素（0-5）
    (max_col) - logical_col
  end

  # 親指キーの物理行
  # @param hand [Symbol] :left または :right
  # @return [Integer] 物理行
  THUMB_PHYSICAL_ROW = { left: 3, right: 7 }.freeze
  def thumb_physical_row(hand)
    raise ArgumentError, "Invalid hand: #{hand}" unless THUMB_PHYSICAL_ROW.key?(hand)
    THUMB_PHYSICAL_ROW[hand]
  end

  # 親指キーの物理列
  # @param hand [Symbol] :left または :right
  # @param thumb_idx [Integer] 0-2 (論理インデックス)
  # @return [Integer] 物理列
  def thumb_physical_col(hand, thumb_idx)
    raise ArgumentError, "Invalid hand: #{hand}" unless [:left, :right].include?(hand)
    raise ArgumentError, "Invalid thumb_idx: #{thumb_idx}" unless (0..2).include?(thumb_idx)

    hand == :left ? 3 + thumb_idx : 5 - thumb_idx
  end

  # エンコーダープッシュの物理位置
  # @param side [Symbol] :left または :right
  # @return [Hash] { row: Integer, col: Integer }
  ENCODER_PUSH_POSITION = {
    left:  { row: 2, col: 6 },
    right: { row: 5, col: 6 }
  }.freeze
  def encoder_push_position(side)
    raise ArgumentError, "Invalid side: #{side}" unless ENCODER_PUSH_POSITION.key?(side)
    ENCODER_PUSH_POSITION[side]
  end
end
```

---

## 座標変換ルール詳細

### Rule 1: 左手の標準グリッドキー（row0-3）

**論理座標**:
- row: 0-3
- col: 0-5 (row0-2), 0-2 (row3)

**物理座標**:
- phys_row = logical_row（そのまま）
- phys_col = logical_col（そのまま）

**例**:
```ruby
# 左手 row0, col 1 ('Q')
position_map.physical_row(:left, 0)        # → 0
position_map.physical_col(:left, 0, 1)     # → 1
# 物理位置: layout[0][1]

# 左手 row3, col 0 ('lctrl')
position_map.physical_row(:left, 3)        # → 3
position_map.physical_col(:left, 3, 0)     # → 0
# 物理位置: layout[3][0]
```

### Rule 2: 右手の標準グリッドキー（row0-3）【逆順】

**論理座標**:
- row: 0-3
- col: 0-5 (row0-2), 0-2 (row3)

**物理座標**:
- phys_row = logical_row + 4
- phys_col = max_col - logical_col（逆順）
  - row0-2: max_col = 5
  - row3: max_col = 2

**例**:
```ruby
# 右手 row0, col 0 ('Y')
position_map.physical_row(:right, 0)       # → 4
position_map.physical_col(:right, 0, 0)    # → 5 (5 - 0)
# 物理位置: layout[4][5]

# 右手 row0, col 5 ('backspace')
position_map.physical_row(:right, 0)       # → 4
position_map.physical_col(:right, 0, 5)    # → 0 (5 - 5)
# 物理位置: layout[4][0]

# 右手 row3, col 0 ('left')
position_map.physical_row(:right, 3)       # → 7
position_map.physical_col(:right, 3, 0)    # → 2 (2 - 0)
# 物理位置: layout[7][2]
```

### Rule 3: 親指キー（left/right）

**論理座標**:
- thumb_idx: 0-2 (left, middle, right)

**物理座標**:
- 左手:
  - phys_row = 3（固定）
  - phys_col = 3 + thumb_idx（順序通り: 3, 4, 5）
- 右手:
  - phys_row = 7（固定）
  - phys_col = 5 - thumb_idx（逆順: 5, 4, 3）

**例**:
```ruby
# 左手 thumb_keys[0] ('left')
position_map.thumb_physical_row(:left)     # → 3
position_map.thumb_physical_col(:left, 0)  # → 3
# 物理位置: layout[3][3]

# 左手 thumb_keys[2] ('right')
position_map.thumb_physical_row(:left)     # → 3
position_map.thumb_physical_col(:left, 2)  # → 5
# 物理位置: layout[3][5]

# 右手 thumb_keys[0] ('left')
position_map.thumb_physical_row(:right)    # → 7
position_map.thumb_physical_col(:right, 0) # → 5
# 物理位置: layout[7][5]

# 右手 thumb_keys[2] ('right')
position_map.thumb_physical_row(:right)    # → 7
position_map.thumb_physical_col(:right, 2) # → 3
# 物理位置: layout[7][3]
```

### Rule 4: エンコーダープッシュボタン

**論理座標**: なし（特殊位置）

**物理座標**:
- 左: layout[2][6]（固定）
- 右: layout[5][6]（固定）

**例**:
```ruby
# 左エンコーダー push
position_map.encoder_push_position(:left)  # → { row: 2, col: 6 }
# 物理位置: layout[2][6]

# 右エンコーダー push
position_map.encoder_push_position(:right) # → { row: 5, col: 6 }
# 物理位置: layout[5][6]
```

---

## ハードウェア固有の制約

### 制約1: 右手の逆順配置

**理由**: Cornixキーボードのハードウェア特性（右手側は物理的に右から左にインデックスが振られている）

**影響**:
- row0-2（6要素）: `5 - col_idx`
- row3（3要素）: `2 - col_idx`
- thumb_keys: `5 - thumb_idx`

**注意**: この制約は PositionMap に隠蔽され、Layerモデルは意識しない

### 制約2: エンコーダープッシュの特殊位置

**理由**: エンコーダープッシュは標準グリッドキーとは別の物理位置に配置

**影響**:
- 左: Row 2, Col 6（row2 の右端）
- 右: Row 5, Col 6（row1 の右端、物理row的には）

**注意**: `encoder_push_position()` メソッドで取得

### 制約3: 親指キーの配置

**理由**: 親指キーは論理的には left_hand/right_hand 内だが、物理的には Row 3/7 の Cols 3-5

**影響**:
- 左手: Row 3, Cols 3-5（標準グリッドキーの右側）
- 右手: Row 7, Cols 3-5（逆順）

**注意**: `thumb_physical_row()`, `thumb_physical_col()` メソッドで取得

---

## 変換例とテストケース

### ケース1: 左手標準キー

```ruby
# 論理: 左手 row1, col 2 ('S')
hand = :left
logical_row = 1
logical_col = 2

phys_row = position_map.physical_row(hand, logical_row)  # → 1
phys_col = position_map.physical_col(hand, logical_row, logical_col)  # → 2

# 物理位置: layout[1][2]
# 期待値: 'KC_S'
```

### ケース2: 右手標準キー（逆順）

```ruby
# 論理: 右手 row0, col 1 ('U')
hand = :right
logical_row = 0
logical_col = 1

phys_row = position_map.physical_row(hand, logical_row)  # → 4
phys_col = position_map.physical_col(hand, logical_row, logical_col)  # → 4 (5 - 1)

# 物理位置: layout[4][4]
# 期待値: 'KC_U'
```

### ケース3: 右手 row3（3要素、逆順）

```ruby
# 論理: 右手 row3, col 1 ('down')
hand = :right
logical_row = 3
logical_col = 1

phys_row = position_map.physical_row(hand, logical_row)  # → 7
phys_col = position_map.physical_col(hand, logical_row, logical_col)  # → 1 (2 - 1)

# 物理位置: layout[7][1]
# 期待値: 'KC_DOWN'
```

### ケース4: 左手親指キー

```ruby
# 論理: 左手 thumb_keys[1] ('middle')
hand = :left
thumb_idx = 1

phys_row = position_map.thumb_physical_row(hand)  # → 3
phys_col = position_map.thumb_physical_col(hand, thumb_idx)  # → 4 (3 + 1)

# 物理位置: layout[3][4]
# 期待値: 'KC_SPACE'
```

### ケース5: 右手親指キー（逆順）

```ruby
# 論理: 右手 thumb_keys[0] ('left')
hand = :right
thumb_idx = 0

phys_row = position_map.thumb_physical_row(hand)  # → 7
phys_col = position_map.thumb_physical_col(hand, thumb_idx)  # → 5 (5 - 0)

# 物理位置: layout[7][5]
# 期待値: 'KC_BSPC'
```

### ケース6: エンコーダープッシュ

```ruby
# 左エンコーダー push
pos = position_map.encoder_push_position(:left)  # → { row: 2, col: 6 }
phys_row = pos[:row]  # → 2
phys_col = pos[:col]  # → 6

# 物理位置: layout[2][6]
# 期待値: 'KC_MUTE'

# 右エンコーダー push
pos = position_map.encoder_push_position(:right)  # → { row: 5, col: 6 }
phys_row = pos[:row]  # → 5
phys_col = pos[:col]  # → 6

# 物理位置: layout[5][6]
# 期待値: 'KC_MPLY'
```

---

## テスト設計

### ユニットテスト（position_map_spec.rb に追加）

```ruby
# spec/position_map_spec.rb (+75行)

describe '#physical_row' do
  it '左手の論理行を物理行に変換' do
    expect(position_map.physical_row(:left, 0)).to eq(0)
    expect(position_map.physical_row(:left, 3)).to eq(3)
  end

  it '右手の論理行を物理行に変換（+4）' do
    expect(position_map.physical_row(:right, 0)).to eq(4)
    expect(position_map.physical_row(:right, 3)).to eq(7)
  end

  it '無効な引数でエラー' do
    expect { position_map.physical_row(:invalid, 0) }.to raise_error(ArgumentError)
    expect { position_map.physical_row(:left, 4) }.to raise_error(ArgumentError)
  end
end

describe '#physical_col' do
  it '左手の論理列を物理列に変換（そのまま）' do
    expect(position_map.physical_col(:left, 0, 1)).to eq(1)
    expect(position_map.physical_col(:left, 3, 2)).to eq(2)
  end

  it '右手 row0-2 の論理列を物理列に変換（逆順、max=5）' do
    expect(position_map.physical_col(:right, 0, 0)).to eq(5)  # 5 - 0
    expect(position_map.physical_col(:right, 0, 5)).to eq(0)  # 5 - 5
    expect(position_map.physical_col(:right, 1, 2)).to eq(3)  # 5 - 2
  end

  it '右手 row3 の論理列を物理列に変換（逆順、max=2）' do
    expect(position_map.physical_col(:right, 3, 0)).to eq(2)  # 2 - 0
    expect(position_map.physical_col(:right, 3, 2)).to eq(0)  # 2 - 2
  end
end

describe '#thumb_physical_row' do
  it '親指キーの物理行を返す' do
    expect(position_map.thumb_physical_row(:left)).to eq(3)
    expect(position_map.thumb_physical_row(:right)).to eq(7)
  end
end

describe '#thumb_physical_col' do
  it '左手親指キーの物理列を返す（順序通り）' do
    expect(position_map.thumb_physical_col(:left, 0)).to eq(3)  # 3 + 0
    expect(position_map.thumb_physical_col(:left, 1)).to eq(4)  # 3 + 1
    expect(position_map.thumb_physical_col(:left, 2)).to eq(5)  # 3 + 2
  end

  it '右手親指キーの物理列を返す（逆順）' do
    expect(position_map.thumb_physical_col(:right, 0)).to eq(5)  # 5 - 0
    expect(position_map.thumb_physical_col(:right, 1)).to eq(4)  # 5 - 1
    expect(position_map.thumb_physical_col(:right, 2)).to eq(3)  # 5 - 2
  end
end

describe '#encoder_push_position' do
  it 'エンコーダープッシュの物理位置を返す' do
    expect(position_map.encoder_push_position(:left)).to eq({ row: 2, col: 6 })
    expect(position_map.encoder_push_position(:right)).to eq({ row: 5, col: 6 })
  end
end
```

### 統合テスト（Layer → QMK → Layer）

```ruby
# spec/models/layer_spec.rb (統合テスト)

describe 'round-trip with physical coordinates' do
  it 'LayerのQMK変換がPositionMapを正しく使用' do
    # 1. 論理モデル作成
    layer = Layer.new(
      name: 'Test Layer',
      description: '',
      index: 0,
      left_hand: LeftHandMapping.new(
        row0: [
          KeyMapping.new(symbol: 'Q', keycode: 'Q', logical_coord: { hand: :left, row: 0, col: 1 })
        ],
        # ...
      ),
      # ...
    )

    # 2. QMK変換
    qmk_hash = layer.to_qmk(position_map: position_map, keycode_converter: keycode_converter)
    layout = qmk_hash['layout']

    # 3. 物理位置検証
    expect(layout[0][1]).to eq(keycode_converter.resolve('Q'))  # 左手 row0, col 1
    expect(layout[4][4]).to eq(keycode_converter.resolve('U'))  # 右手 row0, col 1 → phys [4][4]
    expect(layout[3][4]).to eq(keycode_converter.resolve('Space'))  # 左手 thumb_keys[1] → phys [3][4]

    # 4. 逆変換
    layer2 = Layer.from_qmk(0, layout, encoder_data, position_map, keycode_converter)

    # 5. 論理座標が復元されることを確認
    expect(layer2.left_hand.row0[0].logical_coord).to eq({ hand: :left, row: 0, col: 1 })
  end
end
```

---

## 既存コードからの移行

### Before（既存の compiler.rb）

```ruby
# 16箇所に散在する座標計算
layout[row_idx][col_idx] = keycode  # 左手
layout[row_idx + 4][5 - col_idx] = keycode  # 右手 row0-2
layout[row_idx + 4][2 - col_idx] = keycode  # 右手 row3
layout[3][3 + thumb_idx] = keycode  # 左手親指
layout[7][5 - thumb_idx] = keycode  # 右手親指
layout[2][6] = keycode  # 左エンコーダーpush
layout[5][6] = keycode  # 右エンコーダーpush
```

### After（新実装の Layer モデル）

```ruby
# PositionMapに集約された座標計算
phys_row = position_map.physical_row(hand, logical_row)
phys_col = position_map.physical_col(hand, logical_row, logical_col)
layout[phys_row][phys_col] = keycode

# 親指キー
phys_row = position_map.thumb_physical_row(hand)
phys_col = position_map.thumb_physical_col(hand, thumb_idx)
layout[phys_row][phys_col] = keycode

# エンコーダーpush
pos = position_map.encoder_push_position(side)
layout[pos[:row]][pos[:col]] = keycode
```

**削減される行数**: 28箇所の座標計算 → 0箇所（PositionMapに隠蔽）

---

## 次のステップ

- [migration_guide.md](migration_guide.md): 実装ガイド（Task 1: PositionMap拡張の詳細手順）
