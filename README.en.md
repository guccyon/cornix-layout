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

### Typical Use Cases

Cornix's main usage patterns are explained through three use cases.

<details>
<summary><b>Use Case 1: Decompile layout.vil from Any Location</b></summary>

**Scenario**: Convert a `layout.vil` exported from Vial to YAML format for editing

**Steps**:
```bash
# 1. Download layout.vil (e.g., ~/Downloads/layout.vil)
# Export from Vial: "File > Export Layout"

# 2. Navigate to Cornix project
cd ~/work/cornix

# 3. Decompile (can specify any path)
cornix decompile ~/Downloads/layout.vil

# 4. Check generated configuration
ls -la config/
# config/layers/     - Layer files
# config/macros/     - Macro files
# config/tap_dance/  - Tap dance files
# config/combos/     - Combo files

# 5. Edit configuration
vim config/layers/0_base.yaml

# 6. Compile (with auto-validation)
cornix compile

# 7. Import generated layout.vil into Vial
# Vial: "File > Import Layout" → select layout.vil
```

**Key Points**:
- `cornix decompile` accepts layout.vil from any path
- Defaults to `tmp/layout.vil` when no argument provided
- Automatically blocked by lock protection if `config/` already exists

</details>

<details>
<summary><b>Use Case 2: Edit Existing Configuration and Compile</b></summary>

**Scenario**: `config/` directory already exists and you want to edit and compile

**Steps**:
```bash
# 1. Check current configuration
ls config/layers/

# 2. Edit layer file
vim config/layers/1_symbol.yaml

# 3. Validate (optional, automatically run by compile)
cornix validate

# 4. Compile (with auto-validation)
cornix compile

# 5. Check changes (optional)
git diff layout.vil

# 6. Import into Vial
```

**Key Points**:
- `cornix compile` automatically runs validation
- Compilation aborts if validation errors exist
- Version control (git) usage recommended

</details>

<details>
<summary><b>Use Case 3: Intelligent Rename with LLM</b></summary>

**Scenario**: Rename files with generic names ("Macro 0", "Tap Dance 1") to meaningful names

**Steps**:
```bash
# 1. Check current configuration
ls config/macros/
# 00_macro.yml, 01_macro.yml, ... (generic names)

# 2. Interactive rename (requires Claude CLI)
cornix rename

# 3. Claude AI analysis and suggestions
# Analyzes file contents and proposes meaningful names

# 4. Respond to suggestions with y/n/edit
# y: approve
# n: skip
# e: manual edit

# 5. Execute rename (auto-backup)
# Backup created at config.backup_<timestamp>/

# 6. Compilation verification
# Automatically verifies structure preservation

# 7. Check results
ls config/macros/
# 00_bracket_pair.yml, 01_end_of_line.yml, ... (meaningful names)
```

**Key Points**:
- Requires Claude Code CLI (`claude` command)
- Deeply infers purpose from macro key sequences
- Transaction-based processing (all success or full rollback)
- Auto-updates Name-based references only (Index-based/Legacy preserved)

</details>

**Claude Code Usage Tips**:

When editing configuration with `claude` command and Claude AI:

1. **Validate before edit**: Check current configuration with `cornix validate`
2. **Prefer modifier expressions**: `Cmd + Q` format is more readable than QMK syntax
3. **Prefer name-based references**: Reference macros/tap dances with `Macro('name')` format
4. **Validate after edit**: Auto-validate and compile with `cornix compile`
5. **Use skills**: Intelligent rename with `/rename` skill

### Generate Configuration Files from Existing layout.vil

```bash
# Use default (tmp/layout.vil)
cornix decompile

# Or specify any file path
cornix decompile ~/Downloads/layout.vil
cornix decompile /path/to/custom.vil
```

**⚠️ Critical - Lock Protection**: If the `config/` directory already contains configuration files, decompilation will be automatically blocked. This is a safety feature to prevent accidental overwrites.

**Error Message Example**:
```
⚠️  Error: config/ directory already contains configuration files.
```

**Workaround**:
```bash
# Option 1: Use cleanup command to remove existing configuration
cornix cleanup
cornix decompile ~/Downloads/layout.vil

# Option 2: Manually backup and remove
mv config config.backup
cornix decompile ~/Downloads/layout.vil
```

**Background**: This feature prevents accidental overwriting of existing configurations. Always backup or remove existing configuration before decompiling a new `layout.vil`.

**Cleanup Command**:

Use the `cornix cleanup` command to safely remove generated files:

```bash
# Normal cleanup (protected if lock file exists)
cornix cleanup

# Force cleanup (prompts for confirmation to delete lock file)
cornix cleanup -f
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

Use the `cornix rename` command to automatically rename macros, tap dances, combos, and layers using Claude AI's deep content analysis for meaningful names.

#### Operation Modes

**Interactive Mode (Recommended)**: Interactive mode with user confirmation

```bash
cornix rename
```

In this mode, Claude AI analyzes each file and displays rename suggestions, and users respond with `y`/`n`/`e`(dit). This is the safest and recommended method.

**Advanced Mode (For Advanced Users)**: Direct control with `bin/rename_file` command

```bash
# Single file rename (dry-run)
ruby bin/rename_file \
  --old-path config/macros/03_macro.yml \
  --new-basename 03_end_of_line.yml \
  --name "End of Line" \
  --description "Jump to end of line" \
  --dry-run

# Batch rename (via JSON)
ruby bin/rename_file --batch tmp/rename_plans.json
```

Advanced Mode is suitable for automation in scripts or CI pipelines, but **Interactive Mode** is recommended for normal usage.

#### LLM Integration Architecture

`cornix rename` uses a **hybrid architecture** combining Claude AI and Ruby execution:

**1. LLM Part (Claude AI Skill)**:
- Deep analysis of file contents
- Intent inference from key sequences
- Generation of meaningful names
- Pattern detection (brackets, copy, function template, etc.)
- Confidence level suggestions (high/medium/low)

**2. Ruby Part (Static Execution)**:
- File operations (rename, YAML updates)
- Auto-backup/rollback
- Compilation verification
- Transaction processing

**3. JSON Coordination**:
```json
// tmp/rename_plans.json
[
  {
    "old_path": "config/macros/03_macro.yml",
    "new_basename": "03_end_of_line.yml",
    "content_updates": {
      "name": "End of Line",
      "description": "Jump to end of line with Cmd+Right"
    }
  }
]
```

Claude AI generates suggestions → saves to JSON → Ruby safely applies

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

  # Reference macro by name (recommended)
  A: Macro('Bracket Pair')

  # Reference tap dance by name (recommended)
  fn: TapDance('Layer Switch')
```

#### Macro, Tap Dance, and Combo References

Cornix supports three reference formats:

**1. Name-based Format (Recommended)**: Reference by name for maximum readability
```yaml
# Reference macro by name
A: Macro('Bracket Pair')

# Reference tap dance by name
fn: TapDance('Layer Switch')

# Reference combo by name
combo1: Combo('Escape Alternative')
```

**Benefits**:
- Configuration files are self-documenting and highly readable
- References auto-update when files are renamed (with `cornix rename`)
- Function is immediately clear when editing

