# Cornix Keyboard Layout Manager

A human-readable layout configuration management system for the Cornix keyboard.

Since Vial's `layout.vil` file is difficult to edit directly, this tool provides an intuitive YAML-based configuration file system.

## Features

- 📝 **Human-Readable**: Easy-to-read and write YAML configuration files
- 🔤 **Alias Support**: Automatically uses readable aliases like `KC_TAB` → `Tab`, `KC_TRNS` → `Trans`
- 🗂️ **Modular**: Manage layers, macros, tap dances, and combos in separate files
- 🏷️ **Named Entities**: Give meaningful names to layers, macros, and tap dances
- 📊 **Differential Layers**: Upper layers only describe differences from Layer 0
- 💬 **Comment Support**: Add comments with `#`
- 🔄 **Bidirectional Conversion**: `layout.vil` ⇔ YAML configuration files

## Installation

```bash
git clone https://github.com/yourusername/cornix-layout.git
cd cornix-layout
```

## Usage

### Generate Configuration Files from Existing layout.vil

```bash
# Use default (tmp/layout.vil)
ruby bin/decompile

# Or specify any file path
ruby bin/decompile ~/Downloads/layout.vil
ruby bin/decompile /path/to/custom.vil
```

**Safety Feature**: If the `config/` directory already contains configuration files, decompilation will be automatically blocked.

```bash
# Clean up existing configuration before decompiling a new layout.vil
ruby bin/cornix cleanup
ruby bin/cornix decompile ~/Downloads/layout.vil

# Or manually backup and remove
mv config config.backup
ruby bin/cornix decompile ~/Downloads/layout.vil
```

**Cleanup Command**:

Use the `cornix cleanup` command to safely remove generated files:

```bash
# Normal cleanup (protected if lock file exists)
ruby bin/cornix cleanup

# Force cleanup (prompts for confirmation to delete lock file)
ruby bin/cornix cleanup -f
```

- During normal execution, processing stops if `.decompile.lock` file exists
- When using `-f` option for forced execution, a confirmation prompt is displayed
- Deletion targets: `config/` directory, `layout.vil` file

The following files will be generated under the `config/` directory:

```
config/
├── metadata.yaml              # Keyboard basic information
├── position_map.yaml          # Physical position to symbol mapping
├── settings/
│   └── qmk_settings.yaml      # QMK settings
├── layers/
│   ├── 0_base.yaml            # Base layer
│   ├── 1_symbol.yaml          # Symbol layer
│   └── ...
├── macros/
│   ├── bracket_pair.yaml
│   └── ...
├── tap_dance/
│   └── ...
└── combos/
    └── ...
```

