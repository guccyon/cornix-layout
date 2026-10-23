// マクロ・タップダンス・コンボ・ショートカットの画面に描くものを、snapshot と未保存の変更から組み立てる（DOM に依存しない）。
//
// 未保存の変更（ホストの pending。protocol.md の 12.3）は当てる順に並んでいて、並び（sequence・keys・trigger_keys）の中を指す
// Address は「それより前の変更を当てたあとの位置」で数える。ここでは snapshot の並びを写した作業用の並びに、変更を順に当てて、
// 画面に描く並び（各要素の今の Address・保存済みの値・今の表記・変えた印）を作る。並びの中を指さない値（説明・tapping_term・
// タップダンスの動作・コンボの出すキー・ショートカットの値・preset）は、同じ Address の最後の変更だけが効く。
import type {
  Address,
  AnyChange,
  Change,
  ComboSnapshot,
  Diagnostic,
  KeySlot,
  KeyValue,
  MacroSnapshot,
  MacroStepSnapshot,
  MacroStepValue,
  ProfileSnapshot,
  ShortcutSnapshot,
  TapDanceSnapshot,
  ValueSlot,
} from '../protocol';
import { addressKey } from './model';

/** キーの欄 1 つ（今の Address に書く） */
export type KeyEntry = {
  address: Address;
  /** 保存済みの値（足した要素・保存済みの値がなければ null） */
  saved: KeyValue | null;
  /** 今の表記（書いていなければ空） */
  text: string;
  /** 足した・値を変えた・消した */
  changed: boolean;
  /** 今の注記（なければ空。注記を書けるのはタップダンスの動作とコンボの出すキーだけで、並びの要素ではいつも空） */
  note: string;
  /** 注記を変えた・消した */
  noteChanged: boolean;
};

/** 数値・文字の欄 1 つ */
export type ValueEntry<T> = {
  address: Address;
  saved: T | null;
  /** 今の値（消した・書いていなければ null） */
  value: T | null;
  changed: boolean;
};

/** キーの並び（マクロの手順のキー、コンボの同時に押すキー） */
export type KeyListView = {
  /** 並びの Address（insert / move の宛先） */
  address: Address;
  /** 1 つの値で書いている（keys: KC_A）。要素の Address は並びの Address と同じ */
  scalar: boolean;
  keys: KeyEntry[];
  /** 足した・消した・動かした要素がある */
  restructured: boolean;
};

export type StepView =
  | { action: 'tap' | 'down' | 'up'; address: Address; inserted: boolean; moved: boolean; changed: boolean; keys: KeyListView }
  | { action: 'delay'; address: Address; inserted: boolean; moved: boolean; changed: boolean; duration: ValueEntry<number> }
  | { action: 'text'; address: Address; inserted: boolean; moved: boolean; changed: boolean; content: ValueEntry<string> };

export type MacroView = {
  macro: MacroSnapshot;
  description: ValueEntry<string>;
  /** preset: で書いたマクロの preset の値（sequence で書いていれば null） */
  preset: ValueEntry<string> | null;
  /** 手順の並びの Address */
  stepsAddress: Address;
  steps: StepView[];
  /** 手順を足した・消した・動かした */
  restructured: boolean;
};

export type TapDanceActionName = 'tap' | 'hold' | 'doubleTap' | 'tapHold';
export const TAP_DANCE_ACTIONS: { name: TapDanceActionName; label: string }[] = [
  { name: 'tap', label: 'タップ' },
  { name: 'hold', label: 'ホールド' },
  { name: 'doubleTap', label: 'ダブルタップ' },
  { name: 'tapHold', label: 'タップホールド' },
];

export type TapDanceView = {
  tapDance: TapDanceSnapshot;
  description: ValueEntry<string>;
  actions: Record<TapDanceActionName, KeyEntry>;
  tappingTerm: ValueEntry<number>;
};

export type ComboView = {
  combo: ComboSnapshot;
  description: ValueEntry<string>;
  triggers: KeyListView;
  output: KeyEntry;
};

export type ShortcutView = { shortcut: ShortcutSnapshot; value: KeyEntry };

/** ホストが pending を送ればそれを、送らなければ（v0.1 のホスト）値の書き換えの並びを使う */
export function effectivePending(changes: Change[], pending: AnyChange[] | undefined): AnyChange[] {
  return pending ?? changes;
}

/** そのファイルに未保存の変更がある */
export function fileHasPending(pending: readonly AnyChange[], file: string): boolean {
  return pending.some((change) => change.address.file === file);
}

// ---------------------------------------------------------------------------
// 並びの中を指さない値（同じ Address の最後の変更だけ）
// ---------------------------------------------------------------------------

