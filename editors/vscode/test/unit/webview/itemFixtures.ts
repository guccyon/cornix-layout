// 中身の画面（マクロ・タップダンス・コンボ・ショートカット）のテスト用の snapshot の項目（protocol.md の 12.2 の形）。
import type { Address, ComboSnapshot, KeySlot, KeyValue, MacroSnapshot, ShortcutSnapshot, TapDanceSnapshot } from '../../../src/protocol';
import * as data from '../../fake-server/fixtures';

export function kv(text: string): KeyValue {
  return data.interpret(text) ?? { text, canonical: text, code: null, kind: 'basic', display: { label: text } };
}

const at = (file: string, ...path: (string | number)[]): Address => ({ file, path });
const slot = (address: Address, text: string | null): KeySlot => ({ address, value: text === null ? null : kv(text) });

export const MACRO_FILE = 'macros/00_bracket_pair.yml';
export const PRESET_FILE = 'macros/02_copy_selected.yml';
export const TAP_DANCE_FILE = 'tap_dance/04_tab_escape.yml';
export const COMBO_FILE = 'combos/00_left_bracket.yml';
export const SHORTCUTS_FILE = 'shortcuts.yaml';

/** 手順: tap [A, B]・delay 100・text "hi"・tap Escape（1 つの値で書いた keys） */
export const MACRO: MacroSnapshot = {
  index: 0,
  name: 'Bracket Pair',
  description: '角括弧ペア',
  file: MACRO_FILE,
  descriptionAddress: at(MACRO_FILE, 'description'),
  icon: null,
  preset: null,
  presetAddress: null,
  summary: ['tap: A B', 'delay: 100ms', 'text: hi', 'tap: Escape'],
  steps: [
    {
      address: at(MACRO_FILE, 'sequence', 0),
      action: 'tap',
      keysAddress: at(MACRO_FILE, 'sequence', 0, 'keys'),
      keys: [slot(at(MACRO_FILE, 'sequence', 0, 'keys', 0), 'A'), slot(at(MACRO_FILE, 'sequence', 0, 'keys', 1), 'B')],
    },
    { address: at(MACRO_FILE, 'sequence', 1), action: 'delay', duration: { address: at(MACRO_FILE, 'sequence', 1, 'duration'), value: 100 } },
    { address: at(MACRO_FILE, 'sequence', 2), action: 'text', content: { address: at(MACRO_FILE, 'sequence', 2, 'content'), value: 'hi' } },
    {
      address: at(MACRO_FILE, 'sequence', 3),
      action: 'tap',
      keysAddress: at(MACRO_FILE, 'sequence', 3, 'keys'),
      keys: [slot(at(MACRO_FILE, 'sequence', 3, 'keys'), 'Escape')],
    },
  ],
};

export const PRESET_MACRO: MacroSnapshot = {
  index: 2,
  name: 'Copy Selected',
  description: null,
  file: PRESET_FILE,
  descriptionAddress: at(PRESET_FILE, 'description'),
  icon: 'material-icon-theme:vscode',
  preset: 'VS Code:編集:選択をコピー',
  presetAddress: at(PRESET_FILE, 'preset'),
  summary: ['tap: ⌘C', 'delay: 50ms'],
  steps: [],
};

export const TAP_DANCE: TapDanceSnapshot = {
  index: 4,
  name: 'Tab Escape',
  description: null,
  file: TAP_DANCE_FILE,
  descriptionAddress: at(TAP_DANCE_FILE, 'description'),
  actions: {
    tap: slot(at(TAP_DANCE_FILE, 'actions', 'on_tap'), 'Tab'),
    hold: slot(at(TAP_DANCE_FILE, 'actions', 'on_hold'), 'Escape'),
    doubleTap: slot(at(TAP_DANCE_FILE, 'actions', 'on_double_tap'), null),
    tapHold: slot(at(TAP_DANCE_FILE, 'actions', 'on_tap_hold'), null),
  },
  tappingTerm: { address: at(TAP_DANCE_FILE, 'tapping_term'), value: 200 },
};

export const COMBO: ComboSnapshot = {
  index: 0,
  name: 'Left Bracket',
  description: null,
  file: COMBO_FILE,
  descriptionAddress: at(COMBO_FILE, 'description'),
  triggersAddress: at(COMBO_FILE, 'trigger_keys'),
  triggers: [slot(at(COMBO_FILE, 'trigger_keys', 0), 'Q'), slot(at(COMBO_FILE, 'trigger_keys', 1), 'W')],
  output: slot(at(COMBO_FILE, 'output_key'), "Macro('Bracket Pair')"),
};

export const SHORTCUTS: ShortcutSnapshot[] = [
  { name: '前のタブへ', address: at(SHORTCUTS_FILE, 'shortcuts', '前のタブへ'), value: kv('Command + Shift + [') },
  { name: '次のタブへ', address: at(SHORTCUTS_FILE, 'shortcuts', '次のタブへ'), value: kv('Command + Shift + ]') },
];

export { at };