**2. Index-based Format (Explicit)**: Reference by index
```yaml
# Reference macro by index
A: Macro(0)

# Reference tap dance by index
fn: TapDance(2)
```

**Benefits**:
- Useful when you want explicit index control
- Easy migration from existing configs

**3. QMK Legacy Format (Backward Compatible)**: Traditional QMK format
```yaml
# Macro (M prefix)
A: M0

# Tap Dance (TD function)
fn: TD(2)
```

**Benefits**:
- Familiar to QMK users
- Existing configs work unchanged

**Recommendation**: Use **Name-based format** for new configs. `cornix decompile` automatically generates Name-based format.

**Note**:
- All formats compile to the same `layout.vil` (Vial compatible)
- `cornix rename` auto-updates Name-based references only
- Index-based / Legacy formats are preserved for backward compatibility but won't auto-update

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

**Important**: Validation is automatically run before compilation.

```bash
cornix compile
```

If there are validation errors, compilation will be automatically aborted. To run validation only:

```bash
cornix validate
```

Import the generated `layout.vil` into Vial and flash it to your keyboard.

## Configuration Validation

Use the `cornix validate` command to validate configuration files before compilation.

```bash
# Validate configuration files
cornix validate

# On success
✓ All validations passed

# On failure
✗ Validation failed:
  Error: Layer 0_base.yaml, symbol 'LT1': Invalid keycode 'InvalidKeycode'
  Error: Layer 1_symbols.yaml: Unknown position symbol 'UnknownSymbol'
```

**Important**: `cornix compile` automatically runs validation, so explicit `validate` calls are usually unnecessary.

### Phase 1 Implemented Validation Items

The following validation items are implemented (Phase 1 complete):

<details>
<summary><b>1. YAML Syntax Validation</b></summary>

- Detects syntax errors in all YAML files
- Displays user-friendly error messages for parse errors
- Skips further validation for files with YAML errors (prevents multiple errors)

**Detection Example**:
```
Error: config/layers/0_base.yaml: Invalid YAML syntax - mapping values are not allowed here
```

</details>

<details>
<summary><b>2. Metadata Validation</b></summary>

- Checks for existence of `metadata.yaml`
- Validates required fields: `keyboard`, `version`, `uid`, `vial_protocol`, `via_protocol`
- Validates `vendor_product_id` format (`0xXXXX` format)
- Validates `matrix` configuration type and range (`rows`, `cols` are positive integers)

**Detection Example**:
```
Error: metadata.yaml: Missing required field 'keyboard'
Error: metadata.yaml: Invalid vendor_product_id format (expected 0xXXXX)
```

</details>

<details>
<summary><b>3. Position Map Validation</b></summary>

- Verifies symbols in `position_map.yaml` are unique
- Detects when the same symbol is assigned to multiple physical positions
- Detects duplicates across left and right hands
- Ignores nil or empty strings

**Detection Example**:
```
Error: position_map.yaml: Duplicate symbol 'Q' at: left_hand.row0[1], right_hand.row0[2]
```

</details>

<details>
<summary><b>4. Keycode Validation</b></summary>

- Verifies all keycodes in layers are valid QMK keycodes or aliases
- Validates function-style keycodes (`MO(1)`, `LSFT(A)`, `LT(2, Space)`, etc.)
- Recursively validates function arguments (supports nested functions)
- Validates modifier expressions (`Cmd + Q`, etc.)
- Catches typos early

**Detection Example**:
```
Error: Layer 0_base.yaml, symbol 'Q': Invalid keycode 'Spce' (did you mean 'Space'?)
Error: Layer 1_symbol.yaml, symbol 'W': Invalid function argument in 'LSFT(InvalidKey)'
```

</details>

<details>
<summary><b>5. Position Map Reference Validation</b></summary>

- Verifies symbols used in layers (`LT1`, `RT1`, etc.) are defined in `position_map.yaml`
- Detects undefined position symbol references
- Warns (not error) if `position_map.yaml` doesn't exist

**Detection Example**:
```
Error: Layer 0_base.yaml: Unknown position symbol 'UnknownKey' (not defined in position_map.yaml)
```

</details>

<details>
<summary><b>6. Layer Index Validation</b></summary>

- Layer filenames must start with a number (e.g., `0_base.yaml`)
- Layer indices must be in the 0-9 range
- No duplicate layer indices

**Detection Example**:
```
Error: Layer file 'base.yaml' must start with layer index (e.g., 0_base.yaml)
Error: Duplicate layer index 1: 1_symbol.yaml, 1_number.yaml
```

</details>

<details>
<summary><b>7. Macro/Tap Dance/Combo Name Uniqueness</b></summary>

- Each file must have a `name` field
- Names must be unique across files

**Detection Example**:
```
Error: Duplicate macro name 'Bracket Pair' in files: 00_bracket.yml, 01_bracket_copy.yml
```

</details>

<details>
<summary><b>8. Layer Reference Validation</b></summary>

- Name-based references (`Macro('name')`, `TapDance('name')`) must point to existing names
- Index-based references (`Macro(0)`, `TapDance(2)`) range check only (0-31)
- Legacy references (`M0`, `TD(2)`) range check only

**Detection Example**:
```
Error: Layer 0_base.yaml, symbol 'Q': Macro 'Unknown Macro' not found
Error: Layer 1_symbol.yaml, symbol 'W': Macro index 99 out of range (0-31)
```

</details>

### Phase 2 Not Yet Implemented

The following validations are planned for future Phase 2:

- Macro sequence syntax validation
- Tap dance action syntax validation
- Combo trigger count validation
- QMK Settings type and range checking
- Encoder configuration validation

### Recommended Workflow

```bash
# Edit configuration
vim config/layers/0_base.yaml

# Compile (with auto-validation)
cornix compile
```

Compilation automatically aborts if validation errors exist.

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

## Flexible Reference System

Cornix supports three reference formats for macros, tap dances, and combos. Each format has its own advantages and can be used depending on the use case.

### Three Reference Formats

#### 1. Name-based Format (Recommended)

**The most readable and self-documenting format**. Referencing by name makes it immediately clear what each macro/tap dance/combo does just by looking at the configuration file.

```yaml
# In layer file
mapping:
  Q: Macro('End of Line')           # Reference macro by name
  W: TapDance('Escape or Layer')    # Reference tap dance by name
  E: Combo('Bracket Pair')          # Reference combo by name
```

**Benefits**:
- **High Readability**: `Macro('End of Line')` is clearer than `M3`
- **Self-Documenting**: Configuration files are understandable without comments
- **Auto-Update**: References automatically update when renamed with `cornix rename`

**Use Cases**:
- Creating new layers (recommended)
- Sharing configurations in team development
- Configurations maintained long-term

#### 2. Index-based Format (Explicit)

**Explicitly specifies indices**. References by numeric index (0-31 range).

```yaml
# In layer file
mapping:
  Q: Macro(0)           # Reference macro by index
  W: TapDance(2)        # Reference tap dance by index
  E: Combo(1)           # Reference combo by index
```

**Benefits**:
- **Explicit**: Useful when you want direct index control
- **Stable**: References don't change during rename
- **Flexible**: Can reference even if file doesn't exist (for files to be added later)

