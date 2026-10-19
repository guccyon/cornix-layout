// 偽のサーバーが返すデータ。protocol.md の例を元に、spec/fixtures/authors_config の Base と Symbols のレイヤーを写した。
// 16bit 値や表示の文字はそれらしい値で、Ruby のサーバーの結果と一致するとは限らない（画面を作るための仮のデータ）。
import type {
  Candidate,
  EncoderBinding,
  KeyValue,
  LayerKey,
  LayerSnapshot,
  PositionMapEntry,
  ProfileReferences,
  QmkSettingSnapshot,
  ShortcutTreeResult,
} from '../../src/protocol';

export const SERVER_VERSION = '1.0.0';

/** snapshot の files に入れるもの（ディスクに設定ディレクトリがないとき） */
export const FALLBACK_FILES = [
  'metadata.yaml',
  'position_map.yaml',
  'layers/0_base.yml',
  'layers/1_symbols.yml',
  'settings/qmk_settings.yaml',
];

export const METADATA = { keyboard: 'cornix', version: 1, vial_protocol: 6, via_protocol: 9 };

// ---------------------------------------------------------------------------
// キーの解釈の表（表記 → KeyValue）。候補・inspect・validate もこれを使う
// ---------------------------------------------------------------------------

type KeyInfo = Omit<KeyValue, 'text'>;

const basic = (canonical: string, code: number, label = canonical): KeyInfo => ({
  canonical,
  code,
  kind: 'basic',
  display: { label },
});

const KEYS: Record<string, KeyInfo> = {
  Escape: basic('Escape', 41, 'Esc'),
  Enter: basic('Enter', 40, '⏎'),
  Space: basic('Space', 44),
  Tab: basic('Tab', 43, '⇥'),
  Backspace: basic('Backspace', 42, '⌫'),
  CapsLock: basic('CapsLock', 57, 'Caps'),
  '-': basic('Minus', 45, '-'),
  Minus: basic('Minus', 45, '-'),
  ',': basic('Comma', 54, ','),
  Comma: basic('Comma', 54, ','),
  '.': basic('Dot', 55, '.'),
  Dot: basic('Dot', 55, '.'),
  Up: basic('Up', 82, '↑'),
  Down: basic('Down', 81, '↓'),
  Left: basic('Left', 80, '←'),
  Right: basic('Right', 79, '→'),
  LBracket: basic('LBracket', 47, '['),
  RBracket: basic('RBracket', 48, ']'),
  LCtrl: basic('LCtrl', 224, '⌃'),
  LShift: basic('LShift', 225, '⇧'),
  LAlt: basic('LAlt', 226, '⌥'),
  LGui: basic('LGui', 227, '⌘'),
  Cmd: basic('LGui', 227, '⌘'),
  RShift: basic('RShift', 229, '⇧'),
  Mute: basic('Mute', 168),
  VolumeUp: basic('VolumeUp', 169, 'Vol+'),
  VolumeDown: basic('VolumeDown', 170, 'Vol-'),
  MouseWheelUp: basic('MouseWheelUp', 217, 'Wheel↑'),
  MouseWheelDown: basic('MouseWheelDown', 218, 'Wheel↓'),
  Question: { canonical: 'Question', code: 0x0238, kind: 'modified', display: { label: '?' } },
  '@': { canonical: 'At', code: 0x021f, kind: 'modified', display: { label: '@' } },
  Trans: { canonical: 'Trans', code: 1, kind: 'transparent', display: { label: '▽' } },
  NoKey: { canonical: 'NoKey', code: 0, kind: 'noKey', display: { label: '' } },
  Repeat: { canonical: 'Repeat', code: 0x7c79, kind: 'quantum', display: { label: 'Repeat' } },
  'MO(1)': { canonical: 'MO(1)', code: 0x5221, kind: 'layerAction', display: { label: 'MO(1)', hold: 'L1' } },
  'MO(2)': { canonical: 'MO(2)', code: 0x5222, kind: 'layerAction', display: { label: 'MO(2)', hold: 'L2' } },
  'MO(3)': { canonical: 'MO(3)', code: 0x5223, kind: 'layerAction', display: { label: 'MO(3)', hold: 'L3' } },
  'TG(3)': { canonical: 'TG(3)', code: 0x5263, kind: 'layerAction', display: { label: 'TG(3)' } },
  'LT1(Space)': {
    canonical: 'LT1(Space)',
    code: 16684,
    kind: 'layerTap',
    display: { label: 'Space', tap: 'Space', hold: 'L1' },
  },
  'LT2(KC_LANG1)': {
    canonical: 'LT2(Lang1)',
    code: 0x4290,
    kind: 'layerTap',
    display: { label: 'かな', tap: 'かな', hold: 'L2' },
  },
  'LGUI_T(KC_LANG2)': {
    canonical: 'LGUI_T(Lang2)',
    code: 0x2891,
    kind: 'modTap',
    display: { label: '英数', tap: '英数', hold: '⌘' },
  },
  "TapDance('Tab Escape')": {
    canonical: "TapDance('Tab Escape')",
    code: 0x5704,
    kind: 'tapDance',
    display: { label: 'Tab Escape' },
  },
  "TapDance('Layer 3 Toggle')": {
    canonical: "TapDance('Layer 3 Toggle')",
    code: 0x5703,
    kind: 'tapDance',
    display: { label: 'Layer 3 Toggle' },
  },
  "Macro('Bracket Pair')": {
    canonical: "Macro('Bracket Pair')",
    code: 30464,
    kind: 'macro',
    display: { label: 'Bracket Pair' },
  },
  "Shortcut('前のタブへ')": {
    canonical: 'Shift + Command + [',
    code: 0x0a2f,
    kind: 'modified',
    origin: 'shortcut',
    display: { label: '⇧⌘[' },
  },
  "Shortcut('VS Code:基本操作:コマンドパレット')": {
    canonical: 'Shift + Command + P',
    code: 0x0a13,
    kind: 'modified',
    origin: 'presetShortcut',
    icon: 'material-icon-theme:vscode',
    display: { label: '⇧⌘P' },
  },
  'Shift + Command + P': {
    canonical: 'Shift + Command + P',
    code: 0x0a13,
    kind: 'modified',
    display: { label: '⇧⌘P' },
  },
};

