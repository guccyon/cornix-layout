// 修飾キー式・LT・Mod-Tap の組み立て欄（spec.md の「入力と補完」、protocol.md の 12.4）。キー入力欄の「組み立て」から開く。
// 表記はここで組み立て、keycode/inspect で解釈を確かめてから入れる（サーバーに組み立てのメソッドはない）。
// 修飾キーは左右を 1 つだけ選ぶ形にして、左右の混在を作らせない（Domain::ModifierSet は左右どちらか一方）。
// 表記の形は docs/notation.md と Mapping::KeycodeNotation::Modifiers に合わせる:
// - 修飾キー式: Ctrl, Option, Shift, Command の順（右は RCtrl, ROption, RShift, RCommand）を " + " でつなぎ、最後にキー
// - LT: LT(レイヤー, キー)（レイヤーは 0〜15）
// - Mod-Tap: 正規名_T(キー)（LGUI_T(Lang2)、RSFT_T(Up)）。正規名のない組み合わせは MT(MOD_RCTL|MOD_RSFT|MOD_RALT, キー)
import type { CandidateContext, InspectResult } from '../protocol';
import { h, nodes } from './dom';
import type { HostClient } from './hostClient';
import { KeyInput } from './keyInput';

export type Modifier = 'ctrl' | 'alt' | 'shift' | 'gui';
export type Side = 'left' | 'right';
export type BuildKind = 'modifiers' | 'layerTap' | 'modTap';

export type BuildState = {
  kind: BuildKind;
  side: Side;
  mods: Modifier[];
  layer: number;
  key: string;
};

/** 修飾キー式の並び（KeycodeNotation::Modifiers::EXPRESSION_ORDER） */
export const MODIFIER_ORDER: Modifier[] = ['ctrl', 'alt', 'shift', 'gui'];

/** 修飾キー式の名前（EXPRESSION_FORMAT） */
const EXPRESSION_NAME: Record<Side, Record<Modifier, string>> = {
  left: { ctrl: 'Ctrl', alt: 'Option', shift: 'Shift', gui: 'Command' },
  right: { ctrl: 'RCtrl', alt: 'ROption', shift: 'RShift', gui: 'RCommand' },
};

/** 画面に出す修飾キーの名前（macOS の記号を添える） */
export const MODIFIER_LABEL: Record<Modifier, string> = { ctrl: '⌃ Ctrl', alt: '⌥ Option', shift: '⇧ Shift', gui: '⌘ Command' };

const BITS: Record<Modifier, number> = { ctrl: 0x01, shift: 0x02, alt: 0x04, gui: 0x08 };
const RIGHT = 0x10;

/** 修飾関数の正規名（KeycodeNotation::Modifiers::FUNCTIONS）。ModTap は「正規名_T」 */
const FUNCTIONS: Record<string, number> = {
  LCTL: 0x01, LSFT: 0x02, C_S: 0x03, LALT: 0x04, LCA: 0x05, LSA: 0x06, MEH: 0x07, LGUI: 0x08, LCG: 0x09, SGUI: 0x0a,
  LCSG: 0x0b, LAG: 0x0c, LCAG: 0x0d, LSAG: 0x0e, HYPR: 0x0f,
  RCTL: 0x11, RSFT: 0x12, RCS: 0x13, RALT: 0x14, RCA: 0x15, RSA: 0x16, RGUI: 0x18, RCG: 0x19, RSG: 0x1a, RCSG: 0x1b,
  RAG: 0x1c, RCAG: 0x1d, RSAG: 0x1e,
};

/** ModTap の関数名の別名（MOD_TAP_BITS に足してあるもの） */
const MOD_TAP_ALIASES: Record<string, number> = { CTL_T: 0x01, SFT_T: 0x02, ALT_T: 0x04, OPT_T: 0x04, GUI_T: 0x08, CMD_T: 0x08, WIN_T: 0x08, ALL_T: 0x0f };