**Note**:
- **Keycode Aliases** (`keycode_aliases.yaml`): Fixed file in `lib/cornix/`, not generated in `config/` (no editing needed as it's QMK standard)
- **Position Map** (`position_map.yaml`): Generated in `config/` from `lib/cornix/` template, customizable symbol names

### Intelligent File Renaming

Use the `cornix rename` command to automatically rename macros, tap dances, combos, and layers using Claude AI's deep content analysis:

```bash
# Interactive rename (requires Claude CLI)
cornix rename
```

**Prerequisites**:
- Claude Code CLI (`claude` command) must be installed
- If not installed, the process will abort with an error message

**Execution Flow**:

1. **Compile current configuration**: Save pre-rename state as baseline
2. **Claude AI analysis**:
   - Macros: Deeply infer purpose from key sequences (e.g., `[, ], Left` → "Bracket Pair")
   - Tap Dances: Analyze tap/hold/double-tap actions (e.g., `MO(1)` → "Layer 1 Switch")
   - Combos: Determine function from trigger keys and output
   - Layers: Infer intent from description field and overrides
3. **Display rename suggestions**: Show proposals for each file
4. **User confirmation**: Respond with `y`/`n`/`e`(dit) for each suggestion
5. **Execute renames**: Rename files and update YAML content after auto-backup
6. **Compile verification**: Verify layout.vil structure is preserved
7. **Cleanup temporary files**: Automatically delete logs and temporary files

**Example**:

```
──────────────────────────────────────────────────────────────────────
1. MACRO: 00_macro.yml

  Current:  00_macro.yml
  Proposed: 00_bracket_pair.yml

  Name:        Bracket Pair
  Description: Insert bracket pair [] with cursor positioning

  Reasoning:   Key sequence inserts left bracket, right bracket, then moves cursor left
  Confidence:  high

  Apply this rename? [Y/n/e(dit)]: y
  ✓ Added to rename queue
```

**Claude AI Analysis Capabilities**:
- Understands intent of complex key sequences
- Considers modifier key combinations (Shift, Cmd, Ctrl)
- Infers operation purpose from cursor movement patterns
- Context-aware naming (e.g., `function ()` + Left → "Function Template")

**Safety Features**:
- Automatic backup creation (`config.backup_<timestamp>/`)
- Transaction-based processing (all success or full rollback)
- Compilation verification (structure preservation check)
- Index prefix preservation (`00_`, `01_`, `0_`, `1_`, etc.)
- Layer reference integrity guarantee (index-based)
- Automatic rollback on errors

**Rename Targets**:
- Macros: Files with generic names ("Macro N")
- Tap Dances: Files with generic names ("Tap Dance N")
- Combos: Files with generic names ("Combo N")
- Layers: Files with generic names ("Layer N")

**Backup Cleanup**:
After successful rename, you'll be prompted to delete backup directories.

**Note**:
- **Keycode Aliases** (`keycode_aliases.yaml`): Fixed file in `lib/cornix/`, not generated in `config/` (no editing needed as it's QMK standard)
- **Position Map** (`position_map.yaml`): Generated in `config/` from `lib/cornix/` template, customizable symbol names

### Edit Configuration Files

Layer files generated by `decompile` use readable alias format.

Layer file (e.g., `config/layers/1_symbol.yaml`):

```yaml
name: Symbol
description: Symbol layer

# Only describe keys that differ from Layer 0
overrides:
  Q: LSFT(1)         # Input ! (Shift+1)
  W: LSFT(2)         # Input @ (Shift+2)
  E: LSFT(3)         # Input # (Shift+3)

  lshift: Trans      # Transparent (use key from lower layer)
  D: NoKey           # Disabled

  # Reference macro by name
  A: MACRO(bracket_pair)

  # Reference tap dance
  fn: TD(layer_switch)
```

**Alias Benefits**:
- `KC_TRNS` → `Trans` (more concise)
- `KC_NO` → `NoKey` (clearer meaning)
- `LSFT(KC_1)` → `LSFT(1)` (inner keycodes also converted)
- `KC_TAB` → `Tab` (more readable)

Macro file (e.g., `config/macros/bracket_pair.yaml`):

```yaml
name: bracket_pair
description: Insert [] and move cursor left
enabled: true

sequence:
  - action: tap
    keys: ["[", "]", Left]
```

### Compile to layout.vil

```bash
ruby bin/compile
```

Import the generated `layout.vil` into Vial and flash it to your keyboard.

## File Structure

### Layer Files

Layer files are named in the format `{index}_{name}.yaml`.

- `index`: Layer number (0-9)
- `name`: Any descriptive name

**Examples:** `0_base.yaml`, `1_symbol_mac.yaml`, `2_number.yaml`

To change layer numbers:

```bash
# To change 2_number.yaml to 5_number.yaml
mv config/layers/2_number.yaml config/layers/5_number.yaml

# Manually update MO(2), LT(2, ...) to MO(5), LT(5, ...) in other layer files
```

### Macro, Tap Dance, and Combo Files

These are named in the format `{name}.yaml` (no index prefix).

**The index is determined by alphabetical order of filenames.**

#### Macro File Example

```yaml
name: curly_bracket_pair
description: Insert {} and move cursor left
enabled: true

sequence:
  - action: down
    key: LShift

  - action: tap
    keys: ["[", "]"]

  - action: up
    key: LShift

  - action: tap
    key: Left
```

#### Tap Dance File Example

```yaml
name: screenshot_combo
description: Cmd+Shift+4 on tap, Cmd+Shift+5 on double tap
enabled: true

actions:
  on_tap: "LCmd+LShift+[4]"
  on_double_tap: "LCmd+LShift+[5]"
  on_hold: "-"
  on_tap_hold: "-"

tapping_term: 250
```

#### Combo File Example

```yaml
name: left_bracket
description: D+F inputs [
enabled: true

trigger:
  - D
  - F

output: "["
```

### Referencing in Layers

```yaml
# config/layers/1_symbol.yaml
overrides:
  # Reference macro by name (recommended)
  A: MACRO(bracket_pair)

  # Reference tap dance by name (recommended)
  fn: TD(layer_switch)

  # Index reference also possible (not recommended)
  B: MACRO(0)  # Hard to understand which macro
```

## Keycode Aliases

Keycode aliases are stored as a fixed file in `lib/cornix/keycode_aliases.yaml`. This file provides comprehensive keycode definitions based on the QMK official documentation ([https://docs.qmk.fm/keycodes](https://docs.qmk.fm/keycodes)).

**Important**: This file is a system-provided reference file and is not generated in the `config/` directory. It is automatically referenced during compilation.

### Supported Keycodes

`lib/cornix/keycode_aliases.yaml` includes comprehensive coverage of:

- **Basic Keycodes**: Letters, numbers, symbols, function keys, navigation keys, modifiers
- **Layer Switching**: `MO()`, `DF()`, `TG()`, `TO()`, `TT()`, `OSL()`, `LT()`
- **Modifiers**: Mod-Tap (`MT`, `LCTL_T`, etc.), One Shot Modifiers (`OSM`), modifier combinations (`C()`, `S()`, `A()`, `G()`)
- **Media Keys**: Volume control, playback, media controls
- **Mouse Keys**: Mouse movement, buttons, wheel operations
- **Backlight/RGB**: Backlight and RGB control
- **Quantum Keys**: Reset, debug, EEPROM operations

### Alias Examples

```yaml
aliases:
  # Basic keys
  A: KC_A
  Space: KC_SPACE
  Enter: KC_ENTER
  Escape: KC_ESCAPE

  # Modifiers
  LShift: KC_LSHIFT
  LCmd: KC_LGUI
  LCtrl: KC_LCTRL

  # Symbols (can be used as-is)
  "-": KC_MINUS
  "=": KC_EQUAL
  "[": KC_LBRACKET
  "]": KC_RBRACKET

  # Media keys
  VolumeUp: KC_VOLU
  VolumeDown: KC_VOLD
  Mute: KC_MUTE

  # Special keys
  Transparent: KC_TRNS
  Trans: KC_TRNS
  ___: KC_TRNS
  NoKey: KC_NO
```

### Usage in Layer Files

```yaml
# config/layers/1_symbol.yaml
overrides:
  # Basic keys
  Q: LShift
  W: Space

  # Layer switching
  fn: MO(1)                    # Layer 1 while held
  raise: TG(2)                 # Toggle layer 2

  # Mod-Tap (modifier when held, key when tapped)
  A: LCTL_T(A)                # Ctrl when held, A when tapped

  # Layer Tap
  space: LT(1, Space)         # Layer 1 when held, Space when tapped

  # Transparent key (pass through to lower layer)
  B: Trans                    # or Transparent, ___
```

**Note**: Files generated by `decompile` automatically use alias format, but you can manually write `KC_A` or `Transparent` and they will work (treated equally during compile).

## position_map.yaml

Defines the mapping between physical positions and symbol names.

```yaml
left_hand:
  row0: [tab, Q, W, E, R, T, null]
  row1: [lctrl, A, S, D, F, G, null]
  row2: [lshift, Z, X, C, V, B, l_rotary_push]
  row3: [caps, fn, option, command, space, esc, null]

right_hand:
  row0: [backspace, P, O, I, U, Y, null]
  row1: [backslash, colon, L, K, J, H, layer9]
  row2: [rshift, up, dot, comma, M, N, null]
  row3: [right, down, left, lang, raise, enter, null]
```

This mapping allows you to reference keys with intuitive names like `Q` or `A` in layer files.

## Available Macro Actions

```yaml
# Tap a key
- action: tap
  key: A              # Single key

- action: tap
  keys: [A, B, C]     # Multiple keys in sequence

# Hold a key down
- action: down
  key: LShift

- action: down
  keys: [LCmd, LShift]  # Multiple keys simultaneously

# Release a key
- action: up
  key: LShift

# Input text
- action: text
  content: "function ()"

# Delay
- action: delay
  duration: 100  # ms
```

## Library Feature (Community Macros)

Place community-created macros and tap dances in the `library/` directory.

```yaml
# config/metadata.yaml
library:
  enabled: true

  macros:
    - name: vscode_shortcuts
      enabled: true
    - name: emacs_keybinds
      enabled: false
```

⚠️ **Security Warning**: Always review the content of library macros before enabling them.

## Development

### Directory Structure

```
cornix-layout/
├── README.md                   # Japanese README
├── README.en.md                # English README
├── bin/
│   ├── compile                 # Compiler
│   ├── decompile               # Decompiler
│   └── verify                  # Verification script
├── lib/
│   └── cornix/
│       ├── compiler.rb
│       ├── decompiler.rb
│       ├── keycode_resolver.rb
│       ├── keycode_aliases.yaml # System-provided keycode aliases
│       ├── position_map.yaml    # Default physical position map template
│       └── position_map.rb
├── config/                     # Configuration files
└── layout.vil                  # Generated file
```

### Testing

The project includes a comprehensive RSpec test suite.

```bash
# Run all tests
bundle exec rspec

# Run specific test files
bundle exec rspec spec/compiler_spec.rb
bundle exec rspec spec/decompiler_spec.rb
bundle exec rspec spec/keycode_resolver_spec.rb
bundle exec rspec spec/position_map_spec.rb
bundle exec rspec spec/validator_spec.rb
bundle exec rspec spec/integration_spec.rb

# Run with detailed output
bundle exec rspec --format documentation
```

**Test Coverage**:
- **Compiler**: Keycode resolution, layer structure, macro/tap dance/combo compilation
- **Decompiler**: Alias conversion, YAML generation, round-trip integrity
- **KeycodeResolver**: Alias⇔QMK bidirectional conversion, system alias file loading
- **PositionMap**: Physical position to symbol mapping, position lookup
- **Validator**: Configuration file validation, duplicate name detection
- **Integration**: Full round-trip test (Compile→Decompile→Compile)

**Round-trip Check** (Manual Verification):
```bash
# 1. Backup existing config
mv config config.backup

# 2. Decompile from original
ruby bin/decompile  # Uses tmp/layout.vil

# 3. Compile from generated config
ruby bin/compile

# 4. Compare
ruby bin/diff_layouts
# Expected: === ✓ FILES ARE IDENTICAL ===
```

## Troubleshooting

### Configuration Validation

It is strongly recommended to validate your configuration files before compilation:

```bash
# Validate configuration files
ruby bin/validate

# On success
✓ All validations passed

# On failure
✗ Validation failed:
  Error: Layer 0_base.yaml, symbol 'LT1': Invalid keycode 'InvalidKeycode'
  Error: Layer 1_symbols.yaml: Unknown position symbol 'UnknownSymbol'
```

**Validation checks** (Phase 1 implemented):

1. **YAML Syntax Validation**
   - Detects syntax errors in all YAML files
   - Provides user-friendly error messages for parse errors

2. **Metadata Validation**
   - Checks for existence of `metadata.yaml`
   - Validates required fields (`keyboard`, `version`, `uid`, `vial_protocol`, `via_protocol`)
   - Validates `vendor_product_id` format (`0xXXXX`)
   - Validates `matrix` configuration type and range

3. **Position Map Validation**
   - Verifies symbols in `position_map.yaml` are unique
   - Detects when the same symbol is assigned to multiple physical positions
   - Detects duplicates across left and right hands

4. **Keycode Validation**
   - Verifies all keycodes in layers are valid QMK keycodes or aliases
   - Validates function-style keycodes (`MO(1)`, `LSFT(A)`, `LT(2, Space)`, etc.)
   - Catches typos early

5. **Position Map Reference Validation**
   - Verifies symbols used in layers (`LT1`, `RT1`, etc.) are defined in `position_map.yaml`
   - Detects undefined position symbol references

6. **Layer Index Validation**
   - Layer filenames must start with a number (e.g., `0_base.yaml`)
   - Layer indices must be in the 0-9 range
   - No duplicate layer indices

7. **Macro/Tap Dance/Combo Name Uniqueness**
   - Each file must have a `name` field
   - Names must be unique across files

8. **Layer Reference Validation**
   - `MACRO(name)` and `TD(name)` references must point to existing names

**Recommended workflow**:

```bash
# Edit configuration
vim config/layers/0_base.yaml

# Validate
ruby bin/validate

# Compile
ruby bin/compile
```

### Compilation Errors

Common errors:

- **YAML syntax errors**: Invalid indentation, illegal characters
- **Invalid keycodes**: Typos (`Spce` → should be `Space`)
- **Undefined position symbols**: Referencing symbols not in `position_map.yaml`
- **Duplicate layer numbers**: Multiple layer files with the same number
- **Duplicate macro names**: Multiple macro files with the same name
- **Invalid references**: Referencing non-existent macros like `MACRO(unknown_macro)`

## Contributing

Pull requests are welcome!

1. Fork this repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Create a pull request

## License

MIT License

## References

- [Vial Documentation](https://get.vial.today/)
- [QMK Firmware Documentation](https://docs.qmk.fm/)
- [QMK Keycodes](https://docs.qmk.fm/keycodes_basic)

---

Made with ❤️ for the Cornix keyboard community