for (const letter of 'ABCDEFGHIJKLMNOPQRSTUVWXYZ') {
  KEYS[letter] = basic(letter, 4 + letter.charCodeAt(0) - 'A'.charCodeAt(0));
}

/** 表記を解釈する。知らない表記なら null（0x で始まる 16 進は raw として読む） */
export function interpret(text: string): KeyValue | null {
  const info = KEYS[text] ?? KEYS[Object.keys(KEYS).find((key) => key.toLowerCase() === text.toLowerCase()) ?? ''];
  if (info) return { text, ...info };
  const raw = /^0x([0-9a-f]{1,4})$/i.exec(text);
  if (raw?.[1]) {
    return { text, canonical: `0x${raw[1].toUpperCase().padStart(4, '0')}`, code: parseInt(raw[1], 16), kind: 'raw', display: { label: text } };
  }
  return null;
}

// ---------------------------------------------------------------------------
// position_map とレイヤー
// ---------------------------------------------------------------------------

const POSITION_GROUPS: Record<'left' | 'right', [string, string[]][]> = {
  left: [
    ['row0', ['tab', 'Q', 'W', 'E', 'R', 'T']],
    ['row1', ['lctrl', 'A', 'S', 'D', 'F', 'G']],
    ['row2', ['lshift', 'Z', 'X', 'C', 'V', 'B']],
    ['row3', ['caps', 'fn', 'option']],
    ['thumb_keys', ['left', 'middle', 'right']],
  ],
  right: [
    ['row0', ['Y', 'U', 'I', 'O', 'P', 'backspace']],
    ['row1', ['H', 'J', 'K', 'L', 'colon', 'enter']],
    ['row2', ['N', 'M', 'comma', 'dot', 'up', 'rshift']],
    ['row3', ['left', 'down', 'right']],
    ['thumb_keys', ['left', 'middle', 'right']],
  ],
};