/** MT の引数の MOD_ 定数（CONSTANT_FORMAT） */
const CONSTANT_NAME: Record<Side, Record<Modifier, string>> = {
  left: { ctrl: 'MOD_LCTL', shift: 'MOD_LSFT', alt: 'MOD_LALT', gui: 'MOD_LGUI' },
  right: { ctrl: 'MOD_RCTL', shift: 'MOD_RSFT', alt: 'MOD_RALT', gui: 'MOD_RGUI' },
};

/** 修飾キー式で読める名前（EXPRESSION のうち組み立て欄が読み戻すもの） */
const EXPRESSION_READ: Record<string, [Side, Modifier]> = {
  Shift: ['left', 'shift'], LShift: ['left', 'shift'], RShift: ['right', 'shift'],
  Ctrl: ['left', 'ctrl'], LCtrl: ['left', 'ctrl'], Control: ['left', 'ctrl'], LControl: ['left', 'ctrl'], RCtrl: ['right', 'ctrl'], RControl: ['right', 'ctrl'],
  Alt: ['left', 'alt'], LAlt: ['left', 'alt'], Option: ['left', 'alt'], LOption: ['left', 'alt'], RAlt: ['right', 'alt'], ROption: ['right', 'alt'],
  Cmd: ['left', 'gui'], LCmd: ['left', 'gui'], Command: ['left', 'gui'], LCommand: ['left', 'gui'], Win: ['left', 'gui'], LWin: ['left', 'gui'],
  Gui: ['left', 'gui'], LGui: ['left', 'gui'], RCmd: ['right', 'gui'], RCommand: ['right', 'gui'], RWin: ['right', 'gui'], RGui: ['right', 'gui'],
};

export const MAX_LAYER = 15;

export function emptyState(): BuildState {
  return { kind: 'modifiers', side: 'left', mods: [], layer: 1, key: '' };
}

function bitsOf(side: Side, mods: readonly Modifier[]): number {
  return mods.reduce((bits, mod) => bits | BITS[mod], side === 'right' ? RIGHT : 0);
}

function modsOf(bits: number): { side: Side; mods: Modifier[] } {
  return { side: bits & RIGHT ? 'right' : 'left', mods: MODIFIER_ORDER.filter((mod) => bits & BITS[mod]) };
}

/** 組み立てられない理由（足りないもの）。組み立てられれば null */
export function missing(state: BuildState): string | null {
  if (state.kind !== 'layerTap' && state.mods.length === 0) return '修飾キーを 1 つ以上選んでください';
  if (state.kind === 'layerTap' && !(Number.isInteger(state.layer) && state.layer >= 0 && state.layer <= MAX_LAYER)) return `レイヤーは 0〜${MAX_LAYER} です`;
  if (!state.key.trim()) return 'キーを入れてください';
  return null;
}

/** 表記を組み立てる（足りなければ null） */
export function buildNotation(state: BuildState): string | null {
  if (missing(state)) return null;
  const key = state.key.trim();
  const mods = MODIFIER_ORDER.filter((mod) => state.mods.includes(mod));
  switch (state.kind) {
    case 'modifiers':
      return [...mods.map((mod) => EXPRESSION_NAME[state.side][mod]), key].join(' + ');
    case 'layerTap':
      return `LT(${state.layer}, ${key})`;
    case 'modTap': {
      const bits = bitsOf(state.side, mods);
      const name = Object.keys(FUNCTIONS).find((n) => FUNCTIONS[n] === bits);
      if (name) return `${name}_T(${key})`;
      // MOD_ 定数の並びは Domain::ModifierSet::ORDER（ctrl, shift, alt, gui）
      const constants = (['ctrl', 'shift', 'alt', 'gui'] as const).filter((mod) => mods.includes(mod)).map((mod) => CONSTANT_NAME[state.side][mod]);
      return `MT(${constants.join('|')}, ${key})`;
    }
  }
}

/**
 * 今の表記から組み立て欄の初めの値を読む（組み立て欄が作る形と、そのよくある書き方だけ）。
 * 読めなければ、関数や修飾キー式でない表記はキーとして入れ、それ以外は空から
 */