**Use Cases**:
- Dynamically generated configurations
- When index needs to be fixed
- When auto-update during rename is not desired

#### 3. QMK Legacy Format (Backward Compatible)

**Traditional QMK standard format**. Maintains compatibility with existing QMK configurations.

```yaml
# In layer file
mapping:
  Q: M0           # Legacy macro format
  W: TD(2)        # Legacy tap dance format
```

**Benefits**:
- **Backward Compatibility**: Existing QMK configurations work as-is
- **QMK Standard**: Familiar to QMK users
- **No Migration Required**: Can use existing configurations unchanged

**Use Cases**:
- Migrating from existing QMK configurations
- When maintaining QMK standard format

### Behavioral Differences

| Feature | Name-based | Index-based | Legacy |
|---------|-----------|------------|--------|
| **Readability** | ⭐⭐⭐ | ⭐ | ⭐ |
| **Decompile Output** | ✅ Always this format | ❌ Converted to Name-based | ❌ Converted to Name-based |
| **Rename Auto-Update** | ✅ Auto-updated | ❌ Preserved | ❌ Preserved |
| **Validator Check** | ✅ File existence check | ⚠️ Range check only | ⚠️ Range check only |
| **File Required** | ❌ Required | ✅ Not required (0-31 range) | ✅ Not required |

### Recommendations

**For New Configs**: Use Name-based format. `cornix decompile` automatically generates Name-based format.

**For Existing Configs**: All formats are fully supported and migration is not required. Existing legacy format works as-is.

### Decompiler Behavior

`cornix decompile` always generates YAML files in **Name-based format**. This is by design to maximize readability.

```yaml
# layout.vil (QMK format)
M5, TD(2), COMBO(1)

# ↓ After decompile (YAML)
mapping:
  Q: Macro('End of Line')      # Name-based format
  W: TapDance('Escape')        # Name-based format
  E: Combo('Bracket')          # Name-based format
```

**Note**: Even if written in Index-based or Legacy format, it will be converted to Name-based format after decompile. This is intentional design (unification to more readable format).

### FileRenamer Behavior (Selective Update)

When renaming files with `cornix rename`, **only Name-based references** are automatically updated.

```yaml
# Before rename
config/macros/03_macro.yml: name: "Old Name"

# In layer file
mapping:
  Q: Macro('Old Name')    # ✅ Will be auto-updated
  W: Macro(3)             # ❌ Will not change (Index-based)
  E: M3                   # ❌ Will not change (Legacy)

# After rename (cornix rename executed)
config/macros/03_end_of_line.yml: name: "End of Line"

# In layer file
mapping:
  Q: Macro('End of Line') # ✅ Auto-updated
  W: Macro(3)             # ❌ Unchanged (intentional)
  E: M3                   # ❌ Unchanged (intentional)
```

**Design Reason**: Respects user choice and maintains predictability. Users who chose Name-based format expect auto-updates, while users using Index-based/Legacy formats prioritize stability.

### Round-trip Integrity

All formats guarantee compilation to layout.vil and round-trip integrity.

```bash
# Same layout.vil generated regardless of format used
cornix compile  # → layout.vil (QMK format)

# round-trip check
mv config config.backup
cornix decompile  # Generated in Name-based format
cornix compile
ruby bin/diff_layouts  # ✓ FILES ARE IDENTICAL
```

## Modifier Expressions (VS Code-style)

Cornix supports readable modifier expressions similar to VS Code or IDE keybindings. Write `Cmd + Q` and it automatically compiles to QMK format (`LGUI(KC_Q)`).

### Basic Usage

```yaml
# config/layers/0_base.yaml
mapping:
  Q: Cmd + Q              # → LGUI(KC_Q)
  W: Shift + W            # → LSFT(KC_W)
  E: Ctrl + C             # → LCTL(KC_C)
  R: Alt + Tab            # → LALT(KC_TAB)
```

### Automatic QMK Shortcut Detection

When combining multiple modifiers, QMK shortcut functions are automatically used:

```yaml
mapping:
  # 2 modifiers
  Q: Shift + Cmd + Q          # → LSG(KC_Q)
  W: Ctrl + Shift + W         # → LCS(KC_W)
  E: Ctrl + Alt + E           # → LCA(KC_E)

  # 3 modifiers
  R: Ctrl + Shift + Alt + R   # → MEH(KC_R)
  T: Ctrl + Shift + Cmd + T   # → LCSG(KC_T)

  # 4 modifiers (HYPR)
  Y: Ctrl + Shift + Alt + Cmd + Y  # → HYPR(KC_Y)
```

### Order Independent

Modifier order doesn't matter. Both compile to the same QMK code:

```yaml
Q: Shift + Cmd + Q    # → LSG(KC_Q)
W: Cmd + Shift + W    # → LSG(KC_W)  # Same despite different order
```

### Supported Modifiers

#### Left-side Modifiers (default)

| Notation | QMK Function | Description |
|----------|--------------|-------------|
| `Shift` | `LSFT` | Left Shift |
| `Ctrl`, `Control` | `LCTL` | Left Ctrl |
| `Alt`, `Option` | `LALT` | Left Alt/Option |
| `Cmd`, `Command`, `Win`, `Gui` | `LGUI` | Left Cmd/Win |

#### Right-side Modifiers (explicit)

| Notation | QMK Function | Description |
|----------|--------------|-------------|
| `RShift` | `RSFT` | Right Shift |
| `RCtrl`, `RControl` | `RCTL` | Right Ctrl |
| `RAlt`, `ROption` | `RALT` | Right Alt/Option |
| `RCmd`, `RCommand`, `RWin`, `RGui` | `RGUI` | Right Cmd/Win |

### QMK Shortcut List

Cornix automatically detects the following QMK shortcuts:

#### 2 Modifiers

| Combination | QMK | Combination | QMK |
|------------|-----|------------|-----|
| Ctrl + Shift | LCS | RCtrl + RShift | RCS |
| Ctrl + Alt | LCA | RCtrl + RAlt | RCA |
| Ctrl + Cmd | LCG | RCtrl + RCmd | RCG |
| Shift + Alt | LSA | RShift + RAlt | RSA |
| Shift + Cmd | LSG | RShift + RCmd | RSG |
| Alt + Cmd | LAG | RAlt + RCmd | RAG |

#### 3 Modifiers

| Combination | QMK | Description |
|------------|-----|-------------|
| Ctrl + Shift + Alt | MEH | MEH key |
| Ctrl + Shift + Cmd | LCSG | Left 3-mod |
| Ctrl + Alt + Cmd | LCAG | Left 3-mod |
| Shift + Alt + Cmd | LSAG | Left 3-mod |

#### 4 Modifiers

| Combination | QMK | Description |
|------------|-----|-------------|
| Ctrl + Shift + Alt + Cmd | HYPR | HYPR key |

### Flexible Spacing

Spaces are optional:

```yaml
Q: Cmd + Q      # Recommended (readable)
W: Cmd+W        # Also works
E: Cmd  +  E    # Also works
```

### Combined with Key Aliases

Keys can use aliases:

```yaml
mapping:
  Q: Cmd + Space      # → LGUI(KC_SPACE)
  W: Shift + Tab      # → LSFT(KC_TAB)
  E: Ctrl + Enter     # → LCTL(KC_ENTER)
  R: Alt + KC_ESCAPE  # → LALT(KC_ESCAPE)
```

### Usage Examples

#### Application Operations

```yaml
mapping:
  Q: Cmd + Q          # Quit app
  W: Cmd + W          # Close window
  N: Cmd + N          # New window
  T: Cmd + T          # New tab
```

#### Editor Shortcuts

```yaml
mapping:
  C: Cmd + C          # Copy
  V: Cmd + V          # Paste
  X: Cmd + X          # Cut
  Z: Cmd + Z          # Undo
  S: Cmd + S          # Save
```

#### Advanced Combinations

```yaml
mapping:
  F: Ctrl + Shift + F     # → LCS(KC_F) - Project search
  R: Ctrl + Shift + R     # → LCS(KC_R) - Refactor
  P: Ctrl + Shift + P     # → LCS(KC_P) - Command palette
```

### Escape Hatch

You can still write QMK function syntax directly:

```yaml
mapping:
  Q: LGUI(KC_Q)           # Direct QMK syntax
  W: Cmd + W              # Modifier expression (recommended)
```

### Decompile Behavior

**⚠️ Critical - Irreversible Conversion**: The `cornix decompile` command does not automatically convert back to modifier expressions. QMK format is preserved.

```yaml
# Before compile (original YAML)
mapping:
  Q: Cmd + Q

# layout.vil (after compile)
# → LGUI(KC_Q)

# After decompile (YAML)
mapping:
  Q: LGUI(Q)    # Does not revert to modifier expression
```

**Reason**: The layout.vil file only contains QMK format, and information about the original notation (modifier expression vs QMK syntax) is lost. Additionally, QMK functions can be written in various ways (`LGUI(KC_Q)`, `Cmd + Q`, `LGUI_T(KC_Q)`, etc.), making it difficult to accurately restore the original notation.

**Impact**:
- **Initial decompile**: YAML generated from layout.vil is always in QMK format (e.g., `LGUI(Q)`)
- **Round-trip after edit**: Written in modifier expression (`Cmd + Q`) → compile → decompile → converted to QMK format (`LGUI(Q)`)
- **Manual maintenance**: To continue using modifier expressions, you need to manually edit YAML files

**Best Practices**:
1. **Use version control**: Manage YAML files with `git` etc. and check with `git diff` after decompile
2. **Manual correction after round-trip**: Convert QMK format back to modifier expressions as needed
3. **Mixing allowed**: QMK format and modifier expressions can coexist in the same layer

**Round-trip Integrity**:
While modifier expressions don't revert, round-trip integrity as QMK format is fully guaranteed:

```bash
# 1. Create YAML using modifier expressions
echo "Q: Cmd + Q" > config/layers/0_base.yaml

# 2. Compile
cornix compile  # → LGUI(KC_Q) in layout.vil

# 3. Decompile
mv config config.backup
cornix decompile  # → LGUI(Q) in config/layers/*.yaml

# 4. Recompile
cornix compile

# 5. Verify
ruby bin/diff_layouts  # ✓ FILES ARE IDENTICAL (complete match as QMK format)
```

### Limitations

1. **Plus sign as key**: `Shift + +` cannot be parsed. Use `LSFT(KC_PLUS)` instead.

2. **Function as key**: `Cmd + LT(1, Space)` cannot be parsed. Use `LGUI(LT(1, Space))` instead.

3. **Modifier as key**: Possible, but be explicit:
   ```yaml
   Q: Shift + Shift    # → LSFT(KC_LSHIFT) (sticky Shift)
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

  # Thumb keys (defined within left_hand/right_hand thumb_keys in position_map.yaml)
  l_thumb_left: LGUI_T(KC_LANG2)    # Left thumb, left: GUI when held, LANG2 when tapped
  l_thumb_middle: LT(1, Space)      # Left thumb, middle: Layer 1 when held, Space when tapped
  l_thumb_right: LT(2, Escape)      # Left thumb, right: Layer 2 when held, Escape when tapped
  r_thumb_left: LT(2, Enter)        # Right thumb, left: Layer 2 when held, Enter when tapped
  r_thumb_middle: MO(1)             # Right thumb, middle: Layer 1 while held
  r_thumb_right: LT(3, KC_LANG1)    # Right thumb, right: Layer 3 when held, LANG1 when tapped

  # Transparent key (pass through to lower layer)
  B: Trans                    # or Transparent, ___
```

**Note**: Files generated by `decompile` automatically use alias format, but you can manually write `KC_A` or `Transparent` and they will work (treated equally during compile).

## Position Map (Physical Position Mapping)

The `position_map.yaml` defines the mapping between physical positions on the keyboard and symbol names. This file allows you to reference keys with intuitive names like `Q` or `A` in layer files.

### File Placement and Generation

**System Template**: `lib/cornix/position_map.yaml`
- Default template provided by the system (Cornix standard layout)
- Users do not edit this directly

**User Configuration**: `config/position_map.yaml`
- Automatically generated from `lib/cornix/position_map.yaml` when `cornix decompile` is executed
- **User customizable** (symbol names can be freely changed)
- Loaded when `cornix compile` is executed

**Workflow**:
```
1. cornix decompile
   → Load lib/cornix/position_map.yaml (template)
   → Generate config/position_map.yaml

2. User customizes symbol names (optional)
   → Edit config/position_map.yaml

3. cornix compile
   → Load config/position_map.yaml (user version)
   → Generate layout.vil
```

**Important Design Principle**:
- `lib/cornix/position_map.yaml`: Template that requires **no reconstruction** (not actual data from layout.vil)
- `config/position_map.yaml`: **User-specific** customizable file

### File Format

Defines the mapping between physical positions and symbol names.

```yaml
left_hand:
  row0: [tab, Q, W, E, R, T]          # 6 elements
  row1: [caps, A, S, D, F, G]         # 6 elements
  row2: [lshift, Z, X, C, V, B]       # 6 elements
  row3: [lctrl, command, option]      # 3 elements (standard grid keys only)
  thumb_keys: [left, middle, right]   # simplified symbol names

right_hand:
  row0: [Y, U, I, O, P, backspace]    # 6 elements
  row1: [H, J, K, L, colon, enter]    # 6 elements
  row2: [N, M, comma, dot, up, rshift]# 6 elements
  row3: [left, down, right]           # 3 elements (standard grid keys only)
  thumb_keys: [left, middle, right]   # simplified symbol names

encoders:
  left:
    push: push    # simplified symbol names (uniqueness guaranteed by hierarchical path)
    ccw: ccw
    cw: cw
  right:
    push: push
    ccw: ccw
    cw: cw
```

### Key Array Order and Structure

**Standard Grid Keys**:
- **left_hand**: Keys are arranged **physically from left to right** as `col0`, `col1`, `col2`, ...
- **right_hand**: Keys are also arranged **physically from left to right** as `col0`, `col1`, `col2`, ...
  - Example: `row0` is `Y` (leftmost) → `U` → `I` → `O` → `P` → `backspace` (rightmost)

