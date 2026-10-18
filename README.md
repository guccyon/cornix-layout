# Cornix Keyboard Layout Manager

English | [日本語](README.ja.md)

A tool that manages the keymap of the Cornix keyboard (layers, encoders, macros, tap dances, combos and QMK Settings)
as human-readable YAML files, converts them to and from Vial's `layout.vil`, and writes them directly to a connected keyboard.

- Read the settings from the keyboard into YAML (`pull`)
- Edit the YAML and review the differences from the keyboard (`status`)
- Write only the differences to the keyboard (`apply`). A backup is always taken before writing, and the keyboard is read back afterwards to verify
- If you don't like the result, restore from a backup (`restore`)
- If you use Vial, build a `layout.vil` from the YAML (`compile`), or turn a `layout.vil` exported from Vial into YAML (`decompile`)

Because the settings are plain files, you can keep them in Git to track their history or switch between setups.
It also runs as an MCP server, so AI assistants such as Claude can read and change the keyboard's settings.
Some of the command output, including many error messages, is currently in Japanese.

The YAML supports:

- **Aliases**: `KC_TAB` → `Tab`, `KC_TRNS` → `Trans`, `LSFT(KC_1)` → `!`
- **Modifier expressions**: VS Code-style notation such as `Cmd + Q` and `Ctrl + Shift + F`
- **References by name**: `Macro('Bracket Pair')`, `TapDance('Tab Escape')`
- **Named shortcuts**: define `Previous Tab: Command + Shift + [` in `shortcuts.yaml` and use `Shortcut('Previous Tab')` anywhere
- **Notes**: record what an assignment is for in the settings file, as in `{ key: Mute, note: Mute }`
- **Comments**: write anything after `#`

decompile → compile reproduces the original 16-bit values, so you can bring over a setup made in Vial as it is.

> **This is an unofficial tool.** It is not affiliated with the makers of the Cornix.
> Writing directly to the keyboard is based on testing with real hardware and the public sources of Vial and RMK. Use it at your own risk.

## Contents

