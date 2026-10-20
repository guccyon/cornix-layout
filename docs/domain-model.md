# ドメインモデル

対象: Cornix（RMK 0.8 系ファームウェア、Vial プロトコル 6）。
コードは `lib/cornix/domain/`（Domain 層）と `lib/cornix/image/`（Image 層）。どちらも I/O を持たず、何にも依存しない
（[architecture.md](architecture.md) の「レイヤーと依存の向き」）。用語は [background.md](background.md) を参照。

## 1. 全体像

```
Profile（集約ルート。設定ファイル一式 = layout.vil 1 つ）
 ├─ metadata: Metadata                  … config/metadata.yaml（keyboard, version, uid, ... と extra）
 ├─ settings: QmkSettings               … QSID => 値（Vial の QMK Settings）
 ├─ position_map: PositionMap           … キーの名前 ⇄ 論理位置 ⇄ layout.vil の物理位置（§5）
 ├─ layers: [Layer]                     … 最大 10 枚
 │    └─ Layer(index, name, description, keys, encoders, notes)
 │         ├─ keys: KeyPosition => Keycode       割り当てのある位置だけ
 │         ├─ encoders: { left:, right: } => EncoderBinding(push, ccw, cw, notes)
 │         └─ notes: KeyPosition => String       注記（§3.4）
 ├─ macros: [Macro]                     … 最大 32
 │    └─ Macro(index, name, description, steps: [MacroStep], preset)
 │         MacroStep = Tap(keys) | Down(keys) | Up(keys) | Delay(ms) | Text(content)
 ├─ tap_dances: [TapDance]              … 最大 32
 │    └─ TapDance(index, name, description, on_tap, on_hold, on_double_tap, on_tap_hold, tapping_term, notes)
 ├─ combos: [Combo]                     … 最大 32
 │    └─ Combo(index, name, description, trigger_keys: [Keycode], output_key, notes)
 └─ shortcuts: ShortcutLibrary          … 名前付きショートカット（名前 => Keycode。設定ファイルにだけある）
```

- `Profile` は「キーボードに書き込みたい状態」を表す。各要素は渡された順のまま持ち、番号は各要素の `index`。
  番号や名前の重複、件数の上限、参照先の存在は生成時ではなく `Profile#diagnostics` で検査する（§6）
- デバイス（と layout.vil）の値をそのまま持つ型は別にある（`Image::DeviceImage`、§7）。
  Profile ⇄ DeviceImage の変換は `Mapping::ProfileMapper` だけが行う（§8）
- 名前（マクロ名・タップダンス名・ショートカット名）は Profile の中だけの概念で、デバイスには番号か値しか書かない

## 2. 値オブジェクト

すべて `Data.define` で作り、不変（配列と Hash は freeze）で、値で等価判定する。
不正な値は生成時に `Cornix::InvalidValue` を送出する（構造検証。検査の部品は `Domain::Checks`）。

| 型 | 内容 | 制約 |
|---|---|---|
| `KeyPosition(hand, row, col)` | キーの論理位置（§5） | hand は `:left` / `:right`、row 0〜3、col 0〜5。row 3 の col 3〜5 が親指（`#thumb?`） |
| `LayerRef(index)` | レイヤー番号 | 0〜31（QMK のレイヤー操作で表せる範囲）。実在するレイヤー数は `Capabilities` で検査 |
| `ModifierSet(side, mods)` | 修飾キーの組 | side は `:left` / `:right` の一方だけ。mods は ctrl / shift / alt / gui の 1 つ以上で、正規の順に並べ直す。QMK の 5bit（bit0 ctrl, bit1 shift, bit2 alt, bit3 gui, bit4 右）と 1 対 1。左右の混在は表せない |
| `EncoderBinding(push, ccw, cw, notes)` | エンコーダ 1 つの割り当て | 3 操作とも `Keycode`（使わない操作は `NO_KEY`） |
| `QmkSettings(values)` | QSID => 値 | QSID 0〜0xFFFF、値 0〜0xFFFFFFFF。QSID の昇順に並べ直す。真偽値は 0 / 1。名前・幅は Mapping の `QmkSettingCatalog` が持つ |
| `Metadata` | config/metadata.yaml | `keyboard`（必須）、`version`（必須）、`uid`、`vendor_product_id`（`0xXXXX`）、`product_id`、`matrix`、`vial_protocol`、`via_protocol`。それ以外の項目は `extra` にそのまま持つ（`extra_keys` は layout.vil の `layout_options` / `alt_repeat_key` / `key_override`） |
| `ShortcutLibrary(entries)` | 名前 => Keycode | 名前は空でない文字列で、前後の空白を除いて一意。定義順を保つ |
| `Capabilities` | デバイスの上限 | `layers`, `macros`, `tap_dances`, `combos`, `combo_keys`, `unsupported_keycodes`。Cornix は `Capabilities::CORNIX`（10 / 32 / 32 / 32 / 4） |
| `Diagnostic(severity, path, message)` | 意味検証の結果 1 件（§6） | severity は `:error` / `:warning` |