export const POSITION_MAP: PositionMapEntry[] = (['left', 'right'] as const).flatMap((hand) =>
  POSITION_GROUPS[hand].flatMap(([group, symbols]) =>
    symbols.map((symbol, i) => ({
      hand,
      row: group === 'thumb_keys' ? 3 : Number(group.slice(3)),
      col: group === 'thumb_keys' ? 3 + i : i,
      group,
      symbol,
    })),
  ),
);

type LayerSource = {
  index: number;
  name: string;
  description: string;
  file: string;
  /** "left.row0.tab" → 表記 */
  keys: Record<string, string>;
  notes?: Record<string, string>;
  encoders?: Record<string, string>;
};

const LAYER_SOURCES: LayerSource[] = [
  {
    index: 0,
    name: 'Base',
    description: 'Base layer with standard QWERTY layout and layer switching',
    file: 'layers/0_base.yml',
    keys: {
      'left.row0.tab': "TapDance('Tab Escape')",
      ...letters('left', 'row0', 'QWERT'),
      'left.row1.lctrl': 'LCtrl',
      ...letters('left', 'row1', 'ASDFG'),
      'left.row2.lshift': 'LShift',
      ...letters('left', 'row2', 'ZXCV'),
      'left.row2.B': "Macro('Bracket Pair')",
      'left.row3.caps': 'CapsLock',
      'left.row3.fn': 'MO(3)',
      'left.row3.option': 'LAlt',
      'left.thumb_keys.left': 'LGUI_T(KC_LANG2)',
      'left.thumb_keys.middle': 'LT1(Space)',
      'left.thumb_keys.right': 'MO(2)',
      'right.row0.Y': "Shortcut('VS Code:基本操作:コマンドパレット')",
      ...letters('right', 'row0', 'UIOP'),
      'right.row0.backspace': 'Backspace',
      ...letters('right', 'row1', 'HJKL'),
      'right.row1.colon': '-',
      'right.row1.enter': 'Enter',
      ...letters('right', 'row2', 'NM'),
      'right.row2.comma': ',',
      'right.row2.dot': '.',
      'right.row2.up': 'Up',
      'right.row2.rshift': 'RShift',
      'right.row3.left': 'Left',
      'right.row3.down': 'Down',
      'right.row3.right': 'Right',
      'right.thumb_keys.left': 'MO(3)',
      'right.thumb_keys.middle': 'MO(1)',
      'right.thumb_keys.right': 'LT2(KC_LANG1)',
    },
    notes: { 'left.thumb_keys.left': 'タップで英数、押している間は Command' },
    encoders: {
      'left.push': 'Mute',
      'left.ccw': 'VolumeDown',
      'left.cw': 'VolumeUp',
      'right.push': "TapDance('Layer 3 Toggle')",
      'right.ccw': 'Up',
      'right.cw': 'Down',
    },
  },
  {
    index: 1,
    name: 'Symbols',
    description: '記号レイヤー\n記号はそれぞれ英名の頭文字に対応する文字キーに配置',
    file: 'layers/1_symbols.yml',
    keys: {
      'left.row0.tab': 'Escape',
      'left.row0.Q': 'Question',
      'left.row0.R': 'NoKey',
      'left.row1.lctrl': 'Trans',
      'left.row1.A': '@',
      'left.thumb_keys.middle': 'Space',
      'right.row1.K': 'LBracket',
      'right.row1.L': 'RBracket',
      'right.row0.Y': "Shortcut('前のタブへ')",
    },
    encoders: { 'left.ccw': 'VolumeDown', 'left.cw': 'VolumeUp' },
  },
];

function letters(hand: string, group: string, chars: string): Record<string, string> {
  return Object.fromEntries([...chars].map((c) => [`${hand}.${group}.${c}`, c]));
}

function handKey(hand: 'left' | 'right'): string {
  return hand === 'left' ? 'left_hand' : 'right_hand';
}