export function parseNotation(text: string): BuildState {
  const state = emptyState();
  const trimmed = text.trim();
  if (!trimmed) return state;
  const lt = /^LT\(\s*(\d+)\s*,\s*(.+?)\s*\)$/.exec(trimmed) ?? /^LT(\d+)\(\s*(.+?)\s*\)$/.exec(trimmed);
  if (lt) return { ...state, kind: 'layerTap', layer: Number(lt[1]), key: lt[2]! };
  const modTap = /^([A-Z_]+_T)\(\s*(.+?)\s*\)$/.exec(trimmed);
  if (modTap) {
    const name = modTap[1]!;
    const bits = MOD_TAP_ALIASES[name] ?? FUNCTIONS[name.slice(0, -2)];
    if (bits !== undefined) return { ...state, kind: 'modTap', ...modsOf(bits), key: modTap[2]! };
  }
  const mt = /^MT\(\s*([A-Z_|\s]+?)\s*,\s*(.+?)\s*\)$/.exec(trimmed);
  if (mt) {
    let bits = 0;
    for (const part of mt[1]!.split('|').map((p) => p.trim())) {
      const entry = (['left', 'right'] as const).flatMap((side) => MODIFIER_ORDER.filter((mod) => CONSTANT_NAME[side][mod] === part).map((mod) => [side, mod] as const))[0];
      if (!entry) return state;
      bits |= BITS[entry[1]] | (entry[0] === 'right' ? RIGHT : 0);
    }
    return { ...state, kind: 'modTap', ...modsOf(bits), key: mt[2]! };
  }
  const parts = trimmed.split(/\s+\+\s+/);
  if (parts.length >= 2) {
    const read = parts.slice(0, -1).map((name) => EXPRESSION_READ[name]);
    const sides = new Set(read.map((entry) => entry?.[0]));
    if (read.every((entry) => entry) && sides.size === 1) {
      const side = read[0]![0];
      return { ...state, kind: 'modifiers', side, mods: MODIFIER_ORDER.filter((mod) => read.some((entry) => entry![1] === mod)), key: parts.at(-1)! };
    }
    return state;
  }
  if (/^[^()+]+$/.test(trimmed)) return { ...state, key: trimmed };
  return state;
}

export type ModifierBuilderOptions = {
  host: HostClient;
  context: CandidateContext;
  /** 決めた表記（keycode/inspect で読めたもの） */
  onApply: (text: string) => void;
  /** 閉じた（決めたときも）。focusBack は元の入力欄にフォーカスを戻すか（ほかの場所を押して閉じたときは戻さない） */
  onClose: (focusBack: boolean) => void;
  /** レイヤーの選び先（番号と名前）。なければ 0〜15 の番号 */
  layers?: () => readonly { index: number; name: string }[];
};

const KIND_LABEL: Record<BuildKind, string> = {
  modifiers: '修飾キー＋キー',
  layerTap: 'レイヤー＋キー（LT）',
  modTap: 'Mod-Tap',
};

const KIND_HINT: Record<BuildKind, string> = {
  modifiers: '修飾キーを押したままキーを押したことにする（Shift + Command + P）',
  layerTap: 'タップでキー、押している間はそのレイヤー',
  modTap: 'タップでキー、押している間は修飾キー',
};

let nextId = 1;

/** 組み立て欄。キー入力欄の下に開く小さな枠 */
export class ModifierBuilder {
  readonly element: HTMLElement;
  private state: BuildState = emptyState();
  private readonly id = `modifier-builder-${nextId++}`;
  private readonly kindGroup: HTMLElement;
  private readonly sideGroup: HTMLElement;
  private readonly modGroup: HTMLElement;
  private readonly layerRow: HTMLElement;
  private readonly layerSelect: HTMLSelectElement;
  private readonly modRow: HTMLElement;
  private readonly keyInput: KeyInput;
  private readonly preview: HTMLElement;
  private readonly applyButton: HTMLButtonElement;
  /** 解釈の要求の番号（古い結果を捨てる） */
  private sequence = 0;
  /** 今の表記を読めた（入れてよい） */
  private valid: string | null = null;