**Row Structure**:
- `row0`, `row1`, `row2`: 6 elements each (standard grid keys)
- `row3`: 3 elements each (standard grid keys only)

**Thumb Keys**:
- Defined as `thumb_keys` within `left_hand`/`right_hand` sections (3 keys each)
- Physically located in the latter half of `row3` (cols 3-5), but logically treated as an independent section within each hand
- Placed immediately after row3, aligning the physical placement with the structure
- Symbol names are simplified (`left`, `middle`, `right`)
- Referenced in layer files with hierarchical paths:
  - Left thumb keys: `left_hand.thumb_keys.left`, `left_hand.thumb_keys.middle`, `left_hand.thumb_keys.right`
  - Right thumb keys: `right_hand.thumb_keys.left`, `right_hand.thumb_keys.middle`, `right_hand.thumb_keys.right`

**Encoders**:
- Rotary encoder push buttons and rotations are defined separately in the `encoders` section
- Kept as an independent section since they are clearly at a different physical location from keys
- Symbol names are simplified (`push`, `ccw`, `cw`)
- Referenced in layer files with hierarchical paths:
  - Left encoder: `encoders.left.push`, `encoders.left.ccw`, `encoders.left.cw`
  - Right encoder: `encoders.right.push`, `encoders.right.ccw`, `encoders.right.cw`

**Uniqueness Guaranteed by Hierarchical Paths**:
- Since v2.0, symbol names are guaranteed unique by their full hierarchical path
- Example: `left_hand.thumb_keys.left` and `right_hand.thumb_keys.left` are recognized as different keys
- This eliminates the need for redundant prefixes (`l_`, `r_`, etc.) in symbol names

This mapping allows you to reference keys with an intuitive hierarchical structure in layer files.

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

### bin/ Architecture

Cornix's command-line interface has a clean structure focused on maintainability.

#### Directory Structure

```
bin/
├── cornix                    # Main CLI dispatcher (~62 lines)
├── subcommands/              # Subcommand implementations
│   ├── compile.rb           # Compile with auto-validation
│   ├── decompile.rb         # Decompile with lock protection
│   ├── validate.rb          # Validation-only
│   ├── cleanup.rb           # Safe cleanup
│   └── rename.rb            # RenameCommand wrapper
├── diff_layouts              # Round-trip check tool
└── rename_file               # File renamer CLI (advanced)
```

#### Delegation Pattern

`bin/cornix` functions as a simple dispatcher, delegating actual processing to each subcommand.

```ruby
# Excerpt from bin/cornix
case command
when 'compile'
  load File.expand_path('subcommands/compile.rb', __dir__)
when 'decompile'
  load File.expand_path('subcommands/decompile.rb', __dir__)
when 'validate'
  load File.expand_path('subcommands/validate.rb', __dir__)
# ...
end
```

**Benefits**:
- **Code deduplication**: Eliminated 100% duplication, all commands go through `cornix` dispatcher
- **Consistency**: Common initialization process for all subcommands
- **Maintainability**: Each subcommand managed in independent file

#### Auto-validation Feature

`cornix compile` automatically runs validation. This eliminates the need for users to explicitly call `validate`.

```ruby
# Excerpt from bin/subcommands/compile.rb
# 1. Run validation
validator = Cornix::Validator.new(config_dir)
unless validator.validate
  puts validator.errors
  exit 1
end

# 2. Run compilation
compiler = Cornix::Compiler.new(config_dir)
compiler.compile
```

#### CLI Helpers (CliHelpers)

Provides utility functions shared across all subcommands.

```ruby
# lib/cornix/cli_helpers.rb
module Cornix
  module CliHelpers
    # Protect existing files in config/ directory
    def self.check_config_lock(config_dir)
      # ...
    end

    # Verify config/ directory exists
    def self.ensure_config_exists(config_dir)
      # ...
    end

    # Safe deletion of generated files
    def self.cleanup(config_dir, layout_path)
      # ...
    end
  end
end
```

#### Data Flow

```
User Input
    ↓
cornix [command] [args]
    ↓
bin/cornix (dispatcher)
    ↓
    ├─ compile.rb → Validator → Compiler → layout.vil
    ├─ decompile.rb → CliHelpers.check_config_lock → Decompiler → config/
    ├─ validate.rb → Validator → error/success
    ├─ cleanup.rb → CliHelpers.cleanup → file deletion
    └─ rename.rb → RenameCommand → FileRenamer → config/
```

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

#### Test Suite Details

**Total Test Cases**: 479 tests (all passing)
**Total Lines**: 5,400+ lines
**Execution Time**: ~1.8 seconds

<details>
<summary><b>Test File Breakdown</b></summary>

| Test File | Tests | Content |
|-----------|-------|---------|
| `keycode_parser_spec.rb` | 106 | KeycodeParser features (reference format parsing, function parsing, modifier expression parsing, unparse) |
| `modifier_expression_compiler_spec.rb` | 52 | ModifierExpressionCompiler features (QMK shortcut auto-detection, modifier aliases) |
| `compiler_spec.rb` | 48 | Compiler features (keycode conversion, layer/macro/tap dance/combo compilation) |
| `reference_resolver_spec.rb` | 44 | ReferenceResolver features (name⇔index resolution, caching, validation) |
| `file_renamer_spec.rb` | 57 | FileRenamer features (rename, YAML updates, backup/rollback, layer reference updates) |
| `decompiler_spec.rb` | 37 | Decompiler features (QMK→alias conversion, YAML generation, legacy→name-based upgrade) |
| `validator_spec.rb` | 73 | Validator features (Phase 1 all validation items, modifier expression validation) |
| `keycode_resolver_spec.rb` | 21 | KeycodeResolver features (alias⇔QMK bidirectional conversion) |
| `position_map_spec.rb` | 17 | PositionMap features (physical position mapping) |
| `integration_spec.rb` | 17 | Integration tests (full round-trip, reference system integration, modifier expression integration) |

</details>

<details>
<summary><b>Test Coverage Details</b></summary>

**Flexible Reference System**:
- Name-based reference parsing and resolution
- Index-based reference parsing and resolution
- Legacy reference backward compatibility
- Auto-upgrade by Decompiler (Legacy → Name-based)
- Selective update by FileRenamer (Name-based only auto-update)
- Differential validation by Validator (Name-based: existence check, Index-based: range only)
- Round-trip integrity (complete match for all formats)

**Modifier Expression System**:
- Modifier expression parsing (`Cmd + Q`, etc.)
- QMK shortcut auto-detection (LCS, LSG, MEH, HYPR, etc.)
- Order-independent matching (`Cmd + Shift` = `Shift + Cmd`)
- Modifier alias resolution (Command, Win, Option, etc.)
- Nested function fallback
- Validation by Validator (modifier names, key names)
- Round-trip integrity (complete match as QMK format)

**Compiler**:
- Keycode resolution (alias → QMK format)
- Function argument processing (layer number preservation, modifier argument conversion)
- Layer structure compilation
- Macro/tap dance/combo compilation
- Reference system integration
- Modifier expression integration

**Decompiler**:
- QMK → alias conversion (reverse resolution)
- YAML generation (readable format)
- Legacy format auto-upgrade
- Position Map template generation
- Round-trip integrity