/** Address ごとの最後の変更。注記は noteKey の鍵で別に持つ（レイヤーの欄の slotEdits と同じ畳み方） */
type Overlay = Map<string, { op: 'set'; value: string | number | boolean } | { op: 'remove' }>;

function isNote(change: AnyChange): boolean {
  return (change.op === undefined || change.op === 'set' || change.op === 'remove') && change.field === 'note';
}

function noteKey(address: Address): string {
  return `note\u0000${addressKey(address)}`;
}

function setOverlay(overlay: Overlay, change: AnyChange): void {
  if (isNote(change)) {
    if (change.op === 'remove') overlay.set(noteKey(change.address), { op: 'remove' });
    else if (change.op === undefined || change.op === 'set') overlay.set(noteKey(change.address), { op: 'set', value: change.value });
    return;
  }
  if (change.op === undefined || change.op === 'set') overlay.set(addressKey(change.address), { op: 'set', value: change.value });
  else if (change.op === 'remove') {
    // 行ごと消すと注記も消える
    overlay.set(addressKey(change.address), { op: 'remove' });
    overlay.set(noteKey(change.address), { op: 'remove' });
  }
}

function overlayFor(pending: readonly AnyChange[], file: string): Overlay {
  const overlay: Overlay = new Map();
  for (const change of pending) if (change.address.file === file) setOverlay(overlay, change);
  return overlay;
}

function keyEntry(slot: KeySlot, overlay: Overlay): KeyEntry {
  const savedText = slot.value?.text ?? '';
  const entry = overlay.get(addressKey(slot.address));
  const text = entry === undefined ? savedText : entry.op === 'remove' ? '' : String(entry.value);
  const savedNote = slot.value?.note ?? '';
  const noteEntry = overlay.get(noteKey(slot.address));
  const note = noteEntry === undefined ? savedNote : noteEntry.op === 'remove' ? '' : String(noteEntry.value);
  return { address: slot.address, saved: slot.value, text, changed: text !== savedText, note, noteChanged: note !== savedNote };
}

function valueEntry<T extends string | number>(slot: ValueSlot<T>, overlay: Overlay, parse: (value: unknown) => T): ValueEntry<T> {
  const entry = overlay.get(addressKey(slot.address));
  const value = entry === undefined ? slot.value : entry.op === 'remove' ? null : parse(entry.value);
  return { address: slot.address, saved: slot.value, value, changed: value !== slot.value };
}

const asString = (value: unknown): string => String(value);
const asNumber = (value: unknown): number => (typeof value === 'number' ? value : Number(value));

// ---------------------------------------------------------------------------
// 並び（作業用の形に写して、変更を順に当て、最後に Address を振り直す）
// ---------------------------------------------------------------------------

type WorkKey = { saved: KeyValue | null; savedText: string | null; text: string };
type WorkKeyList = { scalar: boolean; keys: WorkKey[]; restructured: boolean };
type WorkStep = {
  action: MacroStepSnapshot['action'];
  inserted: boolean;
  moved: boolean;
  keys?: WorkKeyList;
  duration?: { saved: number | null; value: number | null };
  content?: { saved: string | null; value: string | null };
};

function workKeys(list: KeySlot[], address: Address): WorkKeyList {
  const scalar = list.length === 1 && addressKey(list[0]!.address) === addressKey(address);
  return {
    scalar,
    keys: list.map((slot) => ({ saved: slot.value, savedText: slot.value?.text ?? '', text: slot.value?.text ?? '' })),
    restructured: false,
  };
}

function newKey(text: string): WorkKey {
  return { saved: null, savedText: null, text };
}

/** index を 0〜length に収める */
function clamp(index: number, length: number): number {
  return Math.max(0, Math.min(length, Math.trunc(index)));
}

function moveItem<T>(items: T[], from: number, to: number): T | undefined {
  if (from < 0 || from >= items.length) return undefined;
  const [item] = items.splice(from, 1);
  items.splice(clamp(to, items.length), 0, item!);
  return item;
}

/** キーの並びに変更 1 つを当てる。rest は並びの Address より後ろの道筋 */
function applyKeyList(list: WorkKeyList, rest: (string | number)[], change: AnyChange): void {
  if (isNote(change)) return;
  if (rest.length === 0) {
    switch (change.op) {
      case 'insert':
        list.keys.splice(clamp(change.index, list.keys.length), 0, newKey(String(change.value)));
        list.scalar = false;
        list.restructured = true;
        return;
      case 'move':
        if (moveItem(list.keys, change.from, change.to)) list.restructured = true;
        list.scalar = false;
        return;
      case 'remove':
        // 1 つの値で書いた keys を消す（要素がなくなる）
        if (list.scalar) {
          list.keys = [];
          list.scalar = false;
          list.restructured = true;
        }
        return;
      default:
        if (list.scalar && list.keys[0]) list.keys[0].text = String(change.value);
        return;
    }
  }
  const index = rest[0];
  if (rest.length !== 1 || typeof index !== 'number') return;
  const key = list.keys[index];
  if (!key) return;
  if (change.op === 'remove') {
    list.keys.splice(index, 1);
    list.restructured = true;
  } else if (change.op === undefined || change.op === 'set') key.text = String(change.value);
}