  constructor(private readonly options: ModifierBuilderOptions) {
    this.kindGroup = h('div', { class: 'builder-kinds', role: 'radiogroup', 'aria-label': '組み立てる形' });
    for (const kind of Object.keys(KIND_LABEL) as BuildKind[]) {
      const radio = h('input', { type: 'radio', name: `${this.id}-kind`, value: kind });
      radio.addEventListener('change', () => this.set({ kind }));
      this.kindGroup.append(h('label', { class: 'builder-choice' }, radio, KIND_LABEL[kind]));
    }
    this.sideGroup = h('div', { class: 'builder-sides', role: 'radiogroup', 'aria-label': '左右' });
    for (const side of ['left', 'right'] as const) {
      const radio = h('input', { type: 'radio', name: `${this.id}-side`, value: side });
      radio.addEventListener('change', () => this.set({ side }));
      this.sideGroup.append(h('label', { class: 'builder-choice' }, radio, side === 'left' ? '左' : '右'));
    }
    this.modGroup = h('div', { class: 'builder-mods', role: 'group', 'aria-label': '修飾キー' });
    for (const mod of MODIFIER_ORDER) {
      const box = h('input', { type: 'checkbox', value: mod });
      box.addEventListener('change', () => {
        const mods = box.checked ? [...this.state.mods, mod] : this.state.mods.filter((m) => m !== mod);
        this.set({ mods: MODIFIER_ORDER.filter((m) => mods.includes(m)) });
      });
      this.modGroup.append(h('label', { class: 'builder-choice' }, box, MODIFIER_LABEL[mod]));
    }
    this.modRow = h('div', { class: 'builder-row' }, h('span', { class: 'builder-row-label' }, '修飾キー'), this.modGroup, this.sideGroup);
    this.layerSelect = h('select', { class: 'builder-layer', 'aria-label': 'レイヤー' });
    this.layerSelect.addEventListener('change', () => this.set({ layer: Number(this.layerSelect.value) }));
    this.layerRow = h('div', { class: 'builder-row' }, h('span', { class: 'builder-row-label' }, 'レイヤー'), this.layerSelect);
    this.keyInput = new KeyInput({
      context: options.context,
      host: options.host,
      label: '組み立てるキー',
      placeholder: 'キー（Escape、P など）',
      allowEmpty: true,
      onCommit: (text) => this.set({ key: text }),
    });
    this.keyInput.input.addEventListener('input', () => this.set({ key: this.keyInput.input.value }, false));
    this.preview = h('div', { class: 'builder-preview', 'aria-live': 'polite' });
    this.applyButton = h('button', { type: 'button', class: 'builder-apply' }, '入れる');
    this.applyButton.addEventListener('click', () => void this.apply());
    const cancel = h('button', { type: 'button', class: 'builder-cancel' }, 'やめる');
    cancel.addEventListener('click', () => this.close());
    this.element = h(
      'div',
      { class: 'modifier-builder', role: 'dialog', 'aria-label': '修飾キー・LT・Mod-Tap の組み立て', hidden: true },
      this.kindGroup,
      this.modRow,
      this.layerRow,
      h('div', { class: 'builder-row' }, h('span', { class: 'builder-row-label' }, 'キー'), this.keyInput.element),
      this.preview,
      h('div', { class: 'builder-actions' }, this.applyButton, cancel),
    );
    this.element.addEventListener('keydown', (event) => {
      if (event.key !== 'Escape' || event.defaultPrevented) return;
      event.preventDefault();
      event.stopPropagation();
      this.close();
    });
  }

  get isOpen(): boolean {
    return !this.element.hidden;
  }

  get current(): BuildState {
    return { ...this.state, mods: [...this.state.mods] };
  }

  /** 今の表記から始めて開く */
  open(text: string): void {
    this.state = parseNotation(text);
    this.renderLayers();
    this.element.hidden = false;
    this.keyInput.setValue(this.state.key);
    this.render();
    this.element.querySelector<HTMLInputElement>(`input[value="${this.state.kind}"]`)?.focus();
  }

  close(focusBack = true): void {
    if (this.element.hidden) return;
    this.sequence++;
    this.keyInput.close();
    this.element.hidden = true;
    this.options.onClose(focusBack);
  }

  dispose(): void {
    this.sequence++;
    this.keyInput.dispose();
  }