## 3. Keycode

キーに割り当てる動作（16bit のキーコード 1 つ分）は、文字列ではなく型のある値オブジェクトの族で表す。
名前（`KC_A` や別名）は持たず、名前はカタログ（`Mapping::KeycodeCatalog`、`data/keycodes.yaml`）から引く。

```
Keycode（すべて Keycode::Value を include する）
 ├─ NoKey / Transparent          0x0000 / 0x0001（定数 NO_KEY / TRANSPARENT）
 ├─ Basic(code)                  0x0002〜0x00FF でカタログにある基本キー（文字・記号・F キー・修飾キー単体・メディア・マウス）
 ├─ Modified(mods, base: Basic)  0x0100〜0x1FFF  LSFT(KC_1), SGUI(KC_4), Cmd + Shift + 4
 ├─ ModTap(mods, base: Basic)    0x2000〜0x3FFF  LGUI_T(KC_LANG2)
 ├─ LayerTap(layer, base: Basic) 0x4000〜0x4FFF  LT1(KC_SPACE)。レイヤーは 0〜15
 ├─ LayerMod(layer, mods)        0x5000〜0x51FF  LM(1, MOD_LSFT)。レイヤーは 0〜15
 ├─ LayerAction(op, layer)       0x5200〜0x52FF  TO / MO / DF / TG / OSL / TT / PDF（op は to, momentary, default,
 │                                               toggle, one_shot, tap_toggle, persistent_default）
 ├─ OneShotMod(mods)             0x52A0〜0x52BF  OSM(MOD_LSFT)
 ├─ TapDanceCall(index)          0x5700〜0x57FF  TD(0)〜TD(255)
 ├─ MacroCall(index)             0x7700〜0x777F  M0〜M127（vial-qmk の QK_MACRO の範囲）
 ├─ Quantum(code)                カタログにある名前付きの特殊キー（QK_BOOT, USER00, KC_ASTG など）
 └─ Raw(code)                    上のどれにも当たらない値。落とさずに往復させるために保持する
```

- `Modified` / `ModTap` / `LayerTap` の `base` は `Basic` だけ（`Cmd + LT(1, Space)` は表せない）
- `MacroCall` / `TapDanceCall` は番号だけを持つ。名前（`Macro('名前')`）との対応は `Profile#references` が作る
- 書き込んではいけない値（QK_BOOT など）や、Cornix が対応していないとみられる値の判定は Domain の外にある
  （書き込みの拒否は `KeycodeCatalog#dangerous?` と `Device::ChangePolicy`。対応していないとみられる値の表は
  `KeycodeCatalog#unsupported_keycodes` が作り、`Application::Environment#capabilities` が `Capabilities` に入れて意味検証に渡す）

### 3.1 16bit 値の解読（`Mapping::KeycodeCodec`）

`decode` は例外を出さない。値が入る範囲で行が決まり、その行の条件（カタログにある・修飾ビットがあるなど）を満たさなければ
次の行へは進まずに `Raw` にする（`case` で範囲だけで分岐する）。範囲の決まった行に当たらない値だけが 10〜12 を順に見る。