function finishKeys(list: WorkKeyList, address: Address): KeyListView {
  return {
    address,
    scalar: list.scalar,
    restructured: list.restructured,
    keys: list.keys.map((key, index) => ({
      address: list.scalar ? address : { file: address.file, path: [...address.path, index] },
      saved: key.saved,
      text: key.text,
      changed: key.savedText === null || key.text !== key.savedText,
      note: '',
      noteChanged: false,
    })),
  };
}

function workStep(step: MacroStepSnapshot): WorkStep {
  switch (step.action) {
    case 'delay':
      return { action: 'delay', inserted: false, moved: false, duration: { saved: step.duration.value, value: step.duration.value } };
    case 'text':
      return { action: 'text', inserted: false, moved: false, content: { saved: step.content.value, value: step.content.value } };
    default:
      return { action: step.action, inserted: false, moved: false, keys: workKeys(step.keys, step.keysAddress) };
  }
}

function insertedStep(value: MacroStepValue | string): WorkStep | undefined {
  if (typeof value === 'string') return undefined;
  switch (value.action) {
    case 'delay':
      return { action: 'delay', inserted: true, moved: false, duration: { saved: null, value: value.duration } };
    case 'text':
      return { action: 'text', inserted: true, moved: false, content: { saved: null, value: value.content } };
    default:
      return { action: value.action, inserted: true, moved: false, keys: { scalar: false, keys: value.keys.map(newKey), restructured: false } };
  }
}

/** マクロに未保存の変更を当てた姿 */
export function macroView(macro: MacroSnapshot, pending: readonly AnyChange[]): MacroView {
  const file = macro.file;
  const overlay: Overlay = new Map();
  const steps = macro.steps.map(workStep);
  let restructured = false;
  for (const change of pending) {
    if (change.address.file !== file) continue;
    const path = change.address.path;
    if (path[0] !== 'sequence') {
      setOverlay(overlay, change);
      continue;
    }
    if (isNote(change)) continue;
    if (path.length === 1) {
      if (change.op === 'insert') {
        const step = insertedStep(change.value);
        if (step) {
          steps.splice(clamp(change.index, steps.length), 0, step);
          restructured = true;
        }
      } else if (change.op === 'move') {
        const step = moveItem(steps, change.from, change.to);
        if (step) {
          step.moved = true;
          restructured = true;
        }
      }
      continue;
    }
    const index = path[1];
    const step = typeof index === 'number' ? steps[index] : undefined;
    if (!step || typeof index !== 'number') continue;
    if (path.length === 2) {
      if (change.op === 'remove') {
        steps.splice(index, 1);
        restructured = true;
      }
      continue;
    }
    const field = path[2];
    if (field === 'keys' && step.keys) applyKeyList(step.keys, path.slice(3), change);
    else if (path.length === 3 && (change.op === undefined || change.op === 'set')) {
      if (field === 'duration' && step.duration) step.duration.value = asNumber(change.value);
      if (field === 'content' && step.content) step.content.value = asString(change.value);
    }
  }
  const view: StepView[] = steps.map((step, index) => {
    const address: Address = { file, path: ['sequence', index] };
    const base = { address, inserted: step.inserted, moved: step.moved };
    if (step.action === 'delay') {
      const d = step.duration!;
      const duration: ValueEntry<number> = { address: { file, path: ['sequence', index, 'duration'] }, saved: d.saved, value: d.value, changed: step.inserted || d.value !== d.saved };
      return { ...base, action: 'delay', duration, changed: step.inserted || step.moved || duration.changed };
    }
    if (step.action === 'text') {
      const c = step.content!;
      const content: ValueEntry<string> = { address: { file, path: ['sequence', index, 'content'] }, saved: c.saved, value: c.value, changed: step.inserted || c.value !== c.saved };
      return { ...base, action: 'text', content, changed: step.inserted || step.moved || content.changed };
    }
    const keys = finishKeys(step.keys!, { file, path: ['sequence', index, 'keys'] });
    return {
      ...base,
      action: step.action,
      keys,
      changed: step.inserted || step.moved || keys.restructured || keys.keys.some((k) => k.changed),
    };
  });
  return {
    macro,
    description: valueEntry({ address: macro.descriptionAddress, value: macro.description }, overlay, asString),
    preset: macro.presetAddress ? valueEntry({ address: macro.presetAddress, value: macro.preset }, overlay, asString) : null,
    stepsAddress: { file, path: ['sequence'] },
    steps: view,
    restructured,
  };
}