function buildLayer(source: LayerSource): LayerSnapshot {
  const keys: LayerKey[] = POSITION_MAP.map((entry) => {
    const id = `${entry.hand}.${entry.group}.${entry.symbol}`;
    const text = source.keys[id];
    let value = text === undefined ? null : interpret(text);
    const note = source.notes?.[id];
    if (value && note) value = { ...value, note };
    return {
      hand: entry.hand,
      row: entry.row,
      col: entry.col,
      address: { file: source.file, path: ['mapping', handKey(entry.hand), entry.group, entry.symbol] },
      value,
    };
  });
  const encoder = (side: 'left' | 'right'): EncoderBinding => {
    const action = (op: 'push' | 'ccw' | 'cw') => {
      const text = source.encoders?.[`${side}.${op}`];
      return {
        address: { file: source.file, path: ['mapping', 'encoders', side, op] },
        value: text === undefined ? null : interpret(text),
      };
    };
    return { push: action('push'), ccw: action('ccw'), cw: action('cw') };
  };
  return {
    index: source.index,
    name: source.name,
    description: source.description,
    file: source.file,
    keys,
    encoders: { left: encoder('left'), right: encoder('right') },
  };
}

export const LAYERS: LayerSnapshot[] = LAYER_SOURCES.map(buildLayer);

export const SETTINGS: QmkSettingSnapshot[] = (
  [
    ['vial', 'combo_timing_window', 'integer', 50, null, null],
    ['keyboard', 'oneshot_timeout', 'integer', 1000, null, null],
    ['keyboard', 'tapping_term', 'integer', 180, 200, 'タップとホールドを分ける時間（ミリ秒）'],
    ['keyboard', 'tap_code_delay', 'integer', 20, null, null],
    ['keyboard', 'tap_hold_caps_delay', 'integer', 20, null, null],
    ['keyboard', 'permissive_hold', 'boolean', false, false, 'ほかのキーを押して離したらホールドとみなす'],
    ['keyboard', 'hold_on_other_key_press', 'boolean', true, null, null],
    ['keyboard', 'chordal_hold', 'boolean', true, null, null],
    ['keyboard', 'flow_tap', 'integer', null, null, null],
  ] as const
).map(([group, name, type, value, defaultValue, description]) => ({
  group,
  name,
  type,
  value,
  default: defaultValue,
  description,
  address: { file: 'settings/qmk_settings.yaml', path: [group, name] },
}));

export const REFERENCES: ProfileReferences = {
  layers: [
    { index: 0, name: 'Base' },
    { index: 1, name: 'Symbols' },
  ],
  macros: [
    { index: 0, name: 'Bracket Pair', icon: null },
    { index: 1, name: 'Curly Brace Pair', icon: null },
    { index: 2, name: 'Copy Selected', icon: 'material-icon-theme:vscode' },
  ],
  tapDances: [
    { index: 3, name: 'Layer 3 Toggle' },
    { index: 4, name: 'Tab Escape' },
  ],
  shortcuts: [{ name: '前のタブへ', text: 'Command + Shift + [' }],
};

// ---------------------------------------------------------------------------
// 候補と同梱のショートカット
// ---------------------------------------------------------------------------