| 順 | 範囲・値 | 解読結果 |
|---|---|---|
| 1 | `0x0000` / `0x0001` | `NoKey` / `Transparent` |
| 2 | `0x0002`〜`0x00FF` でカタログにある | `Basic` |
| 3 | `0x0100`〜`0x1FFF` で修飾ビットがあり、下位 8 ビットが `Basic` | `Modified` |
| 4 | `0x2000`〜`0x3FFF`（同上） | `ModTap` |
| 5 | `0x4000`〜`0x4FFF` で下位 8 ビットが `Basic` | `LayerTap` |
| 6 | `0x5000`〜`0x51FF` で修飾ビットがある | `LayerMod` |
| 7 | `0x52A0`〜`0x52BF` で修飾ビットがある | `OneShotMod` |
| 8 | `0x5700`〜`0x57FF` | `TapDanceCall` |
| 9 | `0x7700`〜`0x777F` | `MacroCall` |
| 10 | レイヤー操作の基準値（`0x5200` TO、`0x5220` MO、`0x5240` DF、`0x5260` TG、`0x5280` OSL、`0x52C0` TT、`0x52E0` PDF）+ 0〜31 | `LayerAction` |
| 11 | カタログにある特殊キー | `Quantum` |
| 12 | それ以外 | `Raw` |

`encode` はこの逆で、表せない値（カタログにない基本キー・特殊キー）は `UnknownKeycode` を送出する。
引数付きのキーコードは表ではなく `KeycodeCodec` の定数とビット演算で組み立てる。

### 3.2 文字列の表記

設定ファイルの文字列は `Mapping::KeycodeNotation`、layout.vil の文字列は `Mapping::VialNotation` が、読み込み時に一度だけ解析する。

| 形式 | 例 |
|---|---|
| 別名 | `A`, `Enter`, `Tab`, `!`, `MouseButton1`, `VolumeUp`, `NoKey`, `Trans`（`data/aliases.yaml`） |
| QMK 名 | `KC_A`, `KC_BTN1`, `QK_BOOT` |
| 修飾キー式 | `Cmd + Shift + A`, `Ctrl + Option + Left` |
| 関数形式 | `LSFT(KC_1)`, `SGUI(KC_4)`, `LGUI_T(KC_LANG2)`, `LT(1, KC_A)`, `LT1(Space)`, `MO(3)`, `OSM(MOD_LSFT)` |
| 参照 | `Macro('名前')`, `TapDance('名前')`, `Macro(0)`, `M2`, `TD(4)` |
| 名前付きショートカット | `Shortcut('名前')`, `Shortcut('アプリ:カテゴリ:ラベル')`（同梱の定義） |
| 生の値 | `0x0B17`（解読して当てはまる型になる。この例は `Ctrl + Shift + Command + T`） |

decompile が書く正規形は「別名 → 修飾キー式（`Ctrl, Option, Shift, Command` の順）→ 関数形式 → `0xHHHH`」。
参照は `Macro('名前')` / `TapDance('名前')` で書く。不変条件は `parse(format(k)) == k`。
詳細は [notation.md](notation.md)。

### 3.3 名前付きショートカット

`config/shortcuts.yaml` の `shortcuts: { 名前: 表記 }` を `ShortcutLibrary` として `Profile#shortcuts` が持つ。
`Shortcut('名前')` は解析の時点で定義の `Keycode` そのものになる（`MacroCall` のような参照の値は作らない）ので、
どの位置が `Shortcut(...)` で書かれていたかは Profile に残らない。書き出すときは値が定義のちょうど 1 つと一致すれば `Shortcut('名前')` にする。

同梱のショートカット（`data/shortcuts/`）は `Profile#shortcuts` に入れず、読むときだけ使う（`References.new(preset_shortcuts:)` で渡し、`References#shortcut(name)` が利用者の定義を先に、なければ同梱のものを引く）。

### 3.4 注記（notes）

割り当てには「何のための操作か」の注記を付けられる（設定ファイルでは `{ key: <表記>, note: <注記> }`）。

- 注記はキーコードを包まず、別の `notes` Hash（場所 => String）で持つ。`Keycode` はデバイスに書く値だけを表す
- 場所: `Layer#notes`（`KeyPosition`。割り当てのある位置だけ）、`EncoderBinding#notes`（`:push` / `:ccw` / `:cw`）、
  `TapDance#notes`（`:on_tap` など）、`Combo#notes`（`:output_key` だけ）。コンボのトリガーとマクロのキーは割り当てではないので対象外
