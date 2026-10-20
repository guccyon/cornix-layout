# Cornix Keyboard Layout Manager

English | [日本語](README.ja.md)

A tool that manages the keymap of the Cornix keyboard (layers, encoders, macros, tap dances, combos and QMK Settings)
as human-readable YAML files, and writes it directly to the connected keyboard without Vial.

- Read the settings from the keyboard into YAML (`pull`)
- Edit the YAML and review the differences from the keyboard (`status`)
- Write only the differences to the keyboard (`apply`). A backup is always taken before writing, and the keyboard is read back afterwards to verify
- If you don't like the result, restore from a backup (`restore`)

Because the settings are plain files, you can keep them in Git to track their history or switch between setups.
The YAML supports modifier expressions such as `Cmd + Q`, references by name such as `Macro('Bracket Pair')`, named shortcuts, notes and comments.
It also runs as an MCP server, so AI assistants such as Claude can read and change the keyboard's settings.
If you prefer to read and write with Vial, it can also convert to and from `layout.vil` (see [Using Vial](#using-vial-compile--decompile)).
Some of the command output, including many error messages, is currently in Japanese.

> **This is an unofficial tool.** It is not affiliated with the makers of the Cornix.
> Reading and writing the keyboard directly is based on testing with real hardware and the public sources of Vial and RMK. Use it at your own risk.

## Contents

- [Supported environment](#supported-environment)
- [Requirements](#requirements)
- [Getting started](#getting-started)
- [Commands](#commands)
- [Writing the settings files](#writing-the-settings-files)
- [Writing keys](#writing-keys)
- [YAML pitfalls](#yaml-pitfalls)
- [Validating the settings](#validating-the-settings)
- [Naming (rename)](#naming-rename)
- [Backups and restoring](#backups-and-restoring)
- [Where the settings live and how to use the repository](#where-the-settings-live-and-how-to-use-the-repository)
- [Editing on screen in VS Code](#editing-on-screen-in-vs-code)
- [Using it as an MCP server](#using-it-as-an-mcp-server)
- [Safety mechanisms](#safety-mechanisms)
- [Troubleshooting](#troubleshooting)
- [Using Vial (compile / decompile)](#using-vial-compile--decompile)
- [For developers](#for-developers)
- [Notes](#notes)

## Supported environment

| Item | Support |
|---|---|
| Keyboard | Cornix |
| Firmware | RMK 0.8 series (Vial protocol 6) |
| OS | Talking to the keyboard (`pull` / `status` / `apply` / `restore` / `device` / `mcp`): macOS only. `validate` and the Vial conversions: anywhere Ruby runs |
| Connection | Bluetooth or USB |

## Requirements

- **Ruby 3.2 or later** (the code uses `Data.define`; CI uses 4.0). The tool uses only the standard library, so there are no gems to install (no `bundle install`)
- **Xcode Command Line Tools** (for talking to the keyboard; install with `xcode-select --install` if `swiftc` is missing)
  - The tool talks to the keyboard through a small Swift program (`ext/cornix_hid/main.swift`). It is built automatically on first use and placed in `tmp/cornix-hid`
- **Claude Code CLI** (the `claude` command; only for `cornix rename`)

## Getting started

### 1. Get the tool

```bash
git clone https://github.com/guccyon/cornix-layout.git   # or clone your own fork
cd cornix-layout
```

If you run `cornix init` as is, the settings are not tracked by Git (`.gitignore` excludes them). To keep them in Git, fork the repository or keep the settings in a separate repository (see [Ways to use it](#ways-to-use-it)).

To use it as a `cornix` command, put a symlink to `bin/cornix` in a directory on your PATH (you can also run `ruby bin/cornix <command>`).

```bash
mkdir -p ~/.local/bin && ln -s "$PWD/bin/cornix" ~/.local/bin/cornix   # add ~/.local/bin to PATH if it is not there
cornix help             # list of commands (cornix help <command> for details)
cornix --version        # the version of the tool
```

Releases are tagged as `vX.Y.Z` (for example `git checkout v1.0.0`). The changes in each version are in [CHANGELOG.md](CHANGELOG.md) (in Japanese).

### 2. Create the settings (`init`)

Connect the Cornix to your Mac over Bluetooth (or USB), check the connection with `cornix device info`, then run:

```bash
cornix init
```

The keyboard's current settings are written as YAML into `profiles/default/`, and which settings to use (`profile: default`) is written to `.cornix.yml`.
Later commands read this and use `profiles/default/`.

- If the keyboard could not be reached, only an empty settings directory is created; connect the keyboard and run `cornix pull`
- If the settings directory already has files in it, `init` stops without overwriting them
- To use another name or keep the settings in another repository, see [Where the settings live and how to use the repository](#where-the-settings-live-and-how-to-use-the-repository)

Layers and macros start with names like `Layer 0` and `Macro 0`. With `cornix rename`, Claude reads them and suggests names (see [Naming (`rename`)](#naming-rename)).

### 3. Edit the settings

Edit the YAML in `profiles/default/` with your editor. See [Writing the settings files](#writing-the-settings-files) for the format.
You can check the files for mistakes without the keyboard with `cornix validate`.

### 4. See the differences (`status`)

```bash
cornix status
```

It compares the settings with the keyboard's current state and lists the changes that would be written (it does not write to the keyboard). It exits with 0 when there are no differences and 2 when there are.

### 5. Write (`apply`)

```bash
cornix apply           # show the differences, ask [y/N], then write
cornix apply --yes     # skip the question
```

How it backs up and verifies is described in [Safety mechanisms](#safety-mechanisms).

### 6. Undoing (`restore`)

```bash
cornix restore         # go back to the state before the last apply
```

See [Backups and restoring](#backups-and-restoring) for details.

## Commands

```
cornix <command> [options]
```

| Command | Keyboard | Description |
|---|---|---|
| `init [DIR] [--from FILE] [--no-pull]` | Reads (not with `--from` / `--no-pull`) | Creates a settings directory (default `profiles/default/`) and `.cornix.yml`, and writes the settings from the keyboard (or the .vil given with `--from`) |
| `pull` | Reads | Turns the keyboard's state into YAML in the settings directory. Stops if there are settings already |
| `status` | Reads | Shows the differences from the keyboard. Exits with 2 when there are differences |
| `apply [--yes]` | Writes (after confirmation) | Writes to the keyboard after you confirm the differences |
| `restore [BACKUP] [--yes]` | Writes (after confirmation) | Goes back to a backup (default: the state before the last apply) |
| `validate` | Not used | Validates the settings files |
| `rename` | Not used | Gives the settings files meaningful names, confirming Claude's suggestions one by one |
| `mcp` | Depends on the tool | Starts as an MCP server (see [Using it as an MCP server](#using-it-as-an-mcp-server)) |
| `serve` | Not used | The backend of the VS Code extension (see [Editing on screen in VS Code](#editing-on-screen-in-vs-code)) |

`cornix device` reads and writes with explicit files.

| Subcommand | Description |
|---|---|
| `device info` | Information about the connected keyboard |
| `device read [-o FILE]` | Prints the keyboard's state in layout.vil format |
| `device backup` | Saves the keyboard's state to `<tmp>/device_backups/` |
| `device diff [FILE]` / `device apply [FILE] [--yes]` | Shows the differences between the given .vil and the keyboard / writes it (default: the compile output) |
| `device restore [BACKUP] [--yes]` | Same as `restore` |

`compile` / `decompile` / `cleanup` for Vial are described in [Using Vial](#using-vial-compile--decompile).

Common options (accepted by every command, before or after the command name):

| Option | Description |
|---|---|
| `--profile NAME` | Use the settings in `profiles/NAME/` |
| `--config DIR` | Give the settings directory directly |
| `--root DIR` | Where `tmp/` and `profiles/` live (default: the directory containing `.cornix.yml`, otherwise this repository) |

Normally `.cornix.yml` decides this, so you don't need them.

Exit codes: `0` = success, `1` = error, `2` = there are differences (`status` only). Errors are printed to standard error as `エラー: …` ("Error: …").

### When `pull` stops

If the settings directory already has settings (files in `layers/` or `macros/`), `pull` stops without reading the keyboard, so that your edits are not overwritten.

```
⚠️  Error: config/ directory already contains configuration files.
```

(The message says `config/` even when the settings directory is under `profiles/`.)
To rebuild the settings from the keyboard, move the current settings aside first.

```bash
mv profiles/default profiles/default.backup
cornix pull
```

The keyboard holds no names, so in the settings read again the names and descriptions of layers and macros, notes, `Shortcut('name')` references and file names go back to their defaults. Bring back what you need from the directory you moved aside.
If you only want to see how the settings differ from the keyboard, `cornix status` is enough.

## Writing the settings files

### File layout

```
profiles/default/
├── metadata.yaml              # keyboard information (version / uid, ...)
├── position_map.yaml          # mapping between key names and physical positions
├── settings/qmk_settings.yaml # QMK Settings (tapping_term, ...)
├── shortcuts.yaml             # named shortcuts (optional; you write it yourself)
├── layers/0_layer.yaml        # layers 0–9
├── macros/00_macro.yaml       # macros
├── tap_dance/00_tap_dance.yaml # tap dances
└── combos/00_combo.yaml       # combos
```

- You can rename files freely (both `.yaml` and `.yml` are read). The number comes from `index` in the YAML; only for layers must the leading number of the file name match `index`
- `pull` writes keys in the most readable form (alias → modifier expression → function form → `0xHHHH`), and refers to macros and tap dances by name

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

- Under `mapping` the structure is the same as `position_map.yaml`. Each hand must list all of `row0`–`row3` and `thumb_keys` (an empty value is fine)
- Keys you leave out inside a group are unassigned, and `compile` / `apply` write them as `NoKey` (KC_NO). To use the layer below, write `Trans`. Encoder actions you leave out are `NoKey`
- To change a layer's number, change the file name and `index`, and update `MO(2)` and the like in other files

### Notes (`note`)

Wherever a key is assigned (layer keys and encoders, tap dance actions, a combo's `output_key`), you can attach a note with `key` and `note`.

```yaml
# excerpt of a layer file
mapping:
  left_hand:
    row0:
      tab:
        key: TapDance('Tab Escape')
        note: Tab on tap, Escape on hold
  encoders:
    left:
      push: { key: Mute, note: Mute }
```

Notes stay only in the settings files and are never written to the keyboard. `key` cannot be omitted.

### Macros

```yaml
# profiles/default/macros/01_curly_bracket_pair.yaml
name: Curly Bracket Pair
description: "Type {} and move the cursor back inside"
index: 1
sequence:
  - action: down           # press (several keys at once)
    keys: LShift
  - action: tap            # tap in order (a single key can be written as keys: Left)
    keys: ["[", "]"]
  - action: up             # release
    keys: LShift
  - action: tap
    keys: Left
```

There are also `action: text`, which types a string (`content:`, ASCII only), and `action: delay`, which waits (`duration:` in milliseconds).

Write `preset` instead of `sequence` to make a macro from the steps of a bundled shortcut ([data/shortcuts/](data/shortcuts/)).

```yaml
# profiles/default/macros/05_window_capture.yaml
index: 5
preset: 'macOS:システム:ウィンドウキャプチャ'   # ⌘⇧4 → Space
# without name, the preset name is used (refer to it as Macro('macOS:システム:ウィンドウキャプチャ'))
```

- Shortcuts that cannot be a single key, such as keys pressed one after another (S → P for `Fusion 360:スケッチ:スプライン`), are used this way (not with `Shortcut(...)`)
- Single-key shortcuts work too. A key with modifiers becomes "press the modifiers → tap the key → release the modifiers"
- `preset` uses only the bundled definitions (overriding the same name in `shortcuts.yaml` does not change it)
- You choose the macro number (`index`) yourself. The preset is not written to the keyboard, so decompile writes the macro as a plain `sequence`

### Tap dances

```yaml
# profiles/default/tap_dance/00_tab_escape.yaml
name: Tab Escape
index: 0
actions:
  on_tap: Tab
  on_hold: Escape
  on_double_tap: NoKey     # NoKey if omitted
  on_tap_hold: NoKey
tapping_term: 200          # milliseconds (250 if omitted)
```

### Combos

```yaml
# profiles/default/combos/06_left_click.yaml
name: Left Click
index: 6
trigger_keys: [Left, Down]   # up to 4 keys
output_key: MouseButton1
```

Triggers are written as keycodes, not key positions. A combo whose trigger keys are not all present on any single layer cannot be pressed, so `validate` warns about it (a `Trans` position counts as the layer 0 value).

### QMK Settings

```yaml
# profiles/default/settings/qmk_settings.yaml
keyboard:
  tapping_term: 180
  permissive_hold: false
  hold_on_other_key_press: true
vial:
  combo_timing_window: 50
```

The available names and value widths are in [data/qmk_settings.yaml](data/qmk_settings.yaml). Settings you leave out keep their current values on the keyboard.

### Referring to macros and tap dances

| Form | Macro | Tap dance |
|---|---|---|
| By name (recommended) | `Macro('Bracket Pair')` | `TapDance('Tab Escape')` |
| By number (`index`) | `Macro(0)` | `TapDance(2)` |
| QMK form | `M0` | `TD(2)` |

- The name is the file's `name`. Put names containing `'` in `"..."` (`Macro("Rock'n Roll")`)
- A name that cannot be found, or a number with nothing defined, is a validation error
- References cannot be used inside macros (in `keys` of a `sequence`)

### Named shortcuts (`shortcuts.yaml`)

When you use the same shortcut in several places, define it with a name and refer to it with `Shortcut('name')`.

```yaml
# profiles/default/shortcuts.yaml
shortcuts:
  Previous Tab: Command + Shift + [
  Next Tab: Command + Shift + ]
  Bracket Pair: Macro('Bracket Pair')    # references to macros and tap dances are allowed too
```

```yaml
# profiles/default/layers/0_base.yaml (excerpt)
mapping:
  left_hand:
    row0:
      Q: Shortcut('Previous Tab')
      W: Shortcut('Next Tab')
```

- `Shortcut('name')` becomes exactly the keycode it defines. It also works inside function arguments (`LT1(Shortcut('name'))`) when the definition is a key allowed there (a basic key for `LT1`)
- A name that is not defined is a validation error. `Shortcut(...)` cannot be used in the values of `shortcuts.yaml` or inside macros
- `pull` does not create `shortcuts.yaml`; you write it yourself
- Shortcuts shared on [cornixhub](https://cornixhub.com/shortcuts) (824 shortcuts for 27 apps) can be used without defining them, as `Shortcut('app:category:label')` (for example `Shortcut('Spotify:再生:次のクリップ')`). The available names are in the files under [data/shortcuts/](data/shortcuts/). Labels are cornixhub's Japanese names
- A definition with the same name in `shortcuts.yaml` takes precedence over the bundled one
- decompile writes `Shortcut(...)` back only for definitions in `shortcuts.yaml` (values equal to a bundled shortcut are written as plain keycodes)
- Multi-step entries (written with `macro:`) cannot be used with `Shortcut(...)`. Use them through `preset` in [Macros](#macros)

### Key positions (`position_map.yaml`)

The key names used in layer files (`left_hand.row0.Q` and so on) come from `position_map.yaml`. You can rename them freely.

```yaml
left_hand:
  row0: [tab, Q, W, E, R, T]
  row1: [caps, A, S, D, F, G]
  row2: [lshift, Z, X, C, V, B]
  row3: [lctrl, command, option]
  thumb_keys: [left, middle, right]
right_hand:
  row0: [Y, U, I, O, P, backspace]
  row1: [H, J, K, L, colon, enter]
  row2: [N, M, comma, dot, up, rshift]
  row3: [left, down, right]
  thumb_keys: [left, middle, right]
encoders:
  left: { push: push, ccw: ccw, cw: cw }
  right: { push: push, ccw: ccw, cw: cw }
```

- For both hands, keys are listed **physically from left to right**
- A name only needs to be unique within its group, and may contain letters, digits, `_` and `-`

## Writing keys

Names are case-sensitive.

| Kind | Examples | Description |
|---|---|---|
| Key names | `A` `Tab` `Enter` `Escape` `Space` `Left` `F5` `VolumeUp` `MouseButton1` | The available names are in [data/aliases.yaml](data/aliases.yaml) and [data/keycodes.yaml](data/keycodes.yaml) (QMK names such as `KC_TAB` work too) |
| Symbols | `"!"` `"@"` `"["` `"1"` | Put a single symbol or digit in quotes |
| Nothing / layer below | `NoKey` / `Trans` | |
| Modifier expressions | `Cmd + Q` `Ctrl + Shift + F` | [Modifier expressions](#modifier-expressions) |
| QMK functions | `LGUI(KC_Q)` `LCTL_T(A)` `OSM(MOD_LSFT)` | Mod-Tap, such as Ctrl when held and A when tapped, works too |
| Layer actions | `MO(1)` `TG(2)` `TO(0)` `LT(1, Space)` `LT1(Space)` | The number is the layer's `index` |
| References | `Macro('Bracket Pair')` `TapDance(2)` `Shortcut('Previous Tab')` | [References](#referring-to-macros-and-tap-dances), [shortcuts](#named-shortcuts-shortcutsyaml) |
| Raw value | `0x7E00` | A value the tables cannot express (`pull` also writes values it cannot interpret this way) |

Boot keycodes such as `QK_BOOT` (`Reset`) can be written in the settings files, but are never written to the keyboard.
`QK_REPEAT_KEY` / `QK_ALT_REPEAT_KEY` / `QK_LAYER_LOCK` / `USER08`–`USER63` seem unsupported by Cornix (Vial does not show them either); they are written, but `validate` / `compile` / `status` / `apply` warn about them ([data/unsupported_keycodes.yaml](data/unsupported_keycodes.yaml)).

### Modifier expressions

```yaml
Q: Cmd + Q                         # LGUI(KC_Q)
W: Shift + Cmd + Left              # SGUI(KC_LEFT)
E: Ctrl + Shift + Alt + Cmd + Y    # HYPR(KC_Y)
```

- The order of the modifiers and the spaces around `+` are free
- Modifier names: `Shift` / `Ctrl` (`Control`) / `Alt` (`Option`) / `Cmd` (`Command`, `Gui`, `Win`). For the right side, `RShift` / `RCtrl` / `RAlt` / `RCmd` and so on
- **Left and right modifiers cannot be mixed** (`Shift + RCmd + A` is an error). Only basic keys can be modified
- `pull` writes modifiers in the order `Ctrl, Option, Shift, Command`, so settings written as `Cmd + Q` read back as `Command + Q` (the value is the same)

## YAML pitfalls

YAML decides the type of unquoted values automatically, so **always quote** the following:

| What you want | Correct form | Without quotes |
|---|---|---|
| The digit key `1` | `"1"` | read **without an error** as the keycode value 0x0001 (= `Trans`) |
| A lone `!` | `"!"` | read **without an error** as empty (unassigned) |
| Symbol keys such as `[` `]` `-` | `"["` | a YAML syntax error |
| `yes` `no` `on` `off` | quote them | become booleans (validate reports them with how to rewrite them) |

When the symbol is in the middle of a string, as in `Command + Shift + [`, quotes are not needed.
Inside a one-line mapping such as `{ push: ..., ccw: ... }`, however, quote values that contain `[`, `]`, `,` and the like.
Mistakes with digits and `!` are not caught by validate, so check the differences with `cornix status` before writing.

## Validating the settings

```bash
cornix validate
```

```
✗ Validation failed:
  Error: layers/1_symbol.yaml: mapping.left_hand.row0.tab: キーコード「Spce」を解釈できません: 「Spce」は不明なキーコードです
  Error: layers/1_symbol.yaml: mapping.left_hand.row1.capz: position_map の left_hand.row1 にないキーです（使えるキー: caps, A, S, D, F, G）
```

(The messages say the keycode "Spce" is unknown, and `capz` is not a key in `left_hand.row1` of the position map.)

- Problems are collected without stopping and shown as "file: location: message" (exit code 1). Fixing mistakes in the shape of groups or files can reveal more. `status` / `apply` run the same checks first
- The file format (YAML syntax, fields, keycodes, key names, number ranges) is checked first; once that passes, the whole setup (limits, duplicate numbers and names, reference targets, layer numbers) is checked
- Limits: 10 layers, 32 macros, 32 tap dances, 32 combos, 4 trigger keys per combo
- If there are only warnings (`⚠  Warning: …`), it continues

## Naming (`rename`)

```bash
cornix rename
```

Claude reads the macros, tap dances, combos and layers that still have default names (`Macro N`, `TapDance N`, `Combo N`, `Layer N`) and suggests names, descriptions and file names.
For each one you choose `Y` (accept) / `n` (skip) / `e` (edit); it then takes a backup (such as `profiles/default.backup_<timestamp>/`), applies them all at once,
and updates references by name such as `Macro('old name')` (references by number such as `Macro(3)` / `TD(2)` and the numbers in file names are not changed). It checks that the settings' values did not change, and rolls back if they did.

Without `claude`, you can name them by hand with `ruby bin/rename_file --config-dir profiles/default ...` (see `ruby bin/rename_file --help`).

## Backups and restoring

Before writing, `apply` and `restore` save the keyboard's state as a timestamped .vil (such as `20261019-010203.vil`) in `<tmp>/device_backups/`.
`<tmp>` is the working directory of each settings directory: `tmp/profiles/default/` for `profiles/default/` (`tmp/` is not tracked by Git).

```bash
cornix restore                       # go back to the newest backup (usually the state before the last apply)
cornix restore 20261019-010203       # go back to the given backup (a file name or a path)
```

- It shows the differences from the target and writes after confirmation. A backup taken with `cornix device backup` also counts as the newest backup
- `restore` also backs up the current state before writing, so running `restore` again right away returns to the state before the restore
- `restore` only changes the keyboard. Use Git to restore the settings files

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

When settings other than `config/` are in use, `validate` / `pull` / `status` / `apply` / `restore` and others show them on the first line, as in "設定: profiles/default（.cornix.yml）" ("Settings: profiles/default (.cornix.yml)").
One repository can hold several settings (for example `profiles/work/` and `profiles/game/`). Switch by editing `.cornix.yml`, or add `--profile`.

### What `init` creates

```bash
cornix init [DIR] [--profile NAME | --config DIR] [--from FILE] [--no-pull]
```

- In `DIR` (default: `--root`, otherwise the current directory) it creates `profiles/NAME/` with `--profile NAME`, the given place with `--config`, and `profiles/default/` otherwise. Names may use letters, digits and `. _ -` (starting with a letter or digit)
- It writes a `.cornix.yml` so that later commands use the new settings. An existing one is left unchanged
- Where there is no `.cornix.yml` but a non-empty `config/`, `cornix init` without options creates nothing and stops, so that the settings in use don't change silently (add `--profile NAME` or `--config DIR`)
- When it creates settings outside this repository, it adds the lines `tmp/` and `.decompile.lock` to `.gitignore`

This repository's `.gitignore` keeps `/.cornix.yml` and `/profiles/` out of Git (they are local settings). To manage your settings in a fork or a branch, delete those two lines.

### If you use the old `config/`

Without a `.cornix.yml`, `config/` is used as before, so nothing needs to change. To move to `profiles/`:

```bash
mkdir -p profiles && mv config profiles/default
echo "profile: default" > .cornix.yml
cornix validate          # the move worked if it shows "設定: profiles/default（.cornix.yml）"
```

Backups also move from `tmp/device_backups/` to `tmp/profiles/default/device_backups/`; copy them if you want to use earlier backups with `restore`.

### Ways to use it

**A. Fork it (recommended)**

```bash
# after forking this repository on GitHub
git clone <your fork> cornix-layout && cd cornix-layout
cornix init --profile <your name>
# after deleting the /.cornix.yml and /profiles/ lines from .gitignore
git add .gitignore profiles .cornix.yml && git commit -m "Add my settings"
git push
```

Upstream never changes what is inside `profiles/` or `.cornix.yml`, so you can take upstream updates with GitHub's "Sync fork" or `git pull upstream main`.

**B. Keep only the settings in a separate repository**

Clone the tool and put `cornix` on your PATH, and manage the settings in a different directory.

```bash
mkdir my-cornix && cd my-cornix && git init
cornix init                    # creates profiles/default/ and .cornix.yml, and adds tmp/ and .decompile.lock to .gitignore
cornix status                  # run in this directory (or below it)
```

### Sample settings

| Branch | Settings | Contents |
|---|---|---|
| `cornix-default-keymap` | `profiles/cornix-default/` | The standard Cornix layout |
| `authors-keymap` | `profiles/authors/` | The keymap the author actually uses, with examples of references by name, modifier expressions, combos and more |

Each is main with settings and a `.cornix.yml` on top. So that it does not clash with your own `.cornix.yml`, opening it in a separate directory is recommended.

```bash
git worktree add ../cornix-default-keymap cornix-default-keymap   # in a fork without it, fetch upstream and use upstream/cornix-default-keymap
cd ../cornix-default-keymap && cornix validate
```

## Editing on screen in VS Code

`editors/vscode/` has a VS Code extension that shows a whole settings directory on one screen and lets you edit every settings file while choosing from candidates.
It is not on the Marketplace: build a .vsix and install it yourself (the steps, in Japanese, are in [editors/vscode/README.md](editors/vscode/README.md)).
The extension talks only to `cornix serve` and never writes to the keyboard; run `status` / `apply` from the terminal as before.

Open it with the Cornix icon in the activity bar or the command "Cornix: プロファイルを開く" (Open profile). The upper half is a diagram of the keyboard and the lower half holds the editing panes; clicking a key moves to its field.

| File | What you can do on screen |
|---|---|
| `layers/` | Keys and encoders, notes, removing an assignment, the layer's name and description |
| `macros/` | Steps (add, delete, move up and down), the keys of tap / down / up, `delay`, `text`, `preset`, expanding a `preset` into steps |
| `tap_dance/` | The four actions and their notes, `tapping_term` |
| `combos/` | The keys pressed together (up to 4; can be picked from the diagram), the output key and its note |
| `shortcuts.yaml` | The values, copying a bundled shortcut |
| `settings/qmk_settings.yaml` | Each setting (with a description and the default value) |
| `position_map.yaml` | The key names (position names) |
| `metadata.yaml` | Shown read-only |

- **Key input**: candidates are searched by name, alias, QMK name, and the Japanese labels and app names of the bundled shortcuts. When nothing matches as a prefix or substring, entries that contain the typed characters in order (fuzzy matches; `lbr` → `[`) are listed below. Among equally good matches, the keys used most in the profile come first. "同梱から選ぶ…" (Choose from bundled) at the bottom of the candidate list lets you pick a bundled shortcut by app → category → label and enters `Shortcut('…')`. The builder next to the field puts together modifier expressions (`Shift + Command + P`), `LT(2, Escape)` and Mod-Tap (`RSFT_T(Up)`). A value is validated as soon as you enter it, and hovering shows what it means
- **The diagram**: the "位置の名前" (Position names) button above it (click to keep it on; temporarily while hovering over it or holding Alt) shows the position names in purple instead of the assignments. The names come from `position_map.yaml`, and while they are shown you can click a key to change its name there. The "全レイヤー" (All layers) button lists each key's value on every layer as `number label` lines (lines for `Trans`, `NoKey` and unwritten positions are left out). A `Trans` key faintly shows the layer 0 key at the same position. Arrow keys are shown as `↑` `←` `→` `↓`. Macros get an orange `M`, your own shortcuts a `★`, and bundled shortcuts the app's icon. A position with no assignment looks like `NoKey`: an outline with nothing inside
- **Combos**: while a combo's number button above the diagram is pressed (kept on) or hovered (temporary), the trigger keys of that combo are highlighted on the current layer. A combo that cannot be pressed (no layer has all of its trigger keys) gets a ⚠. "図から選ぶ" (Pick from diagram) in the combos section adds a trigger by clicking a key in the diagram
- **Sections**: the sections other than layers (macros, tap dances, combos, shortcuts, QMK settings) start collapsed (`▶` / `▼`)
- **Removing an assignment**: ✕ next to a field deletes that line from the YAML. A position with no assignment is written as `NoKey` (see [Layers](#layers))
- **Saving**: changes stay unsaved until Cmd+S (Ctrl+S), and undo works. Saving rewrites only the changed values and keeps comments and order. If Claude or another tool changes the files while they are open, the screen reloads when nothing is unsaved, and otherwise asks which side to keep
- **Adding, deleting and renaming**: macros, tap dances, combos and shortcuts can be added, deleted and renamed (layers can be renamed) from the screen. These are written to the files right after a confirmation dialog (if there are unsaved changes, you are asked to save them first). Renaming also rewrites references such as `Macro('old name')` in every file and the file name, and stops if the compile result would change. Deleting leaves references as they are; the dialog shows how many there are, and the referring side shows an error
- **Copying bundled shortcuts and expanding presets**: "同梱からコピー" (Copy from bundled) in the shortcuts section adds the chosen bundled shortcut to `shortcuts.yaml` (named after its label; existing references are left as they are). "手順に展開" (Expand into steps) on a macro replaces its `preset:` line with the steps of the bundled definition. Both are written right after a confirmation dialog, and expanding stops if the compile result would change
- **Text editor**: when you open a settings file as text, the same validation results appear as squiggles

## Using it as an MCP server

`cornix mcp` runs an MCP (Model Context Protocol) server over standard input and output.

- **Claude Code**: it is already registered as `cornix-device` in `.mcp.json` at the repository root. Open Claude Code in this directory and allow it when asked the first time
- **Other clients** (such as Claude Desktop): register it with absolute paths as below. If `ruby` cannot be found (mise / rbenv and so on), put the absolute path of Ruby in `command`

```json
{
  "mcpServers": {
    "cornix-device": {
      "command": "ruby",
      "args": ["/path/to/cornix-layout/bin/cornix", "mcp", "--root", "/path/to/my-cornix"]
    }
  }
}
```

Point `--root` at the directory that contains `.cornix.yml` (this repository, if you keep your settings here).
If you keep the settings in a separate repository, run `claude mcp add cornix-device -- ruby /path/to/cornix-layout/bin/cornix mcp --root "$PWD"` in that directory to register it with Claude Code.

| Tool | Writes | Description |
|---|---|---|
| `keyboard_info` | No | Information about the keyboard |
| `read_keymap` | No | Returns or saves the current state in layout.vil format |
| `backup` / `list_backups` | No | Saves and lists backups |
| `apply_layout` | Only with `dry_run: false` | Writes a .vil (default: the output of `cornix compile`). A dry run by default, returning the differences and a `confirm_token`; writes only with `dry_run: false` and the `confirm_token` |
| `restore_backup` | Only with `dry_run: false` | Goes back to a backup, with the same two steps as `apply_layout` |

`apply_layout` writes the `<tmp>/build/layout.vil` last written by `cornix status` / `apply` (or `compile`). After changing the YAML, run `cornix status` first.
If the keyboard or the file changes after the review, the token no longer matches and the write is refused. Even when you let an AI assistant write, always ask it to show you the dry run result first.

## Safety mechanisms

The Cornix firmware (RMK 0.8 series) has almost no locks or range checks (entering the bootloader and resetting the EEPROM run without a lock, and out-of-range writes make it panic), so the tool does the following:

- **Allowlist of commands**: the HID bridge only sends commands on its allowlist. Entering the bootloader, resetting the EEPROM, erasing everything, and bulk keymap writes cannot be sent (check with `tmp/cornix-hid --self-test`)
- **Range checks**: keys are written one at a time, and layers, rows, columns, macro offsets and so on are all checked before sending
- **Keys that are never written**: boot keycodes such as `QK_BOOT` ([data/dangerous_keycodes.yaml](data/dangerous_keycodes.yaml)) are never written
- **Validate, confirm and back up before writing**: it stops if the settings have mistakes, shows the differences and asks, and saves the state just before writing
- **Write only the differences and verify**: only what changed is written, and finally the keyboard is read back and checked

Vial asks you to hold two keys (an unlock) when saving macros, but that is behavior of the Vial app, not something the firmware checks. This tool needs no unlock.

## Troubleshooting

### The keyboard cannot be found

```
エラー: Cornix が見つかりません。Mac と Bluetooth（または USB）で接続されているか、スリープしていないか、別の機器に接続先が切り替わっていないかを確認してください
```

(The message says the Cornix was not found, and asks you to check that it is connected to the Mac over Bluetooth (or USB), is not asleep, and has not switched to another device.)

- Press a key once to wake it, or check the connection to the Mac, and run the command again
- If the keyboard has switched to another device (BT1 / BT2, ...), the Mac cannot see it. Switch to the channel connected to the Mac
- If the connection drops midway, it stops with "キーボードから応答がありません" ("no response from the keyboard"). If it was writing, it shows how many items were written and where the backup is; reconnect and run `cornix apply` again, or go back with `cornix restore` (both write only the differences)

### Common validation errors

| Message | Fix |
|---|---|
| `キーコード「Spce」を解釈できません` (cannot interpret keycode) | Fix the spelling (`Space`). Candidates are shown after 「もしかして」 ("did you mean") |
| `position_map の left_hand.row1 にないキーです` (not a key in the position map) | Use a name that exists in `position_map.yaml` |
| `マクロ「Unknown」が見つかりません` (macro not found) | Match the reference to the `name` in the macro file |
| `左右の修飾キーは混在できません` (left and right modifiers mixed) | Use modifiers from one side only |
| `row2, row3, thumb_keys がありません` (groups missing) | List every group of each hand (empty is fine) |

## Using Vial (compile / decompile)

Instead of writing to the keyboard directly, you can also read and write `layout.vil` with Vial (Web / GUI). Use this on systems other than macOS.

```bash
cornix init --from ~/Downloads/layout.vil   # create the settings from a layout.vil saved with Vial's File > Export Layout
cornix compile                              # validate, then write <tmp>/build/layout.vil (-o FILE to choose the output)
# load <tmp>/build/layout.vil with Vial's File > Import Layout
```

| Command | Description |
|---|---|
| `compile [-o FILE]` | Validates the settings and writes a .vil (default `<tmp>/build/layout.vil`). `status` / `apply` do this internally |
| `decompile [FILE]` | Turns a layout.vil into YAML in the current settings directory (default `<tmp>/layout.vil`). Stops if there are settings already (same as [When `pull` stops](#when-pull-stops)) |
| `cleanup [-f]` | Deletes the settings directory and the compile output. With the `.decompile.lock` that init / decompile create, it needs `-f` (and a confirmation) |

decompile → compile reproduces the original 16-bit values, so you can bring over a setup made in Vial as it is.

## For developers

```bash
bundle install                              # gems for the tests (RSpec)
LANG=ja_JP.UTF-8 bundle exec rspec          # all tests (no keyboard needed)
```

- Design (in Japanese): [docs/architecture.md](docs/architecture.md) (layers, dependency direction, data flow, coding conventions) and [docs/tasks.md](docs/tasks.md) (public methods of the main classes). The test layout is in [spec/README.md](spec/README.md)
- Development rules are in [.claude/CLAUDE.md](.claude/CLAUDE.md). When you change the README, change both README.md (English) and README.ja.md (Japanese) in the same commit (`spec/docs/readme_sync_spec.rb` checks their structure)
- To check that decompile → compile gives back your own layout.vil:

```bash
rm -rf /tmp/cornix-roundtrip
cornix init /tmp/cornix-roundtrip --from ~/Downloads/layout.vil
cornix compile --root /tmp/cornix-roundtrip
ruby bin/diff_layouts ~/Downloads/layout.vil /tmp/cornix-roundtrip/tmp/profiles/default/build/layout.vil
# expected: === ✓ FILES ARE IDENTICAL ===
```

## Notes

- This tool is not an official Cornix product and is not affiliated with its makers. A firmware update may change the protocol
- The author accepts no responsibility for problems caused by using this tool. Keep a copy of important settings, for example with `cornix device backup`
- License: [MIT License](LICENSE). You may freely modify and redistribute it as long as you keep the copyright and license notice; it comes with no warranty
- References: [Vial Documentation](https://get.vial.today/), [QMK Keycodes](https://docs.qmk.fm/keycodes_basic)