- [Supported environment](#supported-environment)
- [Requirements](#requirements)
- [Getting started](#getting-started)
- [Commands](#commands)
- [Writing the settings files](#writing-the-settings-files)
- [Writing keys](#writing-keys)
- [YAML pitfalls](#yaml-pitfalls)
- [Validating the settings](#validating-the-settings)
- [Naming the settings files (`rename`)](#naming-the-settings-files-rename)
- [Converting to and from Vial's layout.vil](#converting-to-and-from-vials-layoutvil)
- [Backups and restoring](#backups-and-restoring)
- [Where the settings live and how to use the repository](#where-the-settings-live-and-how-to-use-the-repository)
- [Using it as an MCP server](#using-it-as-an-mcp-server)
- [Safety mechanisms](#safety-mechanisms)
- [Troubleshooting](#troubleshooting)
- [For developers](#for-developers)

## Supported environment

| Item | Support |
|---|---|
| Keyboard | Cornix |
| Firmware | RMK 0.8 series (Vial protocol 6) |
| OS | Talking to the keyboard (`pull` / `status` / `apply` / `restore` / `device` / `mcp`): macOS only. `compile` / `decompile` / `validate` and the like: anywhere Ruby runs |
| Connection | Bluetooth or USB |

## Requirements

- **Ruby 3.2 or later** (the code uses `Data.define`; CI uses 4.0) and **Bundler**
- **Xcode Command Line Tools** (for talking to the keyboard; install with `xcode-select --install` if `swiftc` is missing)
  - The tool talks to the keyboard through a small Swift program (`ext/cornix_hid/main.swift`). It is built automatically on first use and placed in `tmp/cornix-hid`
- **Claude Code CLI** (the `claude` command; only for `cornix rename`)

## Getting started

### 1. Get the tool

```bash
git clone https://github.com/guccyon/cornix-layout.git   # or clone your own fork
cd cornix-layout
bundle install
```

If you want to keep your settings on GitHub and use them on several machines, forking is recommended
(see [Where the settings live and how to use the repository](#where-the-settings-live-and-how-to-use-the-repository)).

To use it as a `cornix` command, put a symlink to `bin/cornix` in a directory on your PATH (you can also run `ruby bin/cornix <command>`).

```bash
mkdir -p ~/.local/bin && ln -s "$PWD/bin/cornix" ~/.local/bin/cornix   # add ~/.local/bin to PATH if it is not there
cornix help             # list of commands
cornix help init        # usage of a command
```

The examples below write it as `cornix`.

### 2. Create the settings (`init`)

Connect the Cornix to your Mac over Bluetooth (or USB), then run:

```bash
cornix init                                # write the keyboard's current settings into profiles/default/
cornix init --from ~/Downloads/layout.vil  # use a layout.vil exported from Vial instead of the keyboard
cornix init --no-pull                      # create only an empty settings directory
```

This creates:

- `profiles/default/` … your settings files. If the keyboard is connected, its current settings are written out as YAML
- `.cornix.yml` … which settings to use (`profile: default`). Later commands read this and use `profiles/default/`

Also note:

- If the settings directory already has files in it, `init` stops without overwriting them
- If the keyboard could not be reached, only an empty settings directory is created; connect the keyboard and run `cornix pull`
- With a name, as in `cornix init --profile work`, it creates `profiles/work/` instead. To switch between several setups,
  or to keep the settings in another repository, see [Where the settings live and how to use the repository](#where-the-settings-live-and-how-to-use-the-repository)
- Settings kept in this repository's `config/` as before keep working as long as there is no `.cornix.yml`
  (see [If you use the old `config/`](#if-you-use-the-old-config))

Layers and macros start with names like `Layer 0` and `Macro 0`. `cornix rename`
([Naming the settings files (`rename`)](#naming-the-settings-files-rename)) is a handy way to give them meaningful names.

### 3. Edit the settings

Edit the YAML in `profiles/default/` with your editor. See [Writing the settings files](#writing-the-settings-files) for the format.
Changing a little at a time and checking with `validate` or `status` each time makes problems easy to locate.

You can check the files for mistakes without the keyboard:

```bash
cornix validate
```

### 4. See the differences (`status`)

```bash
cornix status
```

It compiles the settings (into `tmp/profiles/default/build/layout.vil`), compares the result with the keyboard's current state, and lists the changes that would be written (it writes nothing).
It exits with 0 when there are no differences and 2 when there are.

### 5. Write (`apply`)

```bash
cornix apply           # show the differences, ask [y/N], then write
cornix apply --yes     # skip the question
```

Before writing, the keyboard's current state is backed up to `tmp/profiles/default/device_backups/`.
Only the keys, encoders, tap dances, combos, macros and settings that changed are written, and finally the keyboard is read back to check that it matches.
If validation fails, the command stops at the compile step and never touches the keyboard.

### 6. Undoing (`restore`)

```bash
cornix restore         # go back to the state before the last apply (shows the differences and asks before writing)
```

See [Backups and restoring](#backups-and-restoring) for details.

## Commands

```
cornix <command> [options]
```

| Command | Keyboard | Writes | Description |
|---|---|---|---|
| `init [DIR] [--from FILE] [--no-pull]` | Yes (no with `--from` / `--no-pull`) | No | Creates a settings directory (default `profiles/default/`) and `.cornix.yml`, and writes the settings from the keyboard (or the .vil given with `--from`). Never overwrites existing settings |
| `pull` | Yes | No | Reads the keyboard's state into `<tmp>/layout.vil` and turns it into YAML in the settings directory. Stops if there are settings already |
| `status` | Yes | No | Compiles and shows the differences from the keyboard. Exits with 2 when there are differences |
| `apply [--yes]` | Yes | Yes (after confirmation) | Compiles, asks for confirmation of the differences, then writes to the keyboard |
| `restore [BACKUP] [--yes]` | Yes | Yes (after confirmation) | Goes back to a backup (default: the state before the last apply) |
| `compile [-o FILE]` | No | No | Validates the settings and writes a .vil (default `<tmp>/build/layout.vil`) |
| `decompile [FILE]` | No | No | Turns a layout.vil into YAML in the settings directory (default `<tmp>/layout.vil`). Stops if there are settings already |
| `validate` | No | No | Validates the settings files |
| `rename` | No | No | Gives the settings files meaningful names, confirming Claude's suggestions one by one |
| `cleanup [-f]` | No | No | Deletes the settings directory and the compile output |
| `device <subcommand>` | Yes | Only `apply` / `restore` | Reads and writes the keyboard with explicit files (table below) |
| `mcp` | Yes | Depends on the tool | Starts as an MCP server (see [Using it as an MCP server](#using-it-as-an-mcp-server)) |

Subcommands of `cornix device`:

| Subcommand | Description |
|---|---|
| `device info` | Information about the connected keyboard (number of layers, lock state, ...) |
| `device read [-o FILE]` | Prints the keyboard's current state in layout.vil format |
| `device backup` | Saves the keyboard's state to `<tmp>/device_backups/` with a timestamp |
| `device diff [FILE]` | Shows the differences between a .vil and the keyboard (writes nothing; `FILE` defaults to the compile output) |
| `device apply [FILE] [--yes]` | Shows the differences and writes after confirmation (`FILE` defaults to the compile output) |
| `device restore [BACKUP] [--yes]` | Goes back to the last backup (the state before the last apply) |

`pull` runs `device read` and then `decompile`, `status` runs `compile` and then `device diff`, and `apply` runs `compile` and then `device apply`.
`restore` is the same as `device restore`.

Common options (accepted by every command, before or after the command name):

| Option | Description |
|---|---|
| `--config DIR` | Give the settings directory directly |
| `--profile NAME` | Use the settings in `profiles/NAME/` |
| `--root DIR` | Where `tmp/` and `profiles/` live (default: the directory containing `.cornix.yml`, otherwise this repository) |

Normally the `.cornix.yml` written by `cornix init` decides this, so you don't need them (see [Where the settings live and how to use the repository](#where-the-settings-live-and-how-to-use-the-repository)).

In this README, `<tmp>` is the working directory of the settings in use: `tmp/profiles/NAME/` for settings in `profiles/NAME/`,
and `tmp/` for settings in the old `config/` (`tmp/` is not tracked by Git).

Exit codes: `0` = success, `1` = error, `2` = there are differences (`status` only).
Errors such as a wrong command or an unreadable file are printed to standard error as `エラー: …` ("Error: …").

### When `pull` stops

If the settings directory already has settings (files in `layers/` or `macros/`), `pull` and `decompile` do nothing and stop, so that your edits are not overwritten.
In that case `pull` does not read the keyboard and does not change `<tmp>/layout.vil` either.

```
⚠️  Error: config/ directory already contains configuration files.
```

(The message says `config/` even when the settings directory is under `profiles/`.)

To rebuild the settings from the keyboard, move the current settings aside or delete them with `cornix cleanup -f`, then run it again (settings created by init or decompile have a `.decompile.lock`, so cleanup without `-f` stops).

```bash
mv profiles/default profiles/default.backup     # move them aside
cornix pull
```

## Writing the settings files

### File layout

A settings directory (here `profiles/default/`, as created by `cornix init`) looks like this:

```
profiles/default/
├── .decompile.lock            # record of the decompile (used to protect against cleanup)
├── metadata.yaml              # keyboard information (version / uid of the layout.vil, ...)
├── position_map.yaml          # mapping between key names and physical positions
├── settings/
│   └── qmk_settings.yaml      # QMK Settings (tapping_term, ...)
├── shortcuts.yaml             # named shortcuts (optional; decompile does not create it, you write it yourself)
├── layers/
│   ├── 0_layer.yaml           # layer 0
│   └── ...                    # layers 1–9
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

File name rules (the names decompile writes):

- Layers: `{number}_{name}.yaml` (e.g. `0_layer.yaml`, `1_symbol.yaml`)
- Macros / tap dances / combos: `{two-digit number}_{name}.yaml` (e.g. `00_macro.yaml`, `03_end_of_line.yaml`)
- `{name}` is the `name` lowercased, keeping only letters, digits and `_`. For the default names (`Layer 3`, `Macro 2`, `TapDance 4`, `Combo 1`) it is `layer` / `macro` / `tap_dance` / `combo`

Both `.yaml` and `.yml` are read. You can rename files freely. The number comes from `index` in the YAML; only for layers must the leading number of the file name match `index`.
To change a layer's number, change both the file name and `index`, and update `MO(2)`, `LT2(...)` and the like in other files by hand.

What decompile writes:

- Keycodes as aliases (`Tab`, `Trans`, `!`, ...), and keys with modifiers that have no alias as modifier expressions (`Shift + Command + Enter`)
- Macro and tap dance assignments as references by name (`Macro('Macro 7')`, `TapDance('TapDance 4')`)
- QMK Settings by name (`keyboard.tapping_term`, ...)
- The keycode table (`data/keycodes.yaml`) and the alias table (`data/aliases.yaml`) belong to the tool and are not created in the settings directory

### Layers

```yaml
# profiles/default/layers/1_symbol.yaml
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
      A: Macro('Bracket Pair')     # refer to a macro by name
    row2:                          # write groups without assignments too (empty is fine)
    row3:
    thumb_keys:
      middle: TapDance('Tab Escape')
  right_hand:
    row0:
      Y: Cmd + Space               # modifier expression
    row1:
    row2:
    row3:
    thumb_keys:
  encoders:
    left:
      ccw: VolumeDown
      cw: VolumeUp
```

- Under `mapping` the structure is the same as `position_map.yaml` (`row0`–`row3` and `thumb_keys` of `left_hand` / `right_hand`, and `left` / `right` of `encoders`)
- Each hand must list all of `row0`–`row3` and `thumb_keys` (an empty value is fine)
- Keys you leave out inside a group are unassigned (`-1` in layout.vil). To use the layer below, write `Trans`
- Encoder actions you don't write become `NoKey`

### Notes (`note`)

Wherever a key is assigned (layer keys and encoder actions, tap dance actions, and a combo's `output_key`),
you can attach a note with a mapping of `key` and `note`.

```yaml
# excerpt of a layer file
mapping:
  left_hand:
    row0:
      tab:                         # with a note
        key: TapDance('Tab Escape')
        note: Tab on tap, Escape on hold
      Q: "!"                       # without a note (the short form with only the key)
  encoders:
    left:
      push: { key: Mute, note: Mute }
```

- A `note` is a memo of what the assignment is for. It is not written to layout.vil or the keyboard; it stays only in the settings file.
  Adding or changing notes does not change the compile result
- `note` is optional, and an empty string is the same as no note. Keys other than `key` and `note` are a validation error
- `key` cannot be omitted (to leave an encoder or tap dance action as `NoKey`, leave out the whole value)
- The same form works in a tap dance's `actions` and a combo's `output_key`
- decompile does not write notes (layout.vil has no notes)

### Macros

```yaml
# profiles/default/macros/01_curly_bracket_pair.yaml
name: Curly Bracket Pair
description: "Type {} and move the cursor back inside"
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

Available actions:

```yaml
- action: tap            # tap in order
  keys: [A, B, C]
- action: tap
  keys: A                # a single key can be a string
- action: down           # press (several keys at once)
  keys: [LCmd, LShift]
- action: up             # release
  keys: LShift
- action: text           # type a string (ASCII only)
  content: "function ()"
- action: delay          # wait (milliseconds)
  duration: 100
```

`keys` takes keycodes (aliases, QMK names, modifier expressions). `beep` is not supported.

### Tap dances

```yaml
# profiles/default/tap_dance/00_tab_escape.yaml
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

### Combos

```yaml
# profiles/default/combos/06_left_click.yaml
name: Left Click
description: Left click with ← + ↓
index: 6
trigger_keys:
  - Left
  - Down
output_key: MouseButton1
```

As in layers, `trigger_keys` (up to 4 keys) and `output_key` accept both aliases (`Left`, `MouseButton1`) and QMK names (`KC_LEFT`, `KC_BTN1`). `output_key` also accepts references such as `Macro('name')`.

`enabled` in macros, tap dances and combos is ignored (writing it is not an error).

### QMK Settings

```yaml
# profiles/default/settings/qmk_settings.yaml
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

The available names and widths are in [data/qmk_settings.yaml](data/qmk_settings.yaml). The QSID number form written by older versions of decompile (`'7': 180`) is also read.

### Referring to macros and tap dances

In key assignments (layer keys and encoders, tap dance actions, combo triggers and outputs), macros and tap dances can be referred to in three ways.

| Form | Macro | Tap dance | Description |
|---|---|---|---|
| By name (recommended) | `Macro('Bracket Pair')` | `TapDance('Tab Escape')` | Refers to the file's `name`. Updated automatically by `cornix rename` |
| By number | `Macro(0)` | `TapDance(2)` | Refers to `index` |
| QMK form | `M0` | `TD(2)` | The traditional notation |

- All forms produce the same layout.vil. decompile always writes the name form
- A name that cannot be found, or a number with no macro or tap dance defined, is a validation error
- Put names containing `'` in `"..."` (`Macro("Rock'n Roll")`)
- `Combo(...)` cannot be used, because combos cannot be assigned to keys in layout.vil (validation error)
- References by name cannot be used inside macros (in `keys` of a `sequence`)

### Named shortcuts (`shortcuts.yaml`)

When you use the same shortcut in several places, or want to write what it means rather than the key combination, define it with a name in `profiles/default/shortcuts.yaml` and refer to it with `Shortcut('name')`.

```yaml
# profiles/default/shortcuts.yaml
shortcuts:
  Previous Tab: Command + Shift + [
  Next Tab: Command + Shift + ]
  Window Left Half: Ctrl + Option + Left
  Bracket Pair: Macro('Bracket Pair')    # references to macros and tap dances by name are allowed too
```

```yaml
# profiles/default/layers/0_base.yaml (excerpt)
mapping:
  left_hand:
    row0:
      Q: Shortcut('Previous Tab')
      W: Shortcut('Next Tab')
  encoders:
    left: { push: Shortcut('Window Left Half'), ccw: VolumeDown, cw: VolumeUp }
```

- `Shortcut('name')` becomes exactly the keycode it defines (layout.vil gets the same value as if you had written it directly)
- It works in layer keys and encoders, tap dance actions, and combo triggers and outputs. It also works inside function arguments (`LT1(Shortcut('name'))`, but only when the definition is a key allowed in that place; for `LT1(...)`, a basic key)
- Referring to a name that is not defined is a validation error
- Values in `shortcuts.yaml` cannot use `Shortcut(...)`. It cannot be used inside macros (in `keys` of a `sequence`) either
- `shortcuts.yaml` is optional. decompile does not create, read or change it (layout.vil has no names)
- When `cornix rename` renames a macro or tap dance, `Macro('name')` / `TapDance('name')` inside `shortcuts.yaml` are updated too

### Key positions (`position_map.yaml`)

`position_map.yaml` maps the physical positions of the keys to symbol names. Layer files refer to keys by symbol, as in `left_hand.row0.Q`.

- **Template**: `lib/cornix/position_map.yaml` (the tool's default)
- **Your settings**: `profiles/default/position_map.yaml` (decompile creates it from the template; you can rename the symbols freely; compile reads this one)

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

- For both hands, list the keys **physically from left to right** (right-hand row0 goes from `Y` (leftmost) … to `backspace` (rightmost))
- A symbol only needs to be unique within the same hand and group; different groups may reuse a name (`left` / `right` in the right hand's `row3` and `thumb_keys`, for example). Symbols may contain letters, digits, `_` and `-`
- The thumb keys are physically at the end of row3, but they are written separately as `thumb_keys`
- An encoder's push is a key in the key matrix; its rotation (`ccw` / `cw`) is written to `encoder_layout` in layout.vil

```yaml
# example of renaming symbols (profiles/default/position_map.yaml)
right_hand:
  row0: [y, u, i, o, p, bs]
```

## Writing keys

A key can be written as an alias, a QMK name, a Vial name, a modifier expression, a function form, or a reference. Names are case-sensitive.

| Kind | Examples | Description |
|---|---|---|
| Alias | `A` `Tab` `Enter` `Escape` `Space` `Left` `F5` | The available names are in [data/aliases.yaml](data/aliases.yaml) |
| QMK / Vial name | `KC_TAB` `KC_LSHIFT` `KC_BTN1` | [data/keycodes.yaml](data/keycodes.yaml) |
| Shifted symbols | `"!"` `"@"` `"("` `":"` | Put a single symbol in quotes |
| Nothing / layer below | `NoKey` / `Trans` | `Trans` is "transparent" (uses the assignment of the layer below) |
| Modifier expression | `Cmd + Q` `Ctrl + Shift + F` | [Modifier expressions](#modifier-expressions-vs-code-style) |
| Function form | `LGUI(KC_Q)` `LT(1, Space)` `LCTL_T(A)` | [Function form](#function-form) |
| Layer actions | `MO(1)` `TG(2)` `TO(0)` `LT1(Space)` | The number is the layer's `index` |
| Macro / tap dance reference | `Macro('Bracket Pair')` `TapDance(2)` `M0` `TD(2)` | [Referring to macros and tap dances](#referring-to-macros-and-tap-dances) |
| Named shortcut | `Shortcut('Previous Tab')` | [Named shortcuts](#named-shortcuts-shortcutsyaml) |
| Raw value | `0x7E00` | A value the tables cannot express (decompile also writes values it cannot interpret this way) |

### Aliases

Keycode names come from two tables. Both belong to the tool and are not created in the settings directory.

- **`data/keycodes.yaml`**: the named keycodes of the Cornix (Vial protocol 6) and their 16-bit values. The name written to layout.vil (the name the Vial GUI saves) and other accepted QMK names
- **`data/aliases.yaml`**: human-friendly aliases, in the form `QMK name: [canonical name, alias...]`. The first one is the name decompile writes. Aliases and QMK names are unique across the whole table

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

- Keycodes with arguments such as `MO(n)` / `LT(n, kc)` / `LSFT(kc)` / `TD(n)` / `M0` are not in the tables; their values are built
- Values the tables cannot express can be written as `0xHHHH`

### Modifier expressions (VS Code style)

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

- The order of the modifiers and the spaces around `+` are free (`Cmd + Shift + W` = `Shift+Cmd+W`)
- The key can be an alias or a QMK name (`Cmd + Space`, `Alt + KC_ESCAPE`, `Cmd + "+"`)
- Modifier combinations are written to layout.vil in a form Vial can read. Combinations Vial has a name for use that name (`C_S`, `SGUI`, `LCA`, `LSA`, `MEH`, `LCG`, `LAG`, `LCAG`, `HYPR`, `RCG`, ...); combinations without a name (such as `Ctrl + Shift + Cmd`) are written as 16-bit values (such as `0x0B17`)
- Right-hand modifiers are written as `RShift` / `RCtrl` / `RAlt` / `RCmd` and so on. **Mixing left and right modifiers is an error** (e.g. `Shift + RCmd + A`, because QMK values cannot express it)
- Only basic keys can be modified (`Cmd + LT(1, Space)` is an error)

Modifier names:

| Written as | Side | Modifier |
|---|---|---|
| `Shift`, `LShift` | Left | Shift |
| `Ctrl`, `LCtrl`, `Control`, `LControl` | Left | Ctrl |
| `Alt`, `LAlt`, `Option`, `LOption` | Left | Alt / Option |
| `Cmd`, `LCmd`, `Command`, `LCommand`, `Win`, `LWin`, `Gui`, `LGui` | Left | GUI / Command |
| `RShift` | Right | Shift |
| `RCtrl`, `RControl` | Right | Ctrl |
| `RAlt`, `ROption` | Right | Alt / Option |
| `RCmd`, `RCommand`, `RWin`, `RGui` | Right | GUI / Command |

### Function form

QMK's function form can be written as is.

```yaml
Q: LGUI(KC_Q)
W: LSFT(1)               # the argument may be an alias (LSFT(KC_1))
E: LCS(KC_F)             # same as C_S(KC_F)
R: LCTL_T(A)             # Ctrl when held, A when tapped
T: LT(1, Space)          # can also be written as LT1(Space)
```

Modifier functions and modifier expressions:

| Function | Modifier expression | In layout.vil |
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

The right-hand versions (`RCTL`, `RSFT`, `RALT`, `RGUI`, `RCS`, `RCA`, `RCG`, `RSA`, `RSG`, `RAG`, `RCSG`, `RCAG`, `RSAG`) work the same way. Combinations Vial has no name for are written to layout.vil as 16-bit values.

### Common keycodes

The full lists are in [data/aliases.yaml](data/aliases.yaml) (aliases) and [data/keycodes.yaml](data/keycodes.yaml) (QMK / Vial names).

- **Basic keys**: letters `A`–`Z`, digits `"0"`–`"9"`, function keys `F1`–`F24`
  - Navigation: `Up`, `Down`, `Left`, `Right`, `Home`, `End`, `PageUp`, `PageDown`
  - Editing: `Enter`, `Escape`, `Backspace`, `Tab`, `Space`, `Delete`
  - Modifiers: `LShift`, `RShift`, `LCtrl`, `RCtrl`, `LAlt`, `RAlt`, `LGui` (`LCmd`), `RGui` (`RCmd`)
  - Symbols: `"-"`, `"="`, `"["`, `"]"`, `"\\"`, `";"`, `"'"`, `` "`" ``, `","`, `"."`, `"/"`
  - Shifted symbols: `"!"`, `"@"`, `"#"`, `"("`, `")"`, `":"` and so on
- **Layer actions**: `MO(n)` (while held), `TG(n)` (toggle), `TO(n)` (switch), `TT(n)` (tap to toggle), `DF(n)` (default), `OSL(n)` (one shot)
  - `LT(n, key)` / `LTn(key)`: layer when held, key when tapped
  - Arguments are numbers (`MO(KC_3)` is an error)
- **Modifiers**:
  - Mod-Tap: `LCTL_T(key)`, `LSFT_T(key)`, `LALT_T(key)`, `LGUI_T(key)`, `MEH_T(key)` and so on, `MT(MOD_LCTL|MOD_LSFT, key)`
  - One Shot: `OSM(MOD_LSFT)`
  - With modifiers: `LSFT(key)`, `C(key)`, `S(key)`, `A(key)`, `G(key)` and combinations (`C_S`, `SGUI`, `MEH`, `HYPR`, ...)
  - `LM(n, MOD_LCTL)`
- **Media and mouse**: `VolumeUp`, `VolumeDown`, `Mute`, `MediaPlayPause` and so on. `MouseUp`, `MouseDown`, `MouseLeft`, `MouseRight`, `MouseButton1`…, `MouseWheelUp` and so on
- **Special keys**: `Trans` (`Transparent`, `___`) uses the layer below, `NoKey` does nothing. `Reset` (`QK_BOOT`) can be written in the settings files, but is never written to the keyboard directly

### How decompile writes keys

decompile writes keys with modifiers in this order of preference:

1. An alias if there is one (`LSFT(KC_1)` → `!`, `LSFT(KC_9)` → `(`)
2. Otherwise a modifier expression (in the order `Ctrl, Option, Shift, Command`; for the right side `RCtrl, ROption, RShift, RCommand`)
   - `LGUI(KC_Q)` → `Command + Q`, `HYPR(KC_LEFT)` → `Ctrl + Option + Shift + Command + Left`

So if you write `Cmd + Q`, compile → decompile gives `Command + Q` (the value is the same).

## YAML pitfalls

YAML decides the type of unquoted values automatically, so **always quote** the following:

| What you want | Correct form | Without quotes |
|---|---|---|
| The digit key `1` | `"1"` | becomes the integer 1 |
| Symbol keys such as `!` `[` `]` `-` | `"!"` `"["` | parsed as YAML syntax and fails |
| `yes` `no` `on` `off` | quote them | become booleans |

When the symbol is in the middle of a string, as in `Command + Shift + [`, quotes are not needed (in YAML syntax only `[`, `{`, `!` and the like at the start cause trouble).
Inside a one-line mapping such as `{ push: ..., ccw: ... }`, however, quote values that contain `[`, `]`, `,` and the like.

Wrong indentation and mixed-in tabs are other common causes.
`cornix validate` (and `compile`) reports such mistakes as "file: location: message", together with how to rewrite them.

## Validating the settings

```bash
cornix validate
```

```
# on success
✓ All validations passed

# on failure (exit code 1)
✗ Validation failed:
  Error: layers/1_symbol.yaml: mapping.left_hand.row0.tab: キーコード「Spce」を解釈できません: 「Spce」は不明なキーコードです
  Error: layers/1_symbol.yaml: mapping.left_hand.row1.capz: position_map の left_hand.row1 にないキーです（使えるキー: caps, A, S, D, F, G）
```

(The messages above say: the keycode "Spce" cannot be interpreted because it is unknown, and `capz` is not a key in `left_hand.row1` of the position map.)

Problems are collected all at once instead of stopping at the first one, and shown as "file: key location: message" (while problems of the first stage below remain, the second stage runs only after they are fixed). `cornix compile` (and `status` / `apply`) runs the same validation first. If there are only warnings (`⚠  Warning: …`), compile continues.

Validation has two stages.

1. **File structure (while reading)**
   - **YAML**: syntax errors, duplicate keys, and YAML aliases (`&` / `*`) are errors. Having both `.yaml` and `.yml` of the same file (such as `metadata.yaml`) is an error
   - **Fields**: required fields are present (a layer's `name` / `index` / `mapping`, ...), there are no unknown fields, and types are correct.
     YAML pitfalls such as an unquoted `1` becoming an integer or `yes` / `no` / `on` / `off` becoming booleans are reported with how to rewrite them
   - **metadata.yaml**: `keyboard` and `version` are required. `uid` and the like are integers of 0 or more
   - **position_map.yaml**: the number of keys in each group, the symbol format, and duplicates within a group
   - **Key names**: each key in a layer exists in that group of `position_map.yaml`
   - **Keycodes**: every assignment can be interpreted (aliases, QMK names, function forms, modifier expressions, references, including function arguments)
   - **Numbers**: layers 0–9, the ranges of macro / tap dance / combo numbers, and that the number in a layer's file name matches `index`
   - **Macros**: `action` is `tap` / `down` / `up` / `delay` / `text` (`beep` is not supported)
   - **QMK Settings**: setting names, value types and widths
2. **Consistency of the whole setup**
   - **Limits**: 10 layers, 32 macros, 32 tap dances, 32 combos, 4 trigger keys per combo
   - **Duplicates**: numbers of layers, macros, tap dances and combos, and names of macros, tap dances and combos
   - **Reference targets**: the targets of `Macro(...)` / `M3` / `TapDance(...)` / `TD(2)` / `Shortcut(...)` are defined
   - **Layer numbers**: layer numbers in `MO(n)` / `LT(n, ...)` and the like do not exceed the number of layers (error), and do not point at undefined layers (warning)
   - **Gaps in layers**: layer numbers that skip (warning)

## Naming the settings files (`rename`)

`cornix rename` has Claude read the contents of macros, tap dances, combos and layers and suggest meaningful names and file names. It needs the Claude Code CLI (the `claude` command).

```bash
ls profiles/default/macros/
# 00_macro.yaml, 01_macro.yaml, ... (default names given by decompile)

cornix rename

ls profiles/default/macros/
# 00_bracket_pair.yaml, 01_end_of_line.yaml, ...
```

How it works:

1. **Check the settings**: the settings are validated. If there are problems, it asks you to fix them first and exits
2. **Suggestions from Claude**: files with default names (`Macro N`, `TapDance N`, `Combo N`, `Layer N`) are passed to the Claude CLI, and the suggestions are received in `<tmp>/rename_plans.json`
   - Macros: the purpose is guessed from the key sequence (e.g. `[`, `]`, `Left` → "Bracket Pair")
   - Tap dances: from the tap / hold / double tap actions
   - Combos: from the triggers and the output
   - Layers: from the description and the assignments
3. **Review the suggestions**: for each one choose `Y` (accept) / `n` (skip) / `e` (edit the file name, name and description)
4. **Rename**: a backup is taken next to the settings directory (such as `profiles/default.backup_<timestamp>/`), the file names and `name` / `description` are changed,
   and references by name `Macro('old name')` / `TapDance('old name')` in every YAML of the settings are updated to the new name (it is a text replacement, so references in combo outputs, encoders, function arguments and `shortcuts.yaml` are covered too)
5. **Verify**: the compile results (16-bit values) before and after the change are compared, and if they differ the backup is restored
6. **Clean up**: temporary files are deleted, and you are asked whether to delete the backup

Example of a suggestion:

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

Safety mechanisms:

- The number prefix (`00_`, `0_`, ...) cannot be changed (trying to is an error)
- Everything runs as one batch; if any rename fails, all of them are rolled back
- References by number (`Macro(3)`, `M3`, `TD(2)`) do not depend on names and are not rewritten

### Running it without Claude (`bin/rename_file`)

```bash
# one file (--dry-run only checks)
ruby bin/rename_file --config-dir profiles/default \
  --old-path profiles/default/macros/03_macro.yaml \
  --new-basename 03_end_of_line.yaml \
  --name "End of Line" \
  --description "Jump to end of line" \
  --dry-run

# several at once from a JSON plan (delete the backup on success)
ruby bin/rename_file --config-dir profiles/default --batch tmp/profiles/default/rename_plans.json --cleanup-backup
```

Format of the plan file:

```json
[
  {
    "old_path": "profiles/default/macros/03_macro.yaml",
    "new_basename": "03_end_of_line.yaml",
    "content_updates": {
      "name": "End of Line",
      "description": "Jump to end of line with Cmd+Right"
    }
  }
]
```

`bin/rename_file` does not read `.cornix.yml`, so always pass `--config-dir` for settings in `profiles/` (the default is `config` in the current directory). The result is printed as JSON, and the exit code is 1 on failure. When the Claude CLI cannot be found, or no JSON can be extracted from its output, `cornix rename` also tells you to write a plan file in this format by hand.

## Converting to and from Vial's layout.vil

You can also read and write with Vial (Web / GUI) instead of writing to the keyboard directly.

```bash
# 1. In Vial, use "File > Export Layout" to save layout.vil (e.g. ~/Downloads/layout.vil)
# 2. Turn it into YAML (creates profiles/default/ and .cornix.yml)
cornix init --from ~/Downloads/layout.vil
# 3. Edit the settings
vim profiles/default/layers/0_layer.yaml
# 4. Turn it into layout.vil (validates first, then writes <tmp>/build/layout.vil)
cornix compile
cornix compile -o my.vil    # choose the output (a relative path is from the current directory)
# 5. In Vial, use "File > Import Layout" to load <tmp>/build/layout.vil
```

- compile validates first, and if there are problems it exits without writing the .vil (exit code 1)
- To write a layout.vil into an existing settings directory, use `cornix decompile [FILE]` (`FILE` defaults to `<tmp>/layout.vil`).
  It stops if the settings directory already has settings (same as [When `pull` stops](#when-pull-stops))
- On success, init / decompile create `.decompile.lock` (the source file and its checksum) in the settings directory
- `cornix device diff` / `device apply` also use the compile output when the file is omitted (if you have not compiled yet, they tell you to compile first and exit)

### Deleting generated files (`cleanup`)

```bash
cornix cleanup      # delete the settings directory and <tmp>/build/layout.vil (stops without deleting if there is a lock file)
cornix cleanup -f   # delete even with a lock file, after asking (y/N)
```

It deletes the settings directory chosen by [the same rules](#how-the-settings-directory-is-chosen) as the other commands (such as `profiles/default/`) and the compile output.

### About the unlock step when changing macros

Vial (Web / GUI) asks for an "unlock" (holding two specific keys) when saving macros and when assigning `QK_BOOT`. This is behavior of the Vial app; the Cornix firmware (RMK 0.8 series) does not check the lock state when macros are written. So `cornix apply` / `cornix device` / MCP need no unlock (boot keycodes such as `QK_BOOT` cannot be written in the first place).

## Backups and restoring

Before writing, `apply` and `restore` save the keyboard's state as a timestamped .vil in `<tmp>/device_backups/`.
To keep one yourself, run `cornix device backup`.

```bash
cornix restore                                      # go back to the last backup (the state before the last apply)
cornix restore tmp/profiles/default/device_backups/<timestamp>.vil   # go back to the given backup
cornix restore --yes                                # skip the question
```

- It shows the differences from the last backup taken and writes after confirmation
- `restore` also backs up the current state before writing, so running `restore` again right away returns to the state before the restore
- `restore` only changes the keyboard. To restore the settings files too, use Git, or move the settings aside and read them again with `cornix pull`

## Where the settings live and how to use the repository

### How the settings directory is chosen

The settings directory a command uses is chosen in this order (first match wins):

1. `--config DIR`
2. The `CORNIX_CONFIG` environment variable
3. `--profile NAME` (`profiles/NAME/`)
4. The first `.cornix.yml` found walking up from the current directory (with `--root DIR`, only `DIR/.cornix.yml` is used)
   - `profile: NAME` … `profiles/NAME/` next to `.cornix.yml`
   - `config: PATH` … a path relative to `.cornix.yml`
5. Otherwise, this repository's `config/` (the old location, kept for backward compatibility)

When settings other than `config/` are in use, the first line of `compile` / `decompile` / `validate` / `pull` / `status` / `apply` / `restore` / `rename` / `cleanup` shows which settings were chosen and how, as in "設定: profiles/default（.cornix.yml）" ("Settings: profiles/default (.cornix.yml)").

`<tmp>` (the working directory) is separate for each settings directory: `tmp/profiles/NAME/` for `profiles/NAME/`, and `tmp/` for `config/`.
For settings directories outside `profiles/` (such as one given with `--config`), a hash of the path is added to the name so that directories with the same name don't get mixed up.

One repository can hold several settings (for example `profiles/work/` and `profiles/game/`). Switch by editing `.cornix.yml`, or add `--profile`.

### What `init` creates

```bash
cornix init [DIR] [--profile NAME | --config DIR] [--from FILE] [--no-pull]
```

- `DIR` is where `.cornix.yml`, `tmp/` and `profiles/` go (default: `--root`, otherwise the current directory)
- The settings are created in `DIR/profiles/NAME/` with `--profile NAME`, in the given place with `--config`, and in `DIR/profiles/default/` otherwise
  (the place for init is decided only by the common options; the `CORNIX_CONFIG` environment variable and an existing `.cornix.yml` are not used)
- It writes a `.cornix.yml` (`profile: NAME` or `config: PATH`) so that later commands use the new settings. An existing one is left unchanged
  (and none is written when `--config` points at this repository's `config/`)
- Where there is no `.cornix.yml` but a non-empty `config/`, `cornix init` without options creates nothing and stops, so that the settings in use don't change silently.
  Give the place with `--profile NAME` or `--config DIR`. When it creates the settings that way, it tells you that the new settings will be used from then on
- When it creates settings outside this repository, it adds the lines `tmp/` and `.decompile.lock` to `.gitignore` (for a repository that holds only settings). Lines that are already there are not added
- If the keyboard is connected (or with `--from FILE`, from that .vil), it writes the same settings as decompile would

This repository's `.gitignore` keeps `/.cornix.yml` and `/profiles/` out of Git (they are local settings).
To manage your settings in a fork or a branch, delete those two lines.

### If you use the old `config/`

Without a `.cornix.yml`, this repository's `config/` is used as before, so nothing needs to change.
In that state, `cornix init` without options stops to protect `config/`.
To move to `profiles/`, move the directory and write `.cornix.yml`:

```bash
mkdir -p profiles && mv config profiles/default
echo "profile: default" > .cornix.yml
cornix validate          # the move worked if it shows "設定: profiles/default（.cornix.yml）"
```

`<tmp>` also changes from `tmp/` to `tmp/profiles/default/`. To use your earlier backups with `restore`,
copy `tmp/device_backups/` to `tmp/profiles/default/device_backups/`.

### Ways to use it

**A. Use it in this repository (or a fork)**

The simplest form. Create `profiles/default/` with `cornix init` and use `cornix status` / `cornix apply` as they are.
To manage the settings in Git, delete the `/.cornix.yml` and `/profiles/` lines from `.gitignore` and make a branch on top of main with your settings committed
(the same form as the author's `authors-keymap` branch).

**B. Fork it and keep several settings in `profiles/`**

```bash
# after forking this repository on GitHub
git clone <your fork> cornix-layout && cd cornix-layout
bundle install
cornix init --profile <your name>
# names may use letters, digits and . _ - (starting with a letter or digit)
# after deleting the /.cornix.yml and /profiles/ lines from .gitignore
git add .gitignore profiles .cornix.yml && git commit -m "Add my settings"
git push
```

Upstream never changes what is inside `profiles/` or `.cornix.yml`, so you can take upstream updates with GitHub's "Sync fork" or `git pull upstream main`.

**C. Keep only the settings in a separate repository**

Clone the tool and put `cornix` on your PATH, and keep the settings in a different directory (repository).

```bash
mkdir my-cornix && cd my-cornix && git init
cornix init                    # creates profiles/default/ and .cornix.yml, and adds tmp/ and .decompile.lock to .gitignore
cornix status                  # run in this directory (or below it)
```

To update the tool, just run `git pull` in the directory where you cloned it.

### Sample settings

The following branches have sample settings. Each is main with settings (`profiles/<name>/`) and a `.cornix.yml` on top.

| Branch | Settings | Contents |
|---|---|---|
| `cornix-default-keymap` | `profiles/cornix-default/` | The standard Cornix layout. Recommended for first-time users |
| `authors-keymap` | `profiles/authors/` | The keymap the author actually uses, with examples of references by name, modifier expressions, combos and more |

So that the branch's `.cornix.yml` does not clash with your own, opening it in a separate directory (a worktree) is recommended.
If you cloned a fork, it may not have these branches; fetch them from upstream first
(`git remote add upstream https://github.com/guccyon/cornix-layout.git && git fetch upstream`, then use `upstream/cornix-default-keymap`).

```bash
git worktree add ../cornix-default-keymap cornix-default-keymap
cd ../cornix-default-keymap
cornix compile          # compiles with "設定: profiles/cornix-default（.cornix.yml）"
```

Contributions of sample settings are welcome too (share them on a new branch and open a pull request).

## Using it as an MCP server

`cornix mcp` runs an MCP (Model Context Protocol) server over standard input and output.
It lets an AI agent do things like "read the keyboard's current settings" or "apply this layout.vil".

- **Claude Code**: it is already registered as `cornix-device` in `.mcp.json` at the repository root. Open Claude Code in this directory and allow the MCP server when asked the first time
- **Other clients** (such as Claude Desktop): register it with an absolute path as below. If `ruby` cannot be found (mise / rbenv and so on), put the absolute path of Ruby in `command`

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

The settings directory is chosen in the same order as for the other commands. To use settings in another place, add `--root /path/to/my-cornix` or `--profile NAME` to `args`.

`cornix mcp` reads and writes UTF-8 even when the `LANG` environment variable is not set, and escapes non-ASCII characters in the JSON responses as `\uXXXX`, so clients can read them whatever their locale.

Available tools:

| Tool | Writes | Description |
|---|---|---|
| `keyboard_info` | No | Information about the keyboard |
| `read_keymap` | No | Returns or saves the current state in layout.vil format |
| `backup` / `list_backups` | No | Saves and lists backups |
| `apply_layout` | Only with `dry_run: false` | A dry run by default, returning the differences and a `confirm_token`. Writes only with `dry_run: false` and the `confirm_token` |
| `restore_backup` | Only with `dry_run: false` | Goes back to the last backup (or the one given in `backup_path`). Dry run and `confirm_token` work the same as `apply_layout` |

How applying works:

1. Make the compile output with `cornix compile` (`<tmp>/build/layout.vil`, the default `vil_path` of `apply_layout`)
2. Call `apply_layout` (dry run) to get the differences and a `confirm_token`, and review them
3. If you agree, call `apply_layout` with `dry_run: false` and the `confirm_token`. It backs up automatically, writes only the differences, and reads back to verify
4. To undo, call `restore_backup` the same way, a dry run first and then with the `confirm_token` (choose older backups with `list_backups` and pass them in `backup_path`)

If the differences changed after the review (the keyboard or the file was changed), the token no longer matches and the write is refused.
If the keyboard is not connected, every tool returns an error response and writes nothing.
Even when you let an AI assistant write, always ask it to show you the dry run result before writing.

## Safety mechanisms

The Cornix firmware is the RMK 0.8 series, which, unlike vial-qmk, has almost no locks or range checks (entering the bootloader and resetting the EEPROM run without a lock, and out-of-range writes make the firmware panic). So the tool does the following:

- **Allowlist of commands**: the HID bridge (`ext/cornix_hid/main.swift`) only sends commands on its allowlist. Entering the bootloader, resetting the EEPROM, erasing everything, unlocking, and bulk keymap writes (buggy in RMK 0.8) cannot be sent (check with `tmp/cornix-hid --self-test`)
- **Range checks**: keys are written one at a time, as the Vial GUI does, and layer / row / col, macro offsets and every entry number are range-checked before sending
- **Keys that are never written**: boot keycodes such as `QK_BOOT` ([data/dangerous_keycodes.yaml](data/dangerous_keycodes.yaml)) are never written, even if they are in the settings files
- **Validate before writing**: `status` / `apply` compile every time, and never touch the keyboard if validation fails
- **Confirm before writing**: `apply` / `restore` show the differences and ask for confirmation. MCP has two steps, a dry run and the `confirm_token`
- **Backup before writing**: the state just before writing is always saved to `<tmp>/device_backups/`
- **Write only the differences and verify**: only changed items are written, and finally the keyboard is read back and checked

## Troubleshooting

### When the keyboard is not connected

`cornix pull` / `status` / `apply` / `restore`, every `cornix device` command, and every MCP tool first look for the keyboard and connect to it. If it cannot be found, they write nothing and end with an error (the CLI prints to standard error and exits with 1; MCP returns an error response).

```
エラー: Cornix が見つかりません。Mac と Bluetooth（または USB）で接続されているか、スリープしていないか、別の機器に接続先が切り替わっていないかを確認してください
```

(The message says the Cornix was not found, and asks you to check that it is connected to the Mac over Bluetooth (or USB), is not asleep, and has not switched to another device.)

- **Bluetooth is disconnected or the keyboard is off**: you get the error above. Press a key once to wake it, or check the connection to the Mac, and run the command again
- **The keyboard has switched to another device (BT1 / BT2, ...)**: the Mac cannot see it, so you get the same error. Switch to the channel connected to the Mac
- **The connection dropped while reading or writing**: if there is no response within 1 second, it stops with the error "キーボードから応答がありません" ("no response from the keyboard"). If it was writing, it shows how many items were written and the path of the backup taken before writing; reconnect and run `cornix apply` again, or go back with `cornix restore` (both write only the differences)

### Common errors

**A keycode cannot be interpreted**

```
Error: layers/0_base.yaml: mapping.left_hand.row0.Q: キーコード「Spce」を解釈できません: 「Spce」は不明なキーコードです
```

It is a typo (`Spce` → `Space`). The available names are in [data/aliases.yaml](data/aliases.yaml) and [data/keycodes.yaml](data/keycodes.yaml).

**A key that is not in the position map**

```
Error: layers/0_base.yaml: mapping.left_hand.row1.capz: position_map の left_hand.row1 にないキーです（使えるキー: caps, A, S, D, F, G）
```

Use a symbol that exists in that group of `profiles/default/position_map.yaml`, or change `position_map.yaml`.

**Duplicate numbers or names**

```
Error: layers/2_layer.yaml: index: レイヤーの番号が重複しています: 2
Error: macros/01_macro.yaml: name: マクロの名前が重複しています: Bracket Pair
```

Change `index` / `name` in one of the files.

**A reference to a macro or tap dance that does not exist**

```
Error: layers/0_base.yaml: mapping.left_hand.row0.Q: キーコード「Macro('Unknown')」を解釈できません: マクロ「Unknown」が見つかりません
```

Check the `name` in `profiles/default/macros/*.yaml` and fix the reference (`grep '^name:' profiles/default/macros/*.yaml`).

**Mixed left and right modifiers**

```
キーコード「Shift + RCmd + A」を解釈できません: 左右の修飾キーは混在できません（例: Shift と RCmd）
```

A QMK keycode with modifiers can express only the left or only the right side. Use one side.

**decompile / pull stops, or cleanup stops**

See [When `pull` stops](#when-pull-stops). If cleanup stops with `Protected: config/ directory has an active lock file`, use `cornix cleanup -f`.

**The Claude Code CLI (the `claude` command) cannot be found**

```
  ❌ Error: Claude CLI not found
```

`cornix rename` needs the Claude Code CLI. Install it from https://claude.ai/download and check with `claude --version`.

**The round-trip check fails**

Look at the output of `ruby bin/diff_layouts` to see which layer, row or item differs (see [Round-trip check](#round-trip-check)). Please open an issue with the original layout.vil and the generated one attached.

## For developers

### Structure

The code is split into layers. Settings files, layout.vil and HID bytes are all treated as outer representations, and the inner layers only handle typed values (the domain model).

```
Interface       CLI (bin/cornix → Interface::Cli::Main) and the MCP server
Application     use cases (Init / Compile / Decompile / Validate / Cleanup / RenameFiles / Device*), Workspace and Environment
Mapping         conversion between keycode notation and values (KeycodeNotation / VialNotation / KeycodeCodec), Profile ⇄ DeviceImage (ProfileMapper)
Planning        differences between DeviceImages and the write plan
Domain          Profile and value objects (Keycode, Layer, Macro, TapDance, Combo, PositionMap ...)
Image           DeviceImage (the state of a layout.vil or the hardware, as 16-bit values)
Storage         settings files (ConfigRepository), layout.vil (VilFile), backups, .cornix.yml (SettingsFile)
Device          communication with the HID bridge, reading and writing the hardware
```

```
compile    settings directory → Profile → DeviceImage → layout.vil
decompile  layout.vil → DeviceImage → Profile → settings directory
device     write the differences between layout.vil → DeviceImage (target) and hardware → DeviceImage (current), then read back to verify
```

Design documents (in Japanese):

- [docs/architecture.md](docs/architecture.md) … principles, dependency direction, data flow and coding conventions
- [docs/tasks.md](docs/tasks.md) … public methods of the main classes, and the history of the refactoring
- Development rules are in [.claude/CLAUDE.md](.claude/CLAUDE.md)

### Directory structure

```
cornix-layout/
├── bin/
│   ├── cornix                # CLI (Interface::Cli::Main)
│   ├── diff_layouts          # compare two layout.vil files by 16-bit value
│   └── rename_file           # run renames directly (prints the result as JSON)
├── data/
│   ├── keycodes.yaml         # table of named keycodes (Vial protocol 6)
│   ├── aliases.yaml          # keycode aliases (QMK name: [canonical name, alias...])
│   ├── qmk_settings.yaml     # QSID, names and widths of QMK Settings
│   └── dangerous_keycodes.yaml # keycodes never written to the hardware
├── lib/
│   ├── cornix.rb             # loads every file in layer order
│   └── cornix/
│       ├── domain/ image/ mapping/ planning/ storage/ device/ application/ interface/
│       ├── errors.rb         # Cornix::Error exceptions
│       └── position_map.yaml # template of position_map
├── ext/cornix_hid/main.swift # raw HID bridge (with an allowlist, built to tmp/cornix-hid)
├── spec/                     # RSpec (same layer structure as lib; see spec/README.md)
├── docs/                     # architecture.md, tasks.md
├── .mcp.json                 # MCP server registration for Claude Code
├── .cornix.yml               # which settings to use (created by cornix init; not tracked by Git)
├── profiles/<name>/          # settings files (created by cornix init; not tracked by Git)
├── config/                   # settings in the old location (backward compatible; not on main)
└── tmp/                      # generated files (not tracked by Git)
    └── profiles/<name>/      # <tmp> for each settings directory (directly under tmp/ for config/)
        ├── build/layout.vil  # compile output (used by status / apply)
        ├── layout.vil        # default input of decompile (pull writes the keyboard's state here)
        └── device_backups/   # backups taken before apply / restore
```

### Tests

```bash
LANG=ja_JP.UTF-8 bundle exec rspec                       # everything
LANG=ja_JP.UTF-8 bundle exec rspec spec/mapping          # one layer
LANG=ja_JP.UTF-8 bundle exec rspec spec/end_to_end_spec.rb
```

- The specs follow the same layer structure as lib (`spec/domain`, `spec/mapping`, ... `spec/interface`)
- `spec/end_to_end_spec.rb` compiles `spec/fixtures/test_config` and the author's keymap (`spec/fixtures/authors_config`), and checks that they match the saved layout.vil files by 16-bit value and that decompile → compile gives back the original
- `spec/architecture_spec.rb` checks the dependency direction between layers
- `spec/docs/readme_sync_spec.rb` checks that README.md (English) and README.ja.md (Japanese) have the same structure
- `FakeRmkDevice`, which imitates the responses of RMK 0.8, stands in for the hardware, so the tests run without a keyboard

See [spec/README.md](spec/README.md) for details. GitHub Actions also runs RSpec on every push / pull request.

### Round-trip check

A procedure to check that decompile → compile gives back your own layout.vil.

```bash
rm -rf /tmp/cornix-roundtrip                                      # remove the settings left from an earlier check, if any
cornix init /tmp/cornix-roundtrip --from ~/Downloads/layout.vil   # create settings in a separate place for the check
cornix compile --root /tmp/cornix-roundtrip                       # → /tmp/cornix-roundtrip/tmp/profiles/default/build/layout.vil
ruby bin/diff_layouts ~/Downloads/layout.vil /tmp/cornix-roundtrip/tmp/profiles/default/build/layout.vil
# expected: === ✓ FILES ARE IDENTICAL ===
```

`bin/diff_layouts [FILE1 FILE2]` (when omitted, `tmp/layout.vil` and `tmp/build/layout.vil` in the current directory; these are the paths for the old `config/`, so give both files when you use `profiles/`) reads two layout.vil files and compares keys, encoders, macros, tap dances, combos and settings by 16-bit value. Different notations of the same value (such as `KC_PGDN` and `KC_PGDOWN`) count as the same. If they differ, it shows where and exits with 1.

### Contributing

Pull requests are welcome.

1. Fork this repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Make sure `LANG=ja_JP.UTF-8 bundle exec rspec` passes
4. Commit and push
5. Open a pull request

When you change the README, change both README.md (English) and README.ja.md (Japanese) in the same commit.

## Notes

- This tool is not an official Cornix product and is not affiliated with its makers
- A firmware update may change the protocol
- The author accepts no responsibility for problems caused by using this tool. Keep a copy of important settings, for example by exporting a layout.vil from Vial
- License: MIT License
- References: [Vial Documentation](https://get.vial.today/), [QMK Firmware Documentation](https://docs.qmk.fm/), [QMK Keycodes](https://docs.qmk.fm/keycodes_basic)