- `Layer` / `EncoderBinding` / `TapDance` / `Combo` は `keycode_at(場所)` を持ち、場所の扱いをそろえている。
  注記を引くのは `Layer` / `EncoderBinding` / `TapDance` が `note(場所)`、`Combo` が `output_note`
- `ProfileMapper#to_image` は注記を使わない（compile の結果は注記で変わらない）

nape_pro-layout の `Assignment(keycode, label, shortcut)` のように包まなかったのは、`ProfileMapper#to_image`・意味検証・
`KeycodeNotation` が `Keycode` をそのまま扱えるようにするため。

## 4. エンティティと不変条件

### Layer

- `index` は `LayerRef` の範囲（0〜31）、`name` は空でない 50 文字以内、`description` は任意
- `keys` は割り当てのある位置だけを持つ（ない位置は compile で KC_NO（0）になる。キーのない枠だけがデバイスで -1）
- `encoders` は `:left` / `:right` の両方が必須
- `notes` の位置は `keys` にある位置だけ
- 番号がレイヤー数（10）に収まるか、重複がないかは `Profile#diagnostics`

### Macro と MacroStep

- `index` は M0〜M127 の番号、`name` は空でない文字列。`steps` は 1 つ以上
- `Tap` / `Down` / `Up(keys)`: keys は 1 つ以上の `Keycode`（16bit 値ならどれでもよい）
- `Delay(ms)`: 0〜65024（Vial のバイト列が 2 バイト `(ms % 255) + 1, (ms / 255) + 1` のため）
- `Text(content)`: 空でない ASCII 文字列。NUL（マクロの終端）と `0x01`（命令の接頭辞）は使えない
- `MacroStep` の `kind` は `Image::MacroAction` の kind と同じ記号（`:tap` / `:down` / `:up` / `:delay` / `:text`）
- `preset` は同梱のショートカットの名前（macros/ に `preset:` で書いたもの。`steps` はその手順）。デバイスにはないので設定ファイルに書き戻すときだけ使う。なければ nil

### TapDance

- `index` は TD(0)〜TD(255) の番号。4 つの動作（`on_tap`, `on_hold`, `on_double_tap`, `on_tap_hold`）はすべて `Keycode`。
  使わない動作は `NO_KEY`
- `tapping_term` は 0〜0xFFFF（ミリ秒）。設定ファイルで省略すると 250

### Combo

- `index` は 0〜255。`trigger_keys` は 1 つ以上の `Keycode`、`output_key` は `Keycode`
- トリガーの数（Cornix は 4 まで）と件数の上限は `Profile#diagnostics`

### Profile

- 要素の型だけを生成時に検査し、ファイルをまたぐ整合性（番号・名前の重複、上限、参照先）は `#diagnostics` に任せる。
  設定ファイルの誤りを 1 件ずつではなく、まとめて報告するため
- `#layer(index)` / `#macro(index)` などは番号の要素（重複していれば先のもの）
- `#references` は名前参照の対応表（`{ macros: 名前 => 番号, tap_dances: 名前 => 番号, shortcuts: 名前 => Keycode }`）。
  Mapping の `References.new(**profile.references)` にそのまま渡せる

## 5. 座標系（PositionMap）

Cornix の配列の知識はすべて `Domain::PositionMap`（`lib/cornix/domain/position_map.rb`）に置く。
他のクラスは行・列の計算をしない（ProfileMapper も `PositionMap#matrix` / `#position_at` / `#encoder_push_matrix` だけを使う）。

### 論理位置: `KeyPosition(hand:, row:, col:)`

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
テンプレートは `lib/cornix/position_map.yaml`、利用者版は `config/position_map.yaml`。

### 物理位置: layout.vil の `layout[layer][row][col]`（8 行 × 7 列）

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

### 変換規則（`PositionMap#matrix(position)` → `[row, col]`）

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
- layout.vil の `-1` は `Image::DeviceImage` では nil。ProfileMapper は position_map にある位置で割り当てのないものを KC_NO（0）にし、nil にするのはキーのない枠（プッシュ以外の col 6）と定義のないレイヤーだけ。
  `-1` だと `cornix device apply` がその位置を飛ばして前の値が残り、Vial の読み込みも失敗しうるため