export function tapDanceView(tapDance: TapDanceSnapshot, pending: readonly AnyChange[]): TapDanceView {
  const overlay = overlayFor(pending, tapDance.file);
  return {
    tapDance,
    description: valueEntry({ address: tapDance.descriptionAddress, value: tapDance.description }, overlay, asString),
    actions: {
      tap: keyEntry(tapDance.actions.tap, overlay),
      hold: keyEntry(tapDance.actions.hold, overlay),
      doubleTap: keyEntry(tapDance.actions.doubleTap, overlay),
      tapHold: keyEntry(tapDance.actions.tapHold, overlay),
    },
    tappingTerm: valueEntry(tapDance.tappingTerm, overlay, asNumber),
  };
}

export function comboView(combo: ComboSnapshot, pending: readonly AnyChange[]): ComboView {
  const overlay: Overlay = new Map();
  const triggers = workKeys(combo.triggers, combo.triggersAddress);
  const listPath = combo.triggersAddress.path;
  for (const change of pending) {
    if (change.address.file !== combo.file) continue;
    const path = change.address.path;
    if (listPath.every((part, i) => path[i] === part)) applyKeyList(triggers, path.slice(listPath.length), change);
    else setOverlay(overlay, change);
  }
  return {
    combo,
    description: valueEntry({ address: combo.descriptionAddress, value: combo.description }, overlay, asString),
    triggers: finishKeys(triggers, combo.triggersAddress),
    output: keyEntry(combo.output, overlay),
  };
}

export function shortcutView(shortcut: ShortcutSnapshot, pending: readonly AnyChange[]): ShortcutView {
  return { shortcut, value: keyEntry({ address: shortcut.address, value: shortcut.value }, overlayFor(pending, shortcut.address.file)) };
}

// ---------------------------------------------------------------------------
// 検証の結果
// ---------------------------------------------------------------------------

/** address が prefix の道筋の中を指す（同じファイルで、道筋の先頭が一致） */
export function within(address: Address, prefix: Address): boolean {
  return address.file === prefix.file && prefix.path.every((part, i) => address.path[i] === part);
}

/** そのファイル（か、そのファイルの prefix の下）の検証の結果。address のないものは file で当てる */
export function diagnosticsIn(snapshot: ProfileSnapshot, file: string, prefix?: Address): Diagnostic[] {
  return snapshot.diagnostics.filter((d) => {
    if (d.address) return prefix ? within(d.address, prefix) : d.address.file === file;
    return !prefix && d.file === file;
  });
}

/** 名前の決まり（protocol.md の 12.5: 空でない・前後の空白なし・既存の名前と重ならない）。合えば undefined */
export function nameProblem(name: string, existing: readonly string[], current?: string): string | undefined {
  if (name.trim() === '') return '名前を入れてください';
  if (name !== name.trim()) return '名前の前後に空白は入れられません';
  if (name !== current && existing.includes(name)) return `「${name}」はもうあります`;
  return undefined;
}

// ---------------------------------------------------------------------------
// v0.5: 一覧に並べる項目（protocol.md の 15。未保存の変更を当てた番号・未保存のショートカットの追加）
// ---------------------------------------------------------------------------

/** 自分のショートカットのファイル（protocol.md の 15.2。行の追加はこのファイルの ["shortcuts", 名前]） */
export const SHORTCUTS_FILE = 'shortcuts.yaml';

/** 未保存の変更のうち、ショートカットの行の追加（["shortcuts", 名前] の set）の名前（当てる順。重なりは 1 つ） */
function pendingShortcutNames(pending: readonly AnyChange[]): string[] {
  const names: string[] = [];
  for (const change of pending) {
    const path = change.address.path;
    if (change.address.file !== SHORTCUTS_FILE || path.length !== 2 || path[0] !== 'shortcuts' || typeof path[1] !== 'string') continue;
    if (change.op !== undefined && change.op !== 'set') continue;
    if (change.field !== undefined && change.field !== 'key') continue;
    if (!names.includes(path[1])) names.push(path[1]);
  }
  return names;
}

/**
 * 一覧に並べるショートカット: snapshot のものと、未保存の変更で足したもの（snapshot にない名前の set）。
 * 足したものは保存済みの値がない項目として描き（値は未保存の変更から）、その名前の Address に書けば値を直せる
 */
export function shortcutItems(shortcuts: readonly ShortcutSnapshot[], pending: readonly AnyChange[]): ShortcutSnapshot[] {
  const added = pendingShortcutNames(pending)
    .filter((name) => !shortcuts.some((s) => s.name === name))
    .map((name): ShortcutSnapshot => ({ name, address: { file: SHORTCUTS_FILE, path: ['shortcuts', name] }, value: null }));
  return [...shortcuts, ...added];
}
