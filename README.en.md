# Cornix Keyboard Layout Manager

A human-readable layout configuration manager for the Cornix keyboard.

Vial's `layout.vil` is hard to edit by hand, so this tool manages the layout as YAML configuration files, converts between them and `layout.vil`, and can write changes directly to a connected keyboard.

[日本語の README](README.md)

## Features

- 📝 **Readable YAML**: Layers, macros, tap dances, and combos live in separate files, and you can write `#` comments
- 🔤 **Aliases**: Write readable names such as `KC_TAB` → `Tab`, `KC_TRNS` → `Trans`, `LSFT(KC_1)` → `!`
- ⌨️ **Modifier expressions**: VS Code-style notation such as `Cmd + Q` and `Ctrl + Shift + F`
- 🏷️ **Name-based references**: Refer to macros and tap dances by name, e.g. `Macro('Bracket Pair')`, `TapDance('Tab Escape')`
- 🔄 **Bidirectional conversion**: `layout.vil` ⇔ YAML. decompile → compile reproduces the original 16-bit values
- ✅ **Validation**: Before compiling, the YAML structure, keycodes, references, and limits are all checked, and every problem is reported as "file: location: message"
- 🔌 **Direct keyboard updates**: Write only the differences from the CLI or an MCP server, without Vial Web ([details](#direct-keyboard-updates-no-vial-web))

## Installation

You need Ruby (3.2 or later, since the code uses `Data.define`; CI uses 4.0) and Bundler.

```bash
git clone https://github.com/guccyon/cornix-layout.git
cd cornix-layout
bundle install
```

Put `bin/cornix` on your PATH or run `ruby bin/cornix <command>`. Below it is written as `cornix`.

```bash
cornix help             # list of commands
cornix help decompile   # usage of a command
```

Messages printed by the tool are in Japanese.

## Usage

### Typical Workflows

<details>
<summary><b>Use Case 1: Turn a layout.vil exported from Vial into YAML</b></summary>

```bash
# 1. Export layout.vil from Vial with "File > Export Layout" (e.g. ~/Downloads/layout.vil)

# 2. decompile (without an argument it reads tmp/layout.vil)
cornix decompile ~/Downloads/layout.vil

# 3. Review and edit the generated configuration
ls config/
vim config/layers/0_layer.yaml

# 4. compile (validates first, then writes layout.vil)
cornix compile

# 5. Load layout.vil in Vial with "File > Import Layout",
#    or write it directly to the keyboard with cornix device apply
```

- decompile stops if `config/` already contains a configuration (overwrite protection)

</details>

<details>
<summary><b>Use Case 2: Edit an existing configuration and compile it</b></summary>

```bash
vim config/layers/1_symbol.yaml
cornix validate          # optional (compile validates automatically)
cornix compile
git diff layout.vil      # review the change (optional)
```

- If validation fails, compile stops and does not write layout.vil
- Managing the configuration with git is recommended

</details>

<details>
<summary><b>Use Case 3: File names suggested by Claude (cornix rename)</b></summary>

```bash
ls config/macros/
# 00_macro.yaml, 01_macro.yaml, ... (default names written by decompile)

cornix rename
# Claude reads the files and suggests names → choose Y/n/e(dit) for each
# → rename them all at once (automatic backup, reference rewriting, check that the compiled result is unchanged)

ls config/macros/
# 00_bracket_pair.yaml, 01_end_of_line.yaml, ...
```

- Requires the Claude Code CLI (`claude` command)
- On failure, everything is restored from the backup automatically

</details>

### Generate Configuration Files from an Existing layout.vil

```bash
cornix decompile                       # reads tmp/layout.vil
cornix decompile ~/Downloads/layout.vil
```

**Overwrite protection**: If `config/layers/` or `config/macros/` contains files, decompile exits without doing anything.

```
⚠️  Error: config/ directory already contains configuration files.
```

Move the existing configuration aside, or delete it with `cornix cleanup`, then run decompile again.

```bash
mv config config.backup
cornix decompile ~/Downloads/layout.vil
```

A successful decompile creates `config/.decompile.lock` (the source file and its checksum).

**cleanup command**:

```bash
cornix cleanup      # delete config/ and layout.vil (stops if the lock file exists)
cornix cleanup -f   # delete even if the lock file exists, after a y/N confirmation
```

It deletes `config/` and `layout.vil` in the project root (the repository containing `bin/cornix`), regardless of the directory you run it from.

#### Generated Files

```
config/
├── .decompile.lock            # decompile record (protects against cleanup)
├── metadata.yaml              # keyboard information (version / uid of layout.vil, etc.)
├── position_map.yaml          # key names ⇔ physical positions
├── settings/
│   └── qmk_settings.yaml      # QMK Settings (tapping_term, etc.)
├── layers/
│   ├── 0_layer.yaml           # layer 0
│   └── ...                    # layers 1-9
├── macros/
│   ├── 00_macro.yaml          # macro 0
│   └── ...
├── tap_dance/
│   ├── 00_tap_dance.yaml      # tap dance 0
│   └── ...
└── combos/
    ├── 00_combo.yaml          # combo 0
    └── ...
```

**File naming** (names written by decompile):

- Layers: `{index}_{name}.yaml` (e.g. `0_layer.yaml`, `1_symbol.yaml`)
- Macros / tap dances / combos: `{2-digit index}_{name}.yaml` (e.g. `00_macro.yaml`, `03_end_of_line.yaml`)
- `{name}` is the `name` lowercased with only letters, digits and `_`. For default names (`Layer 3`, `Macro 2`, `TapDance 4`, `Combo 1`) it is `layer` / `macro` / `tap_dance` / `combo`

Both `.yaml` and `.yml` are read. You can rename files freely. The index comes from the `index` field in the YAML; for layers only, the leading number of the file name must match `index`.

What decompile writes:

- Keycodes as aliases (`Tab`, `Trans`, `!`, ...); modified keys without an alias as modifier expressions (`Shift + Command + Enter`)
- Macro and tap dance assignments as name-based references (`Macro('Macro 7')`, `TapDance('TapDance 4')`)
- QMK Settings by name (`keyboard.tapping_term`, ...)

**Notes**:
- The keycode table (`data/keycodes.yaml`) and the alias table (`data/aliases.yaml`) belong to the tool and are not generated into `config/`
- `position_map.yaml` is copied into `config/` from the template (`lib/cornix/position_map.yaml`) and you can change its symbol names

### Naming Configuration Files (cornix rename)

`cornix rename` asks Claude to read your macros, tap dances, combos, and layers and suggest meaningful names and file names.

```bash
cornix rename
```

**Flow**:

1. **Check the configuration**: `config/` is validated. If there are problems, it asks you to fix them first and exits
2. **Suggestions from Claude**: Files with default names (`Macro N`, `TapDance N`, `Combo N`, `Layer N`) are passed to the Claude CLI and the suggestions are received in `tmp/rename_plans.json`
   - Macros: infer the purpose from the key sequence (e.g. `[`, `]`, `Left` → "Bracket Pair")
   - Tap dances: infer from tap / hold / double tap actions
   - Combos: infer from triggers and output
   - Layers: infer from the description and assignments
3. **Review**: For each suggestion choose `Y` (accept) / `n` (skip) / `e` (edit file name, name and description)
4. **Rename**: Back up to `config.backup_<timestamp>/`, change the file names and `name` / `description`,
   and rewrite name-based references `Macro('old name')` / `TapDance('old name')` in every YAML file under `config/` to the new name (this is a text substitution, so references inside combo outputs, encoders and function arguments are updated too)
5. **Verify**: Compile the configuration before and after the change and compare the results (16-bit values); if they differ, restore from the backup
6. **Clean up**: Delete temporary files and ask whether to delete the backups

**Example**:

```
──────────────────────────────────────────────────────────────────────
1. MACRO: 00_macro.yaml

  Current:  00_macro.yaml
  Proposed: 00_bracket_pair.yaml

  Name:        Bracket Pair
  Description: Insert bracket pair [] with cursor positioning

  Reasoning:   Key sequence inserts left bracket, right bracket, then moves cursor left
  Confidence:  high

  Apply this rename? [Y/n/e(dit)]: y
  ✓ Added to rename queue
```

**Safety**:
- Index prefixes (`00_`, `0_`, ...) cannot be changed (attempting to do so is an error)
- Renames are applied as a batch; if any one fails, everything is rolled back
- Index-based references (`Macro(3)`, `M3`, `TD(2)`) do not depend on names and are left unchanged

**Running without Claude** (`bin/rename_file`):

```bash
# One file (--dry-run only checks)
ruby bin/rename_file \
  --old-path config/macros/03_macro.yaml \
  --new-basename 03_end_of_line.yaml \
  --name "End of Line" \
  --description "Jump to end of line" \
  --dry-run

# A batch from a JSON plan (delete the backup on success)
ruby bin/rename_file --batch tmp/rename_plans.json --cleanup-backup
```

Plan file format:

```json
[
  {
    "old_path": "config/macros/03_macro.yaml",
    "new_basename": "03_end_of_line.yaml",
    "content_updates": {
      "name": "End of Line",
      "description": "Jump to end of line with Cmd+Right"
    }
  }
]
```

The result is printed as JSON, with exit code 1 on failure. If the Claude CLI is not found or no JSON can be extracted from its output, `cornix rename` also asks you to write a plan file in this format by hand.

### Editing Configuration Files

Layer file (e.g. `config/layers/1_symbol.yaml`):

```yaml
name: Symbol
description: Symbol layer
index: 1
mapping:
  left_hand:
    row0:
      tab: Escape
      Q: "!"                       # LSFT(KC_1)
      W: "@"
    row1:
      caps: Trans                  # use the key from the layer below
      A: Macro('Bracket Pair')     # macro referenced by name
    thumb_keys:
      middle: TapDance('Tab Escape')
  right_hand:
    row0:
      Y: Cmd + Space               # modifier expression
  encoders:
    left:
      ccw: VolumeDown
      cw: VolumeUp
```

- The structure under `mapping` follows `position_map.yaml` (`row0`-`row3` and `thumb_keys` of `left_hand` / `right_hand`, and `left` / `right` of `encoders`)
- Keys you don't write are unassigned (`-1` in layout.vil). Write `Trans` to use the key from the layer below
- Encoder actions you don't write become `NoKey`

#### Notes

Wherever a key is assigned (layer keys and encoder actions, tap dance actions, and a combo's `output_key`)
you can attach a note by writing a `key` / `note` mapping.

```yaml
mapping:
  left_hand:
    row0:
      tab:                         # with a note
        key: TapDance('Tab Escape')
        note: Tab on tap, Escape on hold
      Q: "!"                       # without a note (just the key)
  encoders:
    left:
      push: { key: Mute, note: Mute }
```

- A `note` is a memo of what the assignment is for. It is never written to layout.vil or the keyboard; it only lives in the configuration files.
  Adding or changing notes does not change the compiled result
- `note` is optional, and an empty string means no note. Keys other than `key` and `note` are a validation error
- decompile writes no notes because layout.vil has none (when carrying over existing configuration, only notes at places whose keycode is unchanged are kept)

Macro file (e.g. `config/macros/00_bracket_pair.yaml`):

```yaml
name: Bracket Pair
description: "Type [] and move the cursor inside"
index: 0
sequence:
  - action: tap
    keys: ["[", "]", Left]
```

### Referring to Macros and Tap Dances

In key assignments (layer keys and encoders, tap dance actions, combo triggers and output) macros and tap dances can be referenced in three ways.

| Form | Macro | Tap dance | Description |
|---|---|---|---|
| Name (recommended) | `Macro('Bracket Pair')` | `TapDance('Tab Escape')` | Refers to the file's `name`; rewritten automatically by `cornix rename` |
| Index | `Macro(0)` | `TapDance(2)` | Refers to `index` |
| QMK | `M0` | `TD(2)` | The traditional notation |

- All forms produce the same layout.vil. decompile always writes the name form
- An unknown name, or an index with no macro / tap dance defined, is a validation error
- Wrap names containing `'` in `"..."` (`Macro("Rock'n Roll")`)
- `Combo(...)` cannot be assigned to a key in layout.vil and is not supported (validation error)
- Name-based references cannot be used inside macros (`keys` of `sequence`)

### Converting to layout.vil

```bash
cornix compile
```

compile validates first; if there are problems it exits without writing layout.vil (exit code 1). Use `cornix validate` to only validate. Load the generated `layout.vil` in Vial, or write it directly with `cornix device apply` (next section).

Errors such as a wrong command or an unreadable file are printed to standard error as `エラー: …` (Japanese for "Error:") and the command exits with code 1.

## Direct Keyboard Updates (No Vial Web)

You can apply `layout.vil` directly to a Cornix connected over Bluetooth / USB using the Vial protocol (macOS only. On first use a small HID bridge, `tmp/cornix-hid`, is built with `swiftc` from the Xcode Command Line Tools).

```bash
cornix device info              # info about the connected keyboard (layer count, lock state, ...)
cornix device read -o now.vil   # save the keyboard's current state in layout.vil format
cornix device backup            # save a timestamped copy under tmp/device_backups/
cornix device diff              # show differences between layout.vil and the keyboard (no writes)
cornix device apply             # show differences and write after confirmation (--yes skips it)
cornix device restore           # restore the last backup (the state before the last apply)
```

`apply` automatically takes a backup before writing, writes only the changed keys, encoders, tap dances, combos, macros, and settings, then reads them back to verify.

To undo, run `cornix device restore`. It shows the differences from the latest backup and writes after confirmation. To restore an older backup, pass the file, e.g. `cornix device restore tmp/device_backups/<timestamp>.vil`. `restore` also backs up the current state before writing, so running `restore` again returns to the state before the restore.

### When the Keyboard Is Not Connected

Every `cornix device` command and every MCP tool first looks for the keyboard and connects to it. If it can't be found, nothing is written and the command fails (the CLI prints the error to standard error and exits with code 1; MCP returns an error response).

```
エラー: Cornix が見つかりません。Mac と Bluetooth（または USB）で接続されているか、スリープしていないか、別の機器に接続先が切り替わっていないかを確認してください
```

(The message says: Cornix not found. Check that it is connected to the Mac via Bluetooth (or USB), is not asleep, and has not switched to another device.)

- **Bluetooth disconnected / keyboard powered off**: You get the error above. Press a key once to wake the keyboard, or check the connection to the Mac, and try again.
- **Keyboard switched to another device (BT1 / BT2, etc.)**: The Mac can't see it, so you get the same error. Switch to the channel connected to the Mac.
- **Connection lost while reading or writing**: If there is no response within 1 second, it aborts with a "no response from the keyboard" error. If it was writing, it shows how many entries were written and the path of the pre-apply backup; reconnect and run `cornix device apply` again, or go back with `cornix device restore` (both write only the differences).

### MCP Server

`cornix mcp` starts an MCP server (stdio). AI agents can then do things like "read the keyboard's current settings" or "apply this layout.vil".

#### Setup

- **Claude Code**: It is already registered as `cornix-device` in `.mcp.json` at the repository root. Open Claude Code in this directory and approve the MCP server when prompted the first time.
- **Other clients** (Claude Desktop, etc.): Register it with an absolute path as below. If `ruby` can't be found (mise / rbenv, etc.), put the absolute path to Ruby in `command`.

```json
{
  "mcpServers": {
    "cornix-device": {
      "command": "ruby",
      "args": ["/path/to/cornix-layout/bin/cornix", "mcp"]
    }
  }
}
```

`cornix mcp` reads and writes UTF-8 even if `LANG` is not set, and escapes non-ASCII characters in response JSON as `\uXXXX`, so responses are readable regardless of the client's locale.

#### Tools

| Tool | Description |
|---|---|
| `keyboard_info` | Keyboard information (read-only) |
| `read_keymap` | Return / save the current state in layout.vil format (read-only) |
| `backup` / `list_backups` | Save and list backups |
| `apply_layout` | Dry run by default: returns the differences and a `confirm_token`. Writes only with `dry_run: false` and the `confirm_token` |
| `restore_backup` | Restore the latest backup (or the one given in `backup_path`). Dry run and `confirm_token` work like `apply_layout` |

If the keyboard is not connected, every tool returns an error response and writes nothing.

#### Apply Flow

1. Generate `layout.vil` with `cornix compile`
2. Call `apply_layout` (dry run) to get the differences and a `confirm_token`, and review them
3. If you agree, call `apply_layout` with `dry_run: false` and the `confirm_token`. It backs up, writes only the differences, and verifies by reading back
4. To undo, call `restore_backup` the same way: dry run, then with the `confirm_token` (choose an older backup with `list_backups` and pass it as `backup_path`)

If the differences changed after the dry run (the keyboard or the file was modified), the token doesn't match and the write is refused.

#### About Unlocking for Macro Changes

Vial (Web / GUI) asks you to hold two specific keys ("unlock") when saving macros or assigning `QK_BOOT`. This is behavior of the Vial app; the Cornix firmware (RMK 0.8 series) does not check the lock state when writing macros. So no unlock is needed with `cornix device` / MCP (boot keycodes such as `QK_BOOT` can't be written at all).

### Safety

The Cornix firmware is RMK 0.8 series and, unlike vial-qmk, has almost no locks or range checks (bootloader jump and EEPROM reset run without a lock, and out-of-range writes make the firmware panic). Therefore:

- The HID bridge (`ext/cornix_hid/main.swift`) only sends commands on an allowlist. Bootloader jump, EEPROM reset, full erase, unlock, and bulk keymap write (buggy in RMK 0.8) can't be sent (check with `tmp/cornix-hid --self-test`).
- Keys are written one at a time, like Vial GUI does, and layer / row / col, macro offsets, and every entry index are range-checked before sending.
- Boot keycodes such as `QK_BOOT` (`data/dangerous_keycodes.yaml`) are never written.

## Validating Configuration Files

```bash
cornix validate
```

```
# Success
✓ All validations passed

# Failure (exit code 1)
✗ Validation failed:
  Error: layers/1_symbol.yaml: mapping.left_hand.row0.tab: キーコード「Spce」を解釈できません: 「Spce」は不明なキーコードです
  Error: layers/1_symbol.yaml: mapping.left_hand.row1.capz: position_map の left_hand.row1 にないキーです（使えるキー: caps, A, S, D, F, G）
  Error: macros/01_macro.yaml: name: マクロの名前が重複しています: Bracket Pair
```

(Unknown keycode "Spce"; key not in position_map's left_hand.row1; duplicate macro name.)

All problems are collected rather than stopping at the first one, and each is shown as "file: key location: message". `cornix compile` runs the same validation first. If there are only warnings (`⚠  Warning: …`), compile continues.

Validation has two stages.

<details>
<summary><b>1. File structure (while loading)</b></summary>

- **YAML**: Syntax errors, duplicate keys, and YAML aliases (`&` / `*`) are errors. Having both `.yaml` and `.yml` with the same name (for `metadata.yaml` etc.) is an error
- **Fields**: Required fields exist (`name` / `index` / `mapping` for layers, etc.), there are no unknown fields, and types are correct.
  YAML pitfalls, such as an unquoted `1` becoming an integer or `yes` / `no` / `on` / `off` becoming booleans, are reported with how to fix them
- **metadata.yaml**: `keyboard` and `version` are required; `uid` etc. must be non-negative integers
- **position_map.yaml**: Number of keys in each group, symbol format, duplicates within a group
- **Key names**: Each layer key exists in that group of `position_map.yaml`
- **Keycodes**: Every assignment can be interpreted (aliases, QMK names, function forms, modifier expressions, references, including function arguments)
- **Indexes**: Ranges of layers (0-9) and macro / tap dance / combo indexes; a layer's file name number matches its `index`
- **Macros**: `action` is `tap` / `down` / `up` / `delay` / `text` (`beep` is not supported)
- **QMK Settings**: Setting names and value types / widths

</details>

<details>
<summary><b>2. Consistency of the whole configuration</b></summary>

- **Limits**: 10 layers, 32 macros, 32 tap dances, 32 combos, 4 trigger keys per combo
- **Duplicates**: Indexes of layers / macros / tap dances / combos; names of macros / tap dances / combos
- **Reference targets**: The targets of `Macro(...)` / `M3` / `TapDance(...)` / `TD(2)` are defined
- **Layer numbers**: Layer numbers in `MO(n)` / `LT(n, ...)` etc. don't exceed the layer count (error) and point to defined layers (warning)
- **Missing layers**: Gaps in layer numbers (warning)

</details>

## File Formats

### Layer Files

See [Editing Configuration Files](#editing-configuration-files). The file name is `{index}_{name}.yaml`, and the leading number must equal `index`.

To change a layer number, change both the file name and `index`, and update `MO(2)`, `LT2(...)` etc. in other files by hand.

### Macro Files

```yaml
name: Curly Bracket Pair
description: "Type {} and move the cursor inside"
index: 1
sequence:
  - action: down
    keys: LShift
  - action: tap
    keys: ["[", "]"]
  - action: up
    keys: LShift
  - action: tap
    keys: Left
```

### Tap Dance Files

```yaml
name: Tab Escape
description: Tab on tap, Escape on hold
index: 0
actions:
  on_tap: Tab
  on_hold: Escape
  on_double_tap: NoKey
  on_tap_hold: NoKey
tapping_term: 200        # milliseconds (250 if omitted)
```

Omitted actions are `NoKey`.

### Combo Files

```yaml
name: Left Click
description: Left + Down for left click
index: 6
trigger_keys:
  - Left
  - Down
output_key: MouseButton1
```

Like layers, `trigger_keys` (up to 4 keys) and `output_key` accept both aliases (`Left`, `MouseButton1`) and QMK names (`KC_LEFT`, `KC_BTN1`). `output_key` can also be a reference such as `Macro('name')`.

`enabled` in macro / tap dance / combo files is ignored (writing it is not an error).

### QMK Settings

```yaml
# config/settings/qmk_settings.yaml
keyboard:
  oneshot_timeout: 1000
  tapping_term: 180
  tap_code_delay: 20
  tap_hold_caps_delay: 20
  permissive_hold: false
  hold_on_other_key_press: true
  chordal_hold: true
  flow_tap: 120
vial:
  combo_timing_window: 50
```

Available names and widths are in `data/qmk_settings.yaml`. The QSID-number form written by older decompiles (`'7': 180`) is also read.

## Modifier Expressions (VS Code Style)

Writing `Cmd + Q` produces a keycode with modifiers.

```yaml
Q: Cmd + Q               # LGUI(KC_Q)
W: Shift + W             # LSFT(KC_W)
E: Ctrl + C              # LCTL(KC_C)
R: Alt + Tab             # LALT(KC_TAB)
T: Shift + Cmd + Q       # SGUI(KC_Q)
Y: Ctrl + Shift + F      # C_S(KC_F)
U: Ctrl + Shift + Alt + Cmd + Y   # HYPR(KC_Y)
```

- Modifier order and spaces around `+` don't matter (`Cmd + Shift + W` = `Shift+Cmd+W`)
- The key can be an alias or a QMK name (`Cmd + Space`, `Alt + KC_ESCAPE`, `Cmd + "+"`)
- Modifier combinations are written to layout.vil in a form Vial can read: combinations with a Vial name use it (`C_S`, `SGUI`, `LCA`, `LSA`, `MEH`, `LCG`, `LAG`, `LCAG`, `HYPR`, `RCG`, ...), and combinations without one (`Ctrl + Shift + Cmd`, ...) are written as 16-bit values (`0x0B17`, ...)
- Right-side modifiers are written as `RShift` / `RCtrl` / `RAlt` / `RCmd` etc. **Mixing left and right modifiers is an error** (e.g. `Shift + RCmd + A`, because a QMK value can't represent it)
- Only basic keys can be modified (`Cmd + LT(1, Space)` is an error)

### Modifier Names

| Notation | Side | Modifier |
|---|---|---|
| `Shift`, `LShift` | left | Shift |
| `Ctrl`, `LCtrl`, `Control`, `LControl` | left | Ctrl |
| `Alt`, `LAlt`, `Option`, `LOption` | left | Alt / Option |
| `Cmd`, `LCmd`, `Command`, `LCommand`, `Win`, `LWin`, `Gui`, `LGui` | left | GUI / Command |
| `RShift` | right | Shift |
| `RCtrl`, `RControl` | right | Ctrl |
| `RAlt`, `ROption` | right | Alt / Option |
| `RCmd`, `RCommand`, `RWin`, `RGui` | right | GUI / Command |

### Function Form

QMK function forms can be written as they are.

```yaml
Q: LGUI(KC_Q)
W: LSFT(1)               # arguments may be aliases (LSFT(KC_1))
E: LCS(KC_F)             # same as C_S(KC_F)
R: LCTL_T(A)             # Ctrl on hold, A on tap
T: LT(1, Space)          # can also be written LT1(Space)
```

### How decompile Writes Them

decompile writes modified keys in this order of preference:

1. An alias if one exists (`LSFT(KC_1)` → `!`, `LSFT(KC_9)` → `(`)
2. Otherwise a modifier expression (in the order `Ctrl, Option, Shift, Command`; right side `RCtrl, ROption, RShift, RCommand`)
   - `LGUI(KC_Q)` → `Command + Q`, `HYPR(KC_LEFT)` → `Ctrl + Option + Shift + Command + Left`

So a configuration written as `Cmd + Q` becomes `Command + Q` after compile → decompile (the value is the same).

## Keycode Aliases

Keycode names come from two tables. Both belong to the tool and are not generated into `config/`.

- **`data/keycodes.yaml`**: Named keycodes of Cornix (Vial protocol 6) and their 16-bit values: the name written to layout.vil (the name Vial GUI saves) and other accepted QMK names
- **`data/aliases.yaml`**: Human-readable aliases in the form `QMK name: [canonical name, aliases...]`. The first entry is the name decompile writes. Aliases and QMK names are unique across the whole table

```yaml
# data/aliases.yaml (excerpt)
special:
  KC_NO: [NoKey, None, Nop]
  KC_TRNS: [Trans, Transparent, ___]
basic:
  KC_A: [A]
  KC_ESCAPE: [Escape, Esc]
  KC_ENTER: [Enter, Return, Ent]
  KC_LGUI: [LGui, LCmd, LWin]
  KC_VOLU: [VolumeUp, VolUp]
  KC_BTN1: [MouseButton1, MouseBtn1]
quantum:
  QK_BOOT: [Reset, Boot]
modified:
  "LSFT(KC_1)": ["!", Exclaim]
  "LSFT(KC_SCOLON)": [":", Colon]
```

- Configuration files accept aliases, QMK names (`KC_TAB`, `KC_LSHIFT`), and Vial names
- Keycodes with arguments such as `MO(n)` / `LT(n, kc)` / `LSFT(kc)` / `TD(n)` / `M0` are not in the tables; they are built into values
- Values the tables can't express can be written as `0xHHHH` (decompile also writes uninterpretable values this way)

## Position Map

`position_map.yaml` maps physical key positions to symbol names. Layer files specify keys by symbol, such as `left_hand.row0.Q`.

- **Template**: `lib/cornix/position_map.yaml` (the tool's default)
- **User configuration**: `config/position_map.yaml` (created from the template by decompile; you can change the symbol names freely; compile reads this one)

```yaml
left_hand:
  row0: [tab, Q, W, E, R, T]           # 6 keys
  row1: [caps, A, S, D, F, G]          # 6 keys
  row2: [lshift, Z, X, C, V, B]        # 6 keys
  row3: [lctrl, command, option]       # 3 keys
  thumb_keys: [left, middle, right]    # 3 thumb keys
right_hand:
  row0: [Y, U, I, O, P, backspace]
  row1: [H, J, K, L, colon, enter]
  row2: [N, M, comma, dot, up, rshift]
  row3: [left, down, right]
  thumb_keys: [left, middle, right]
encoders:
  left:
    push: push
    ccw: ccw
    cw: cw
  right:
    push: push
    ccw: ccw
    cw: cw
```

- For both hands, list keys **physically from left to right** (right-hand row0 goes `Y` (leftmost) → ... → `backspace` (rightmost))
- Symbols must be unique within the same hand and group; different groups may reuse a name (e.g. `left` / `right` in right-hand `row3` and `thumb_keys`). Symbols may contain letters, digits, `_` and `-`
- Thumb keys are physically the second half of row3, but are written separately as `thumb_keys`
- Encoder push is a key in the key matrix; rotation (`ccw` / `cw`) goes to `encoder_layout` in layout.vil

```yaml
# Renaming symbols (config/position_map.yaml)
right_hand:
  row0: [y, u, i, o, p, bs]
```

## Macro Actions

```yaml
- action: tap            # tap in order
  keys: [A, B, C]
- action: tap
  keys: A                # a single key may be a string
- action: down           # press (simultaneously if several)
  keys: [LCmd, LShift]
- action: up             # release
  keys: LShift
- action: text           # type a string (ASCII only)
  content: "function ()"
- action: delay          # wait (milliseconds)
  duration: 100
```

`keys` takes keycodes (aliases, QMK names, modifier expressions). `beep` is not supported.

## Development

### Structure

The internals are layered: configuration files, layout.vil and HID bytes are all treated as outer representations, and the inside works only with typed values (the domain model).

```
Interface       CLI (bin/cornix → Interface::Cli::Main), MCP server
Application     Use cases (Compile / Decompile / Validate / Cleanup / RenameFiles / Device*) and Environment
Mapping         Keycode notations and values (KeycodeNotation / VialNotation / KeycodeCodec), Profile ⇄ DeviceImage (ProfileMapper)
Planning        Differences between DeviceImages and write plans
Domain          Profile and value objects (Keycode, Layer, Macro, TapDance, Combo, PositionMap, ...)
Image           DeviceImage (layout.vil / device state as raw 16-bit values)
Storage         config/*.yaml (ConfigRepository), layout.vil (VilFile), backups
Device          Communication with the HID bridge; reading and writing the device
```

```
compile    config/ → Profile → DeviceImage → layout.vil
decompile  layout.vil → DeviceImage → Profile → config/
device     write the difference between layout.vil → DeviceImage (target) and device → DeviceImage (current), then read back and verify
```

Principles, dependency direction and coding conventions are in [docs/architecture.md](docs/architecture.md); public methods of the main classes are in [docs/tasks.md](docs/tasks.md) (both in Japanese).

### Directory Structure

```
cornix-layout/
├── bin/
│   ├── cornix                # CLI (Interface::Cli::Main)
│   ├── diff_layouts          # compare two layout.vil files by 16-bit values
│   └── rename_file           # run renames directly (prints the result as JSON)
├── data/
│   ├── keycodes.yaml         # named keycode table (Vial protocol 6)
│   ├── aliases.yaml          # keycode aliases (QMK name: [canonical, aliases...])
│   ├── qmk_settings.yaml     # QSID, name and width of QMK Settings
│   └── dangerous_keycodes.yaml # keycodes never written to the device
├── lib/
│   ├── cornix.rb             # requires every file in layer order
│   └── cornix/
│       ├── domain/ image/ mapping/ planning/ storage/ device/ application/ interface/
│       ├── errors.rb         # Cornix::Error exceptions
│       └── position_map.yaml # position_map template
├── ext/cornix_hid/main.swift # raw HID bridge (with allowlist, built to tmp/cornix-hid)
├── spec/                     # RSpec (same layer structure as lib; see spec/README.md)
├── docs/                     # architecture.md, tasks.md
├── .mcp.json                 # MCP server registration for Claude Code
├── config/                   # configuration files (generated)
└── layout.vil                # output of compile
```

### Tests

```bash
LANG=ja_JP.UTF-8 bundle exec rspec                       # everything
LANG=ja_JP.UTF-8 bundle exec rspec spec/mapping          # one layer
LANG=ja_JP.UTF-8 bundle exec rspec spec/end_to_end_spec.rb
```

- Specs follow the same layer structure as lib (`spec/domain`, `spec/mapping`, ... `spec/interface`)
- `spec/end_to_end_spec.rb` compiles `spec/fixtures/test_config` and the author's keymap (`spec/fixtures/authors_config`), checks that the results match the stored layout.vil files by 16-bit values, and that decompile → compile reproduces them
- `spec/architecture_spec.rb` checks the dependency direction between layers
- A `FakeRmkDevice` that mimics RMK 0.8 responses replaces the real keyboard, so tests run without one

See [spec/README.md](spec/README.md) for details. GitHub Actions also runs RSpec on every push / pull request.

### Round-Trip Check

A procedure to check that decompile → compile reproduces your own layout.vil:

```bash
mv config config.backup          # move the existing configuration aside
cp ~/Downloads/layout.vil tmp/layout.vil
cornix decompile                 # tmp/layout.vil → config/
cornix compile                   # config/ → layout.vil
ruby bin/diff_layouts            # compare tmp/layout.vil and layout.vil
# Expected: === ✓ FILES ARE IDENTICAL ===
```

`bin/diff_layouts [FILE1 FILE2]` reads two layout.vil files and compares keys, encoders, macros, tap dances, combos and settings by 16-bit values. Different spellings of the same value (`KC_PGDN` and `KC_PGDOWN`, etc.) are treated as equal. If they differ, it shows where and exits with code 1.

## Troubleshooting

<details>
<summary><b>Common problems</b></summary>

### 1. decompile is blocked

```
⚠️  Error: config/ directory already contains configuration files.
```

`config/` already contains a configuration. Move it aside with `mv config config.backup` or delete it with `cornix cleanup`, then decompile again. If cleanup stops with `Protected: config/ directory has an active lock file`, use `cornix cleanup -f`.

### 2. A keycode can't be interpreted

```
Error: layers/0_base.yaml: mapping.left_hand.row0.Q: キーコード「Spce」を解釈できません: 「Spce」は不明なキーコードです
```

A typo (`Spce` → `Space`). Valid names are in `data/aliases.yaml` and `data/keycodes.yaml`.

### 3. A key that isn't in position_map

```
Error: layers/0_base.yaml: mapping.left_hand.row1.capz: position_map の left_hand.row1 にないキーです（使えるキー: caps, A, S, D, F, G）
```

Use a symbol from that group of `config/position_map.yaml`, or change `position_map.yaml`.

### 4. Duplicate indexes or names

```
Error: layers/2_layer.yaml: index: レイヤーの番号が重複しています: 2
Error: macros/01_macro.yaml: name: マクロの名前が重複しています: Bracket Pair
```

Change the `index` / `name` of one of the files.

### 5. Reference to a nonexistent macro / tap dance

```
Error: layers/0_base.yaml: mapping.left_hand.row0.Q: キーコード「Macro('Unknown')」を解釈できません: マクロ「Unknown」が見つかりません
```

Check the `name` fields in `config/macros/*.yaml` and fix the reference (`grep '^name:' config/macros/*.yaml`).

### 6. Mixed left and right modifiers

```
キーコード「Shift + RCmd + A」を解釈できません: 左右の修飾キーは混在できません（例: Shift と RCmd）
```

A QMK modified keycode can only represent one side. Use the same side for all modifiers.

### 7. The round-trip check fails

Look at the output of `ruby bin/diff_layouts` to see which layer, row or item differs. Please open an issue with the original and the generated layout.vil.

### 8. The Claude Code CLI (`claude` command) is not found

```
  ❌ Error: Claude CLI not found
```

`cornix rename` requires the Claude Code CLI. Install it from https://claude.ai/download and check with `claude --version`.

### 9. YAML syntax or type errors

Check the file named in the message. Common causes are wrong indentation, mixed tabs, and strings that need quotes (`"!"`, `"["`, `"1"`, ...). When, for example, an unquoted `1` is read as an integer, the message shows how to rewrite it.

</details>

## Tips

- **Use name-based references**: `Macro('End of Line')` is more readable than `M5`, and `cornix rename` rewrites it automatically
- **Use modifier expressions**: `Cmd + Q` and `Ctrl + Shift + F` read better than `LGUI(KC_Q)` and `C_S(KC_F)`, and decompile writes modifier expressions too
- **Use git**: Managing `config/` with git makes reviewing and reverting changes easy
- **Keep index prefixes**: Keep prefixes like `03_` when renaming files (for layers, the file name number must match `index`)
- **Change a little, then check**: Running `cornix compile` (with automatic validation) after each change pinpoints problems quickly

## Contributing

Pull requests are welcome!

1. Fork this repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Make sure `LANG=ja_JP.UTF-8 bundle exec rspec` passes
4. Commit and push
5. Open a pull request

## License

MIT License

## References

- [Vial Documentation](https://get.vial.today/)
- [QMK Firmware Documentation](https://docs.qmk.fm/)
- [QMK Keycodes](https://docs.qmk.fm/keycodes_basic)

---

## Appendix

### Main Keycodes

See `data/aliases.yaml` (aliases) and `data/keycodes.yaml` (QMK / Vial names) for the complete list.

<details>
<summary><b>Main keycode categories</b></summary>

**Basic keys**:
- Letters `A`-`Z`, digits `"0"`-`"9"`, function keys `F1`-`F24`
- Navigation: `Up`, `Down`, `Left`, `Right`, `Home`, `End`, `PageUp`, `PageDown`
- Editing: `Enter`, `Escape`, `Backspace`, `Tab`, `Space`, `Delete`
- Modifiers: `LShift`, `RShift`, `LCtrl`, `RCtrl`, `LAlt`, `RAlt`, `LGui` (`LCmd`), `RGui` (`RCmd`)
- Symbols: `"-"`, `"="`, `"["`, `"]"`, `"\\"`, `";"`, `"'"`, `` "`" ``, `","`, `"."`, `"/"`
- Shifted symbols: `"!"`, `"@"`, `"#"`, `"("`, `")"`, `":"`, ...

**Layer switching**:
- `MO(n)` (while held), `TG(n)` (toggle), `TO(n)` (switch), `TT(n)` (tap toggle), `DF(n)` (default), `OSL(n)` (one shot)
- `LT(n, key)` / `LTn(key)`: layer on hold, key on tap
- The argument is a number (`MO(KC_3)` is an error)

**Modifiers**:
- Mod-Tap: `LCTL_T(key)`, `LSFT_T(key)`, `LALT_T(key)`, `LGUI_T(key)`, `MEH_T(key)`, ..., `MT(MOD_LCTL|MOD_LSFT, key)`
- One Shot: `OSM(MOD_LSFT)`
- Modified keys: `LSFT(key)`, `C(key)`, `S(key)`, `A(key)`, `G(key)` and combinations (`C_S`, `SGUI`, `MEH`, `HYPR`, ...)
- `LM(n, MOD_LCTL)`

**Media / mouse**:
- `VolumeUp`, `VolumeDown`, `Mute`, `MediaPlayPause`, ...
- `MouseUp`, `MouseDown`, `MouseLeft`, `MouseRight`, `MouseButton1`..., `MouseWheelUp`, ...

**Special keys**:
- `Trans` (`Transparent`, `___`): use the layer below
- `NoKey`: disabled
- `Reset` (`QK_BOOT`): can be written in configuration files, but `cornix device` never writes it

</details>

### Modifier Functions and Modifier Expressions

| Function | Modifier expression | Notation in layout.vil |
|---|---|---|
| `LCTL` / `C` | `Ctrl + key` | `LCTL(...)` |
| `LSFT` / `S` | `Shift + key` | `LSFT(...)` |
| `LALT` / `A` | `Alt + key` | `LALT(...)` |
| `LGUI` / `G` | `Cmd + key` | `LGUI(...)` |
| `LCS` / `C_S` | `Ctrl + Shift + key` | `C_S(...)` |
| `LCA` | `Ctrl + Alt + key` | `LCA(...)` |
| `LCG` | `Ctrl + Cmd + key` | `LCG(...)` |
| `LSA` | `Shift + Alt + key` | `LSA(...)` |
| `LSG` / `SGUI` | `Shift + Cmd + key` | `SGUI(...)` |
| `LAG` | `Alt + Cmd + key` | `LAG(...)` |
| `MEH` | `Ctrl + Shift + Alt + key` | `MEH(...)` |
| `LCSG` | `Ctrl + Shift + Cmd + key` | 16-bit value (`0x0Bxx`) |
| `LCAG` | `Ctrl + Alt + Cmd + key` | `LCAG(...)` |
| `LSAG` | `Shift + Alt + Cmd + key` | 16-bit value (`0x0Exx`) |
| `HYPR` | `Ctrl + Shift + Alt + Cmd + key` | `HYPR(...)` |

The right-side versions (`RCTL`, `RSFT`, `RALT`, `RGUI`, `RCS`, `RCA`, `RCG`, `RSA`, `RSG`, `RAG`, `RCSG`, `RCAG`, `RSAG`) work the same way. Combinations without a Vial name are written to layout.vil as 16-bit values.

### Sample Configurations

Switch branches to use sample configurations.

<details>
<summary><b>Available sample configurations</b></summary>

#### 1. Official default keymap (recommended)

```bash
git checkout cornix-default-keymap
ls config/
cornix compile
```

The standard Cornix layout. Recommended for beginners.

#### 2. The author's keymap

```bash
git checkout authors-keymap
ls config/
cornix compile
```

A keymap in daily use, with examples of name-based references, modifier expressions, combos, and more.

#### 3. From your own layout.vil

```bash
git checkout main
cornix decompile ~/Downloads/my_layout.vil
vim config/layers/0_layer.yaml
cornix compile
```

#### Switching branches

```bash
mv config config.my_backup             # move the current configuration aside
git checkout cornix-default-keymap
# ...
git checkout main
mv config.my_backup config             # put it back
```

</details>

Contributions of sample configurations are welcome (share them on a new branch and open a pull request).

---

Made with ❤️ for the Cornix keyboard community