- テスト: `spec/domain/position_map_spec.rb`（全位置の物理座標と逆変換）、`spec/mapping/profile_mapper/*`（レイヤー・エンコーダの配置、旧 compile 結果との一致）

## 6. 意味検証（`Profile#diagnostics`）

`Profile#diagnostics(capabilities = Capabilities::CORNIX)` が `[Diagnostic]` を返す（実装は `Domain::ProfileDiagnostics`）。

| 対象 | error | warning |
|---|---|---|
| レイヤー | 枚数の上限、番号の上限・重複 | 番号の抜け |
| マクロ / タップダンス / コンボ | 件数の上限、番号の上限・重複、名前の重複 | |
| コンボ | トリガーの数の上限 | |
| すべての割り当て（レイヤーのキーとエンコーダ、マクロのキー、タップダンスの動作、コンボのトリガーと出力） | `M(n)` / `TD(n)` の参照先がない、レイヤー番号がレイヤー数を超える | レイヤー数の内だが定義されていないレイヤーを指す、`Capabilities#unsupported_keycodes` にある特殊キー（書き込みは止めない。`Capabilities::CORNIX` の表は空で、表は `Application::Environment#capabilities` が足す） |

`path` は `layers[0].left_hand.row0.tab` や `macros[2].steps[1].keys[0]` のようなモデル内のパス（番号は Profile の配列の位置）。
ファイル上の位置への写像は Storage（`Storage::DiagnosticLocator`）が行う。検証の全体は [validation.md](validation.md)。

## 7. DeviceImage（生データ）

`Image::DeviceImage` はデバイスと layout.vil が持つ値を、解釈せずに 16bit 整数とバイト列のまま持つ型。Domain には依存しない。
差分（`Planning::ImageDiff`）はこの型どうしで取る。

| 項目 | 形 |
|---|---|
| `layers` | `[layer][row][col]` => Integer（キーコード）か nil（キーがない。.vil の -1） |
| `encoders` | `[layer][encoder]` => `EncoderRecord(ccw, cw)`。push はマトリクス側（layers）にある |
| `macros` | `[index]` => `[MacroAction(kind, keys, value)]` |
| `tap_dances` | `[index]` => `TapDanceRecord(on_tap, on_hold, on_double_tap, on_tap_hold, tapping_term)` |
| `combos` | `[index]` => `ComboRecord(keys, output)`（keys は 4 要素、未使用は 0 = KC_NO） |
| `settings` | `{ QSID => Integer }` |
| `meta` | .vil のその他のトップレベル項目（version, uid, vial_protocol, via_protocol, layout_options, alt_repeat_key, key_override）。解釈せずに運ぶ |

## 8. Profile ⇄ DeviceImage の対応（ProfileMapper）

`Mapping::ProfileMapper#to_image(profile)`（compile）と `#to_profile(image, position_map:, previous: nil)`（decompile）。
`to_image(to_profile(image))` が image に戻るように対応させる。

| Profile | DeviceImage（to_image） | to_profile で読まないもの |
|---|---|---|
| `layers` | 10 枚。レイヤーは index の位置に置き、定義のないレイヤーはすべて nil。割り当てのない位置は KC_NO（0）、キーのない位置は nil。エンコーダの push は `PositionMap#encoder_push_matrix` の位置 | すべての位置とエンコーダが nil のレイヤー |
| `Layer#encoders` | `[layer][左, 右]` の `EncoderRecord`（定義のないレイヤーは ccw / cw とも nil） | （nil は KC_NO として読む） |
| `macros` | 32 個。未使用は `[]` | 動作が空の枠 |
| `tap_dances` | 32 個。未使用は KC_NO × 4 と tapping_term 250 | KC_NO × 4 で tapping_term が 250（か nil）の枠 |
| `combos` | 32 個。トリガーは 4 個まで 0 で埋める。未使用はすべて 0 | トリガーと出力がすべて KC_NO の枠（トリガーは末尾の KC_NO だけ落とす） |
| `settings` | QSID の昇順 | |
| `metadata` | version / uid / vial_protocol / via_protocol（nil でも書く）、vendor_product_id / product_id / matrix（あれば）、`extra_keys` | |
| `shortcuts`・注記 | 書かない（デバイスにない） | previous から引き継ぐ |

