# keycode_aliases.yaml Implementation

## 実装経緯（2026-03-05）

### 課題
- デコンパイル時にkeycode_aliases.yamlを動的生成していた
- QMK公式のBasic Keycodes, Layer Switching, Modifiersが網羅されていなかった

### 解決策
1. keycode_aliases.yamlをシステム提供の固定ファイルとして`lib/cornix/`に配置
2. QMK公式ドキュメント（https://docs.qmk.fm/keycodes）に基づき337行の包括的な定義を作成
3. デコンパイル時にはコピーせず、コンパイル時に直接参照

## 実装詳細

### ファイル配置
- **場所**: `lib/cornix/keycode_aliases.yaml`
- **行数**: 337行
- **フォーマット**: YAML

### Compilerでの参照
```ruby
# lib/cornix/compiler.rb:11-17
def initialize(config_dir)
  @config_dir = config_dir
  # lib/cornix/keycode_aliases.yaml を直接参照
  aliases_path = File.join(__dir__, 'keycode_aliases.yaml')
  @keycode_resolver = KeycodeConverter.new(aliases_path)
  @position_map = PositionMap.new("#{config_dir}/position_map.yaml")
end
```

### Decompilerでの扱い
```ruby
# lib/cornix/decompiler.rb:30-42
def decompile(output_dir)
  FileUtils.mkdir_p(output_dir)

  extract_metadata(output_dir)
  extract_position_map(output_dir)
  # copy_keycode_aliases メソッドと呼び出しを削除
  extract_qmk_settings(output_dir)
  extract_layers(output_dir)
  extract_macros(output_dir)
  extract_tap_dance(output_dir)
  extract_combos(output_dir)

  puts "✓ Decompilation completed: #{output_dir}"
end
```

## keycode_aliases.yamlの構成

### Basic Keycodes
- Letters (A-Z) → KC_A - KC_Z
- Numbers (0-9) → KC_0 - KC_9
- Symbols: `-`, `=`, `[`, `]`, `\`, `;`, `'`, `` ` ``, `,`, `.`, `/`
- Function Keys: F1-F24
- Navigation: Escape, Tab, Space, Enter, Backspace, Delete, Insert, Home, End, PageUp, PageDown, Arrows
- Modifiers: LCtrl, LShift, LAlt, LGui (LCmd/LWin), RCtrl, RShift, RAlt, RGui
- System: PrintScreen, ScrollLock, Pause, Application (Menu)
- Special: NoKey (KC_NO), Transparent (KC_TRNS), ___

### Numpad Keys
- NumLock, KpSlash, KpAsterisk, KpMinus, KpPlus, KpEnter
- Kp0-Kp9, KpDot, KpEqual, KpComma

### Media Keys
- Volume: VolumeUp, VolumeDown, Mute
- Playback: MediaPlayPause, MediaStop, MediaPrevious, MediaNext
- Other: MediaRewind, MediaFastForward, MediaEject, MediaSelect

### Mouse Keys
- Movement: MouseUp, MouseDown, MouseLeft, MouseRight
- Buttons: MouseButton1-5
- Wheel: MouseWheelUp, MouseWheelDown, MouseWheelLeft, MouseWheelRight
- Acceleration: MouseAccel0-2

### Layer Switching (説明のみ)
- MO(layer): Momentary layer switch
- DF(layer): Default layer
- TG(layer): Toggle layer
- TO(layer): To layer (exclusive)
- TT(layer): Tap toggle
- OSL(layer): One shot layer
- LT(layer, kc): Layer tap

### Mod-Tap (説明のみ)
- LCTL_T(kc): Left Control when held, kc when tapped
- LSFT_T(kc): Left Shift when held, kc when tapped
- LALT_T(kc): Left Alt when held, kc when tapped
- LGUI_T(kc): Left GUI when held, kc when tapped
- (右側も同様)
- MT(mod, kc): Generic mod-tap

### One Shot Modifiers (説明のみ)
- OSM(MOD_LCTL): One shot left control
- OSM(MOD_LSFT): One shot left shift
- OSM(MOD_LALT): One shot left alt
- OSM(MOD_LGUI): One shot left GUI

### Modifier Combinations (説明のみ)
- C(kc): Control + kc
- S(kc): Shift + kc
- A(kc): Alt + kc
- G(kc): GUI + kc
- HYPR(kc): Ctrl+Shift+Alt+GUI + kc
- MEH(kc): Ctrl+Shift+Alt + kc

### Backlight and RGB
- Backlight: BLOn, BLOff, BLToggle, BLStep, BLIncrease, BLDecrease, BLBreathe
- RGB: RGBToggle, RGBModeForward, RGBModeReverse, RGBHueIncrease, RGBHueDecrease, RGBSatIncrease, RGBSatDecrease, RGBValIncrease, RGBValDecrease

### Quantum Keys
- Reset, Boot, DebugToggle, ClearEEPROM
- AutoShiftToggle, AutoShiftDown, AutoShiftUp, AutoShiftReport

## 動作確認

### Round-trip Check結果
```
=== ✓ FILES ARE IDENTICAL ===

Version: ✓
UID: ✓
Vial protocol: ✓
Via protocol: ✓
Layout structure: ✓
Encoder layout: ✓
Macros: ✓
Tap Dance: ✓
Combos: ✓
Settings: ✓
```

### 確認済み事項
- ✅ config/にkeycode_aliases.yamlは生成されない
- ✅ lib/cornix/keycode_aliases.yamlが正しく参照される
- ✅ コンパイル・デコンパイルの完全一致

## 今後の拡張

### カスタムエイリアスの追加方法
1. `lib/cornix/keycode_aliases.yaml`を編集
2. `aliases:`セクションに追加:
   ```yaml
   MyCustomKey: KC_CUSTOM_KEYCODE
   ```
3. Round-trip checkで確認

### 新しいQMKキーコードの追加
1. QMK公式ドキュメントで新しいキーコードを確認
2. 該当するセクションに追加（または新規セクション作成）
3. コメントで説明を追加
4. README.mdの対応キーコードリストを更新