**Validator**:
- Phase 1 all validation items (8 items)
- Reference format validation (Name-based, Index-based, Legacy)
- Modifier expression validation
- Clear error messages

**FileRenamer**:
- File rename (index prefix preservation)
- YAML content updates (name, description fields)
- Backup/rollback (transaction-based)
- Layer reference auto-update (Name-based only)
- Compilation verification

**Integration**:
- Compile → Decompile → Compile full round-trip
- Integrity for all reference formats
- QMK format preservation for modifier expressions
- No data loss

</details>

**Round-trip Check** (Manual Verification):
```bash
# 1. Backup existing config
mv config config.backup

# 2. Decompile from original
cornix decompile  # Uses tmp/layout.vil

# 3. Compile from generated config
cornix compile

# 4. Compare
ruby bin/diff_layouts
# Expected: === ✓ FILES ARE IDENTICAL ===
```

## Troubleshooting

Common issues and solutions.

<details>
<summary><b>Common Issues</b></summary>

### 1. Decompile Blocked

**Symptom**:
```
⚠️  Error: config/ directory already contains configuration files.
```

**Cause**: Lock protection feature is activated because existing `config/` directory exists.

**Solution**:
```bash
# Option 1: Use cleanup command
cornix cleanup

# Option 2: Manual backup
mv config config.backup

# Decompile again
cornix decompile
```

---

### 2. Compilation Error: Invalid keycode

**Symptom**:
```
Error: Layer 0_base.yaml, symbol 'Q': Invalid keycode 'Spce'
```

**Cause**: Typo in keycode (`Spce` → should be `Space`)

**Solution**:
```bash
# 1. Identify file and line from error message
vim config/layers/0_base.yaml

# 2. Fix typo
# Spce → Space

# 3. Validate
cornix validate

# 4. Recompile
cornix compile
```

**Common Typos**:
- `Spce` → `Space`
- `Entr` → `Enter`
- `Backspce` → `Backspace`
- `Trans` → `Transparent` (both correct but `Trans` recommended)

---

### 3. Undefined Position Symbol

**Symptom**:
```
Error: Layer 0_base.yaml: Unknown position symbol 'UnknownKey'
```

**Cause**: Referencing a symbol not defined in `position_map.yaml`.

**Solution**:
```bash
# 1. Check position_map.yaml
cat config/position_map.yaml

# 2. Check symbol usage in layer file
grep "UnknownKey" config/layers/*.yaml

# 3. Option A: Add symbol to position_map.yaml
vim config/position_map.yaml

# 3. Option B: Fix symbol in layer file
vim config/layers/0_base.yaml
```

---

### 4. Duplicate Layer Index

**Symptom**:
```
Error: Duplicate layer index 1: 1_symbol.yaml, 1_number.yaml
```

**Cause**: Multiple files with the same layer index (`1_`).

**Solution**:
```bash
# Change layer index of one file
mv config/layers/1_number.yaml config/layers/2_number.yaml
```

---

### 5. Duplicate Macro Name

**Symptom**:
```
Error: Duplicate macro name 'Bracket Pair' in files: 00_bracket.yml, 01_bracket_copy.yml
```

**Cause**: Multiple macro files with the same `name` field.

**Solution**:
```bash
# Change name in one file
vim config/macros/01_bracket_copy.yml
# name: "Bracket Pair" → "Bracket Pair Alt"
```

---

### 6. Non-existent Macro/Tap Dance Reference

**Symptom**:
```
Error: Layer 0_base.yaml, symbol 'Q': Macro 'Unknown Macro' not found
```

**Cause**: Name-based reference pointing to non-existent name.

**Solution**:
```bash
# 1. Check existing macro names
ls config/macros/
cat config/macros/*.yml | grep "^name:"

# 2. Fix reference in layer file
vim config/layers/0_base.yaml
# Macro('Unknown Macro') → Macro('Existing Macro')
```

---

### 7. Round-trip Check Fails

**Symptom**:
```
=== ✗ FILES DIFFER ===
Layer 0: ...
```

**Cause**: Data inconsistency in Compile/Decompile process.

**Solution**:
```bash
# 1. Check which section has differences
ruby bin/diff_layouts

# 2. Collect detailed information for bug report
cp tmp/layout.vil tmp/layout.original.vil
cp layout.vil tmp/layout.recompiled.vil

# 3. Report issue on GitHub
# https://github.com/anthropics/claude-code/issues
```

---

### 8. Modifier Expression Disappears After Decompile

**Symptom**: Wrote `Cmd + Q` but after decompile it becomes `LGUI(Q)`.

**Cause**: By design. Decompiler does not automatically convert back to modifier expressions.

**Explanation**:
- Only QMK format is saved in layout.vil
- Information about original notation (modifier expression vs QMK syntax) is lost
- See "Modifier Expressions > Decompile Behavior" section for details

**Workaround**:
- Use version control (git) to manually maintain modifier expressions
- Accept QMK format (functionally equivalent)

---

### 9. Claude Code CLI (`claude` command) Not Found

**Symptom**:
```
Error: claude command not found. Please install Claude Code CLI.
```

**Cause**: Claude Code CLI required for `cornix rename` is not installed.

**Solution**:
```bash
# Install Claude Code CLI
# https://claude.ai/download

# Verify installation
claude --version
```

---

### 10. YAML Syntax Error

**Symptom**:
```
Error: config/layers/0_base.yaml: Invalid YAML syntax - mapping values are not allowed here
```

**Cause**: YAML syntax error (invalid indentation, illegal characters, etc.)

**Solution**:
```bash
# 1. Check file from error message
vim config/layers/0_base.yaml

# 2. Common causes
# - Mixed spaces and tabs in indentation
# - Missing colon after key
# - Special characters in string (quotes needed)

# 3. Validate YAML (optional)
ruby -ryaml -e "YAML.load_file('config/layers/0_base.yaml')"
```

</details>

### Configuration Validation

**Note**: Validation is automatically performed during `cornix compile`. You can also validate separately:

```bash
# Validate configuration files
cornix validate

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

# Validate & compile (auto-validation)
cornix compile
```

### Compilation Errors

Common errors:

- **YAML syntax errors**: Invalid indentation, illegal characters
- **Invalid keycodes**: Typos (`Spce` → should be `Space`)
- **Undefined position symbols**: Referencing symbols not in `position_map.yaml`
- **Duplicate layer numbers**: Multiple layer files with the same number
- **Duplicate macro names**: Multiple macro files with the same name
- **Invalid references**: Referencing non-existent macros like `MACRO(unknown_macro)`

See "Troubleshooting" section for details.

## Tips & Best Practices

Tips and best practices for using Cornix effectively.

### Configuration Management

**1. Prefer Name-based References**

```yaml
# ✅ Recommended: Name-based format
Q: Macro('End of Line')
W: TapDance('Escape or Layer')

# ❌ Not recommended: Index-based/Legacy format (low readability)
Q: Macro(5)
W: TD(2)
```

**Reasons**:
- Configuration files are self-documenting with high readability
- Auto-updates when files are renamed with `cornix rename`
- Clear for team development

**2. Use Modifier Expressions**