- 解釈できない 16bit 値は `Keycode::Raw` のまま持つ
- `previous`（設定ファイルから読んだ Profile）があれば、同じ番号の要素の名前と説明、キーコードが変わっていない場所の注記、
  メタデータの keyboard と、extra のうち extra_keys 以外の項目（file_naming など）、名前付きショートカットを引き継ぐ（`ProfileMapper::Inheritance`）。
  いまの decompile は空の config/ にしか書かないので previous を渡さない（名前は `Macro 0` などの既定の名前になる）

## 9. 設定ファイル（config/）

読み書きは `Storage::ConfigRepository`（読む: `ConfigLoader`、書く: `ConfigWriter`）。ファイルごとの形式は `Storage::Schema::*File`。
拡張子は `.yaml` と `.yml` のどちらでも読み、書くときは `.yaml`。

```
config/
  metadata.yaml               キーボードの情報（必須）
  position_map.yaml           キーの名前と位置の対応（必須）
  settings/qmk_settings.yaml  QMK の設定（任意）
  shortcuts.yaml              名前付きショートカット（任意。利用者が作る）
  layers/{番号}_{名前}.yaml
  macros/{番号 2 桁}_{名前}.yaml
  tap_dance/{番号 2 桁}_{名前}.yaml
  combos/{番号 2 桁}_{名前}.yaml
```

```yaml
# layers/1_symbols.yaml
name: Symbols
index: 1
description: 記号レイヤー
mapping:
  left_hand:
    row0: { tab: Escape, Q: Question, W: DoubleQuote, E: Equal, R: NoKey, T: Tilde }
    row1:
      caps: Trans
      A: { key: "@", note: アットマーク }   # 注記付きの形
    row2:                                   # グループ（row0〜row3, thumb_keys）は必須。値は空でもよい
    row3:
    thumb_keys:                             # 書かないキー・空の値のキーは割り当てなし
  right_hand:
    row0:
    row1:
    row2:
    row3:
      left: Ctrl + Option + Shift + Command + Left
    thumb_keys:
  encoders:                                 # 省略した操作は KC_NO
    left: { push: PlayPause, ccw: Rewind, cw: FastForward }
    right: { push: LGUI(KC_0), ccw: Command + Minus, cw: Command + Plus }

# macros/04_copy_current_line.yaml
name: Copy Current Line
index: 4                                    # M4
sequence:
  - { action: down, keys: KC_LGUI }         # tap / down / up は keys（1 つかリスト）
  - { action: tap, keys: [KC_LEFT] }
  - { action: delay, duration: 100 }        # ミリ秒
  - { action: text, content: "hello" }      # ASCII
  - { action: up, keys: KC_LGUI }

# macros/05_window_capture.yaml
index: 5
preset: 'macOS:システム:ウィンドウキャプチャ'  # sequence の代わりに同梱のショートカットの手順（name を省くと preset の名前）

# tap_dance/02_paste_variants.yaml
name: Paste Variants
index: 2                                    # TD(2)
actions:                                    # 省略した動作は KC_NO
  on_tap: LGUI(KC_V)
  on_hold: Macro('Copy Selected')
  on_double_tap: Macro('Copy Current Word')
  on_tap_hold: Macro('Copy Current Line')
tapping_term: 250                           # 省略すると 250

# combos/06_left_click.yaml
name: Left Click
index: 6
trigger_keys: [KC_LEFT, KC_DOWN]
output_key: MouseButton1

# settings/qmk_settings.yaml
keyboard:
  tapping_term: 180
  permissive_hold: true
vial:
  combo_timing_window: 50

# shortcuts.yaml
shortcuts:
  前のタブへ: Command + Shift + [
```

- 読む順は metadata → position_map → macros → tap_dance → shortcuts（ここで名前参照の対応表を作る）→ settings → layers → combos
- マクロ・タップダンス・コンボの `enabled` は読み飛ばす（旧形式との互換）
- 問題はすべて集めて `Storage::InvalidConfig` で 1 回送出し、`ファイル: キーの位置: 内容` の形で報告する