export const CANDIDATES: Candidate[] = [
  ...'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.split('').map((c): Candidate => ({ insertText: c, label: c, detail: `KC_${c}`, category: 'basic' })),
  { insertText: 'Escape', label: 'Escape', detail: 'Esc · KC_ESCAPE', category: 'basic' },
  { insertText: 'Enter', label: 'Enter', detail: 'Return · KC_ENTER', category: 'basic' },
  { insertText: 'Space', label: 'Space', detail: 'KC_SPACE', category: 'basic' },
  { insertText: 'Tab', label: 'Tab', detail: 'KC_TAB', category: 'basic' },
  { insertText: 'Backspace', label: 'Backspace', detail: 'KC_BACKSPACE', category: 'basic' },
  { insertText: 'LGui', label: 'LGui', detail: 'Cmd · Command · KC_LGUI', category: 'modifier' },
  { insertText: 'LShift', label: 'LShift', detail: 'Shift · KC_LSHIFT', category: 'modifier' },
  { insertText: 'LCtrl', label: 'LCtrl', detail: 'Ctrl · Control · KC_LCTRL', category: 'modifier' },
  { insertText: 'LAlt', label: 'LAlt', detail: 'Option · Alt · KC_LALT', category: 'modifier' },
  { insertText: 'VolumeUp', label: 'VolumeUp', detail: 'KC_AUDIO_VOL_UP', category: 'media' },
  { insertText: 'VolumeDown', label: 'VolumeDown', detail: 'KC_AUDIO_VOL_DOWN', category: 'media' },
  { insertText: 'Mute', label: 'Mute', detail: 'KC_AUDIO_MUTE', category: 'media' },
  { insertText: 'MouseWheelUp', label: 'MouseWheelUp', detail: 'KC_MS_WH_UP', category: 'mouse' },
  { insertText: 'MouseWheelDown', label: 'MouseWheelDown', detail: 'KC_MS_WH_DOWN', category: 'mouse' },
  { insertText: 'MO(1)', label: 'MO(1)', detail: 'Symbols', category: 'layer' },
  { insertText: 'MO(2)', label: 'MO(2)', detail: '', category: 'layer' },
  { insertText: 'TG(3)', label: 'TG(3)', detail: '', category: 'layer' },
  { insertText: "Macro('Bracket Pair')", label: 'Bracket Pair', detail: 'M0', category: 'macro' },
  { insertText: "TapDance('Tab Escape')", label: 'Tab Escape', detail: 'TD4', category: 'tapDance' },
  { insertText: "Shortcut('前のタブへ')", label: '前のタブへ', detail: 'Command + Shift + [', category: 'shortcut' },
  {
    insertText: "Shortcut('VS Code:基本操作:コマンドパレット')",
    label: 'コマンドパレット',
    detail: 'VS Code › 基本操作 · Shift + Command + P',
    category: 'presetShortcut',
    icon: 'material-icon-theme:vscode',
  },
  { insertText: 'Trans', label: 'Trans', detail: '下のレイヤーのキー · KC_TRNS', category: 'special' },
  { insertText: 'NoKey', label: 'NoKey', detail: '何もしない · KC_NO', category: 'special' },
  {
    insertText: 'Repeat',
    label: 'Repeat',
    detail: 'QK_REPEAT_KEY',
    category: 'special',
    warning: 'Cornix は Repeat Key に対応していません',
  },
];

export const SHORTCUT_TREE: ShortcutTreeResult = {
  apps: [
    {
      name: 'VS Code',
      icon: 'material-icon-theme:vscode',
      categories: [
        {
          name: '基本操作',
          items: [
            {
              label: 'コマンドパレット',
              insertText: "Shortcut('VS Code:基本操作:コマンドパレット')",
              text: 'Shift + Command + P',
              macro: false,
            },
            { label: 'キーボードショートカット', insertText: 'VS Code:基本操作:キーボードショートカット', macro: true },
          ],
        },
      ],
    },
    {
      name: 'Figma',
      icon: 'simple-icons:figma',
      categories: [
        {
          name: 'ツール',
          items: [{ label: 'フレーム', insertText: "Shortcut('Figma:ツール:フレーム')", text: 'F', macro: false }],
        },
      ],
    },
  ],
};

/** マウスを載せたときの説明 */
export function describe(value: KeyValue): { title: string; lines: string[] } {
  const code = value.code === null ? [] : [`16bit 値: 0x${value.code.toString(16).toUpperCase().padStart(4, '0')}`];
  if (value.kind === 'macro') {
    return { title: 'マクロ Bracket Pair（M0）', lines: ['角括弧ペア [] を挿入してカーソルを内側に配置', 'tap: [ ] ←', ...code] };
  }
  if (value.origin === 'presetShortcut' || value.origin === 'shortcut') {
    return { title: `ショートカット ${value.text}`, lines: [value.canonical, ...code] };
  }
  return { title: value.canonical, lines: code };
}