```yaml
# ✅ Recommended: Modifier expressions (readable)
Q: Cmd + Q
W: Ctrl + Shift + F

# ❌ Not recommended: QMK syntax (functionally equivalent but less readable)
Q: LGUI(KC_Q)
W: LCS(KC_F)
```

**Note**: Automatically reverts to QMK format after decompile. Maintain with version control.

**3. Use Version Control**

```bash
# Manage configuration files with Git
git init
git add config/
git commit -m "Initial keyboard configuration"

# Check changes after editing
vim config/layers/0_base.yaml
git diff config/

# Commit
git commit -am "Update base layer: add Cmd+Q shortcut"
```

**Reasons**:
- Configuration history can be tracked
- Easy rollback of incorrect changes
- Easy to manually restore modifier expressions after decompile

**4. Regular Validation**

```bash
# Before editing
cornix validate

# Edit
vim config/layers/0_base.yaml

# After editing (with auto-validation)
cornix compile
```

### File Naming

**1. Use Descriptive Filenames**

```bash
# ✅ Good examples
config/layers/0_base.yaml
config/layers/1_symbol.yaml
config/layers/2_number.yaml
config/macros/00_bracket_pair.yml
config/macros/01_end_of_line.yml

# ❌ Bad examples (too generic)
config/layers/0_layer.yaml
config/layers/1_layer.yaml
config/macros/00_macro.yml
config/macros/01_macro.yml
```

**Reasons**:
- Contents can be inferred from filename alone
- Can auto-rename with `cornix rename`

**2. Preserve Index Prefix**

```bash
# Preserve index when renaming
mv config/macros/03_macro.yml config/macros/03_end_of_line.yml
# ✅ Correct: 03_ preserved

mv config/macros/03_macro.yml config/macros/05_end_of_line.yml
# ❌ Wrong: Changing index breaks references
```

**Reasons**:
- Index determines order in layout.vil
- Changing breaks references from layers

### Claude Code Integration

**1. Validation Before and After Editing**

```bash
# Before editing with Claude Code
cornix validate

# Claude Code session
claude

# Edit files in session
# ...

# After editing
cornix compile  # with auto-validation
```

**2. Use Skills**

```bash
# Intelligent rename
claude
> /rename

# Use custom skills if available
> /compile
> /validate
```

**3. Incremental Changes**

```yaml
# ❌ Bad: Too many changes at once
Q: Cmd + Q
W: Cmd + W
E: Cmd + E
# ... 50 lines of changes

# ✅ Good: Small repeated changes
Q: Cmd + Q
# Compile & test

W: Cmd + W
# Compile & test
```

**Reason**: Easier to identify cause when errors occur

### Common Mistakes to Avoid

<details>
<summary><b>1. Specifying Layer Number as KC_*</b></summary>

```yaml
# ❌ Wrong
Q: MO(KC_3)    # Switch to layer 3

# ✅ Correct
Q: MO(3)       # Specify number directly
```

**Reason**: Layer numbers are preserved as-is (`KC_3` is the "3" key keycode)

</details>

<details>
<summary><b>2. Not Converting Modifier Arguments</b></summary>

```yaml
# ❌ Wrong
Q: LSFT(1)     # This is not "Shift+1" but will error

# ✅ Correct (auto-converted)
Q: LSFT(1)     # Automatically converted to LSFT(KC_1) during compile

# Or explicit
Q: LSFT(KC_1)
```

**Note**: Compiler automatically converts numeric arguments in modifier functions to `KC_*` format.

</details>

<details>
<summary><b>3. Expecting All Reference Formats to Auto-Update</b></summary>

```yaml
# Before rename
config/macros/03_macro.yml: name: "Old Name"

# In layer
Q: Macro('Old Name')  # ✅ Will auto-update
W: Macro(3)           # ❌ Won't update
E: M3                 # ❌ Won't update

# After rename (cornix rename executed)
Q: Macro('New Name')  # ✅ Auto-updated
W: Macro(3)           # ❌ Unchanged (intentional)
E: M3                 # ❌ Unchanged (intentional)
```

**Reason**: Only Name-based references auto-update. Index-based/Legacy formats are preserved to respect user choice.

</details>

<details>
<summary><b>4. Expecting Modifier Expressions to Revert After Decompile</b></summary>

```yaml
# Before compile
Q: Cmd + Q

# layout.vil (after compile)
# LGUI(KC_Q)

# After decompile
Q: LGUI(Q)    # ❌ Does not revert to modifier expression
```

**Reason**: Only QMK format is saved in layout.vil, and information about original notation is lost.

**Workaround**: Manually maintain with version control (git), or accept QMK format.

</details>

<details>
<summary><b>5. Changing Index Prefix</b></summary>

```bash
# ❌ Wrong
mv config/macros/03_macro.yml config/macros/05_macro.yml
# Index changes from 03→05, breaking layer references

# ✅ Correct
mv config/macros/03_macro.yml config/macros/03_end_of_line.yml
# Index 03 preserved, only filename changed
```

**Reason**: Index determines order in layout.vil and is referenced from layers.

</details>

### Performance and Efficiency

**1. ReferenceResolver Caching**

ReferenceResolver caches YAML files on first reference (~7KB, 100ms). Subsequent resolutions are instantaneous.

**2. Use Validator**

Running `cornix validate` before compilation catches errors early. However, `cornix compile` automatically runs validation, so it's usually unnecessary.

**3. Batch Rename**

When renaming many files, use `cornix rename` batch mode for efficiency (transaction-based processing).

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

---

## Appendix

### Complete Keycode List

Cornix supports 337 QMK official keycode aliases. See `lib/cornix/keycode_aliases.yaml` for the complete list.

<details>
<summary><b>Main Keycode Categories</b></summary>

**Basic Keycodes**:
- Letters: `A`-`Z`
- Numbers: `0`-`9`
- Function keys: `F1`-`F24`
- Navigation: `Up`, `Down`, `Left`, `Right`, `Home`, `End`, `PageUp`, `PageDown`
- Editing: `Enter`, `Escape`, `Backspace`, `Tab`, `Space`, `Delete`
- Modifiers: `LShift`, `RShift`, `LCtrl`, `RCtrl`, `LAlt`, `RAlt`, `LCmd` (LGUI), `RCmd` (RGUI)