  /** 値を変える（テストからも呼ぶ） */
  set(patch: Partial<BuildState>, syncKey = true): void {
    this.state = { ...this.state, ...patch };
    if (syncKey && patch.key !== undefined) this.keyInput.setValue(patch.key);
    this.render();
  }

  /** 組み立てた表記を確かめて入れる。読めなければ入れない */
  async apply(): Promise<boolean> {
    // 打ちかけのキーも入れる（「入れる」を押す前に欄を離れていなくても）
    this.state = { ...this.state, key: this.keyInput.input.value };
    const text = buildNotation(this.state);
    if (!text) {
      this.render();
      return false;
    }
    const ok = this.valid === text || (await this.check(text));
    if (!ok || !this.isOpen) return false;
    this.options.onApply(text);
    this.close();
    return true;
  }

  private renderLayers(): void {
    const layers = this.options.layers?.() ?? [];
    const names = new Map(layers.map((layer) => [layer.index, layer.name]));
    const indexes = layers.length > 0 ? layers.map((layer) => layer.index).filter((i) => i >= 0 && i <= MAX_LAYER) : [...Array(MAX_LAYER + 1).keys()];
    if (!indexes.includes(this.state.layer)) indexes.push(this.state.layer);
    this.layerSelect.replaceChildren(
      ...indexes
        .filter((i) => i >= 0 && i <= MAX_LAYER)
        .sort((a, b) => a - b)
        .map((i) => h('option', { value: i }, names.has(i) ? `${i} ${names.get(i)}` : String(i))),
    );
  }

  private render(): void {
    const { kind, side, mods, layer } = this.state;
    for (const radio of this.kindGroup.querySelectorAll<HTMLInputElement>('input')) radio.checked = radio.value === kind;
    for (const radio of this.sideGroup.querySelectorAll<HTMLInputElement>('input')) radio.checked = radio.value === side;
    for (const box of this.modGroup.querySelectorAll<HTMLInputElement>('input')) box.checked = mods.includes(box.value as Modifier);
    this.modRow.hidden = kind === 'layerTap';
    this.layerRow.hidden = kind !== 'layerTap';
    this.layerSelect.value = String(layer);
    const text = buildNotation(this.state);
    const lack = missing(this.state);
    this.valid = null;
    this.applyButton.disabled = true;
    this.preview.replaceChildren(
      h('div', { class: 'builder-hint' }, KIND_HINT[kind]),
      text ? h('code', { class: 'builder-text' }, text) : h('div', { class: 'builder-missing' }, lack ?? ''),
    );
    if (text) void this.check(text);
  }

  /** keycode/inspect で解釈を確かめ、結果を添える。読めて error がなければ true */
  private async check(text: string): Promise<boolean> {
    const sequence = ++this.sequence;
    let result: InspectResult;
    try {
      result = await this.options.host.request('keycode/inspect', { context: this.options.context, text });
    } catch (error) {
      if (sequence === this.sequence) this.showResult(text, null, [error instanceof Error ? error.message : String(error)]);
      return false;
    }
    if (sequence !== this.sequence) return this.valid === text;
    const errors = result.diagnostics.filter((d) => d.severity === 'error').map((d) => d.message);
    const ok = !!result.value && errors.length === 0;
    this.showResult(text, ok ? result : null, ok ? result.diagnostics.map((d) => d.message) : errors.length > 0 ? errors : ['読めない表記です']);
    this.valid = ok ? text : null;
    this.applyButton.disabled = !ok;
    return ok;
  }

  private showResult(text: string, result: InspectResult | null, messages: string[]): void {
    const value = result?.value;
    this.preview.replaceChildren(
      ...nodes(
        h('div', { class: 'builder-hint' }, KIND_HINT[this.state.kind]),
        h('code', { class: 'builder-text' }, text),
        value && h('div', { class: 'builder-meaning' }, `→ ${value.canonical}${value.display.label ? `（${value.display.label}）` : ''}`),
        ...messages.map((message) => h('div', { class: `builder-message ${value ? 'warning' : 'error'}` }, message)),
      ),
    );
  }
}