**Symbol Keys**:
```yaml
"-": KC_MINUS
"=": KC_EQUAL
"[": KC_LBRACKET
"]": KC_RBRACKET
"\\": KC_BSLASH
";": KC_SCOLON
"'": KC_QUOTE
"`": KC_GRAVE
",": KC_COMMA
".": KC_DOT
"/": KC_SLASH
```

**Layer Switching**:
- `MO(layer)`: Momentary (while held)
- `TG(layer)`: Toggle
- `TO(layer)`: To (switch)
- `TT(layer)`: Tap Toggle (tap to toggle, hold for MO)
- `DF(layer)`: Default (change default layer)
- `OSL(layer)`: One Shot Layer (once only)
- `LT(layer, key)`: Layer Tap (layer when held, key when tapped)

**Modifiers**:
- Mod-Tap: `LCTL_T(key)`, `LSFT_T(key)`, `LALT_T(key)`, `LGUI_T(key)`
- One Shot Modifiers: `OSM(mod)`
- Modifier combinations: `C(key)`, `S(key)`, `A(key)`, `G(key)`
- QMK shortcuts: `LCS`, `LSG`, `MEH`, `HYPR` (see "QMK Modifier Shortcuts" for details)

**Media Keys**:
- `VolumeUp`, `VolumeDown`, `Mute`
- `MediaPlayPause`, `MediaNextTrack`, `MediaPrevTrack`, `MediaStop`
- `MediaFastForward`, `MediaRewind`, `MediaEject`

**Mouse Keys**:
- Movement: `MouseUp`, `MouseDown`, `MouseLeft`, `MouseRight`
- Buttons: `MouseBtn1`-`MouseBtn8`
- Wheel: `MouseWheelUp`, `MouseWheelDown`, `MouseWheelLeft`, `MouseWheelRight`
- Acceleration: `MouseAccel0`-`MouseAccel2`

**Special Keys**:
- `Transparent` / `Trans` / `___`: Transparent (pass through to lower layer)
- `NoKey`: Disabled
- `Reset`: Keyboard reset
- `Debug`: Debug mode

**Backlight/RGB**:
- Backlight: `BL_ON`, `BL_OFF`, `BL_TOGG`, `BL_INC`, `BL_DEC`
- RGB: `RGB_TOG`, `RGB_MOD`, `RGB_HUI`, `RGB_SAI`, `RGB_VAI`

</details>

### QMK Modifier Shortcuts

Cornix automatically detects 20+ QMK modifier shortcuts.

<details>
<summary><b>Complete Shortcut List</b></summary>

#### Left-side Modifiers (L prefix)

**2-modifier Combinations**:
| QMK | Combination | Description |
|-----|-------------|-------------|
| `LCS` | Ctrl + Shift | Left Ctrl + Shift |
| `LCA` | Ctrl + Alt | Left Ctrl + Alt |
| `LCG` | Ctrl + Cmd | Left Ctrl + GUI |
| `LSA` | Shift + Alt | Left Shift + Alt |
| `LSG` | Shift + Cmd | Left Shift + GUI |
| `LAG` | Alt + Cmd | Left Alt + GUI |

**3-modifier Combinations**:
| QMK | Combination | Description |
|-----|-------------|-------------|
| `MEH` | Ctrl + Shift + Alt | MEH key |
| `LCSG` | Ctrl + Shift + Cmd | Left Ctrl + Shift + GUI |
| `LCAG` | Ctrl + Alt + Cmd | Left Ctrl + Alt + GUI |
| `LSAG` | Shift + Alt + Cmd | Left Shift + Alt + GUI |

#### Right-side Modifiers (R prefix)

**2-modifier Combinations**:
| QMK | Combination | Description |
|-----|-------------|-------------|
| `RCS` | RCtrl + RShift | Right Ctrl + Shift |
| `RCA` | RCtrl + RAlt | Right Ctrl + Alt |
| `RCG` | RCtrl + RCmd | Right Ctrl + GUI |
| `RSA` | RShift + RAlt | Right Shift + Alt |
| `RSG` | RShift + RCmd | Right Shift + GUI |
| `RAG` | RAlt + RCmd | Right Alt + GUI |

**3-modifier Combinations**:
| QMK | Combination | Description |
|-----|-------------|-------------|
| `RCSG` | RCtrl + RShift + RCmd | Right Ctrl + Shift + GUI |
| `RCAG` | RCtrl + RAlt + RCmd | Right Ctrl + Alt + GUI |
| `RSAG` | RShift + RAlt + RCmd | Right Shift + Alt + GUI |

#### Special Combinations

**4 Modifiers**:
| QMK | Combination | Description |
|-----|-------------|-------------|
| `HYPR` | Ctrl + Shift + Alt + Cmd | HYPR key (all 4 modifiers) |

**Usage Example**:
```yaml
# Write in Cornix
Q: Ctrl + Shift + Alt + Cmd + Q

# Automatically converted to
# → HYPR(KC_Q)
```

</details>

### Position Map Template

Default template structure of `lib/cornix/position_map.yaml`.

<details>
<summary><b>Template Structure</b></summary>

```yaml
left_hand:
  row0: [tab, Q, W, E, R, T]
  row1: [lctrl, A, S, D, F, G]
  row2: [lshift, Z, X, C, V, B]
  row3: [caps, fn, command, option, space, esc]

right_hand:
  row0: [Y, U, I, O, P, backspace]
  row1: [H, J, K, L, colon, enter]
  row2: [N, M, comma, dot, up, rshift]
  row3: [enter, raise, lang, left, down, right]

encoders:
  left:
    push: l_rotary_push
    ccw: l_rotary_ccw
    cw: l_rotary_cw
  right:
    push: r_rotary_push
    ccw: r_rotary_ccw
    cw: r_rotary_cw
```

**Structure**:
- `left_hand` / `right_hand`: 6 keys per row (row0-row3)
- `encoders`: Rotary encoder configuration (push, ccw, cw)

**Array Order**:
- Both left and right hands ordered **physically from left to right**
- Right hand `row0` is `Y` (leftmost) → `U` → `I` → `O` → `P` → `backspace` (rightmost)

**Customization**:
Edit `config/position_map.yaml` to freely change symbol names.

```yaml
# Custom example
left_hand:
  row0: [tab, q, w, e, r, t]  # Changed to lowercase
  # ...

right_hand:
  row0: [y, u, i, o, p, bs]   # Shortened 'backspace' → 'bs'
  # ...
```

</details>

### Sample Configuration

Cornix provides different sample configurations through branch switching.

<details>
<summary><b>Available Sample Configurations</b></summary>

#### 1. Official Default Keymap (Recommended)

To edit based on the official Cornix default keymap:

```bash
# Check out cornix-default-keymap branch
git checkout cornix-default-keymap

# Check config/ directory
ls config/

# Edit configuration
vim config/layers/0_base.yaml

# Compile
cornix compile
```

**Features**:
- Cornix standard layout
- Recommended for beginners
- Configuration consistent with documentation

#### 2. Author's Keymap

To reference the author's (project maintainer's) keymap:

```bash
# Check out authors-keymap branch
git checkout authors-keymap

# Check config/ directory
ls config/

# View/edit configuration
vim config/layers/0_base.yaml

# Compile
cornix compile
```

**Features**:
- Real-world usage example
- Advanced feature utilization examples
- Customization hints

#### 3. Generate from Your Own layout.vil

To base on your own Vial configuration:

```bash
# Return to main branch
git checkout main

# Decompile your layout.vil
cornix decompile ~/Downloads/my_layout.vil

# Edit generated config/
vim config/layers/0_base.yaml

# Compile
cornix compile
```

#### How to Switch Branches

**If you have existing config/**:

```bash
# Backup current configuration
mv config config.my_backup

# Switch branch
git checkout cornix-default-keymap

# Check sample configuration
ls config/
```

**Return to original branch**:

```bash
# Return to main branch
git checkout main

# Restore backup
mv config.my_backup config
```

</details>

#### Community Contributions

Sample configurations are welcome:
- Share your own sample configurations in a new branch
- Contribute via pull request
- Add documentation to `examples/` directory

See "Contributing" section for details.

