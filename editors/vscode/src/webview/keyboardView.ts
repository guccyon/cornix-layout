// 上のペイン: Cornix のキーボード図。選んでいるレイヤーの割り当てを描き、キーを押すと onSelect（下の欄へ移る）。
// 2 役のキー（display の tap / hold）は上下に分けて描く。レイヤー操作も同じ形で、下の帯にレイヤー番号（MO は帯だけ）。割り当て済みのキーにアイコン（同梱のショートカットと preset: のマクロ）。
// マクロ・タップダンス・自分のショートカットは右上に小さな印（M・TD・★。model.ts の keyMark）。NoKey は何も描かない（空白）。
// タップダンスは、キーの面を割り当てのある動作の数の窓に分けて描く（1 つは面全体、2 つは左右、3 つは上 1・下 2、4 つは 2×2。
// 順はタップ・ホールド・ダブルタップ・タップホールド）。エンコーダの帯では窓にせず、タップの札と「+残りの数」を並べる。
import type { Diagnostic, Hand, KeyValue } from '../protocol';
import { BOARD, ENCODERS, keyRect } from './cornixLayout';
import { h } from './dom';
import { iconElement } from './icons';
import { ENCODER_OPS, HAND_LABEL, keyAccessibleName, keyMark, severityOf, tapDanceWindows, windowLabels, type Slot } from './model';

/** 1 つの欄の描き方 */
export type SlotView = {
  /** 今の表記 */
  text: string;
  /** 今の表記の解釈（未保存の値でまだ聞いていなければ undefined、読めなければ null） */
  value: KeyValue | null | undefined;
  diagnostics: readonly Diagnostic[];
  changed: boolean;
};

export type KeyboardViewOptions = {
  onSelect: (slotId: string) => void;
  /** 説明をつなぐ（欄は id で指す。作り直さずに slot の中身が変わることがあるため） */
  decorate?: (element: HTMLElement, slotId: string) => void;
};

const pct = (value: number, total: number) => `${((value / total) * 100).toFixed(3)}%`;

export class KeyboardView {
  readonly element: HTMLElement;
  private readonly board: HTMLElement;
  private readonly elements = new Map<string, HTMLElement>();
  private slots = new Map<string, Slot>();
  private selected: string | undefined;
  /** 読み上げに添えるレイヤーの名前（図には番号だけを描く） */
  private layerNames: ReadonlyMap<number, string> = new Map();

  constructor(private readonly options: KeyboardViewOptions) {
    this.board = h('div', { class: 'board', style: `aspect-ratio: ${BOARD.width} / ${BOARD.height}` });
    this.element = h('div', { class: 'keyboard', role: 'group', 'aria-label': 'キーボード図' }, this.board);
  }

  /** レイヤーの番号 → 名前（setSlots / update の前に入れる） */
  setLayerNames(names: ReadonlyMap<number, string>): void {
    this.layerNames = names;
  }

  /** レイヤーの欄で作り直す */
  setSlots(slots: Slot[]): void {
    this.slots = new Map(slots.map((slot) => [slot.id, slot]));
    this.elements.clear();
    this.board.replaceChildren();
    for (const slot of slots) {
      if (!slot.key) continue;
      const rect = keyRect(slot.hand, slot.key.row, slot.key.col);
      if (!rect) continue;
      const key = h('button', {
        type: 'button',
        class: 'key',
        'data-slot': slot.id,
        style: [
          `left: ${pct(rect.x, BOARD.width)}`,
          `top: ${pct(rect.y, BOARD.height)}`,
          `width: ${pct(rect.w, BOARD.width)}`,
          `height: ${pct(rect.h, BOARD.height)}`,
          rect.rotate ? `transform: rotate(${rect.rotate}deg)` : '',
        ].join('; '),
      });
      this.add(key, slot);
    }
    for (const hand of ['left', 'right'] as const) this.board.append(this.encoder(hand, slots));
    this.applySelection();
  }

  /** 作り直さずに欄の中身（保存済みの値など）だけを差し替える。並びと Address は同じであること */
  replaceSlots(slots: Slot[]): void {
    this.slots = new Map(slots.map((slot) => [slot.id, slot]));
  }

  private encoder(hand: Hand, slots: Slot[]): HTMLElement {
    const place = ENCODERS[hand];
    const wrapper = h('div', {
      class: 'encoder',
      role: 'group',
      'aria-label': `${HAND_LABEL[hand]}のエンコーダ`,
      style: [
        `left: ${pct(place.x, BOARD.width)}`,
        `top: ${pct(place.y, BOARD.height)}`,
        `width: ${pct(place.w, BOARD.width)}`,
        `height: ${pct(place.h, BOARD.height)}`,
      ].join('; '),
    });
    for (const { op } of ENCODER_OPS) {
      const slot = slots.find((s) => s.hand === hand && s.encoder === op);
      if (!slot) continue;
      const part = h('button', { type: 'button', class: `encoder-part encoder-${op}`, 'data-slot': slot.id });
      this.add(part, slot, wrapper);
    }
    return wrapper;
  }

  private add(element: HTMLElement, slot: Slot, parent: HTMLElement = this.board): void {
    element.setAttribute('aria-label', keyAccessibleName(slot, slot.saved?.text ?? '', slot.saved, [], this.layerNames));
    element.addEventListener('click', () => this.options.onSelect(slot.id));
    this.options.decorate?.(element, slot.id);
    this.elements.set(slot.id, element);
    parent.append(element);
  }

  /** 1 つの欄の中身を描く */
  update(slotId: string, view: SlotView): void {
    const element = this.elements.get(slotId);
    const slot = this.slots.get(slotId);
    if (!element || !slot) return;
    const severity = severityOf(view.diagnostics);
    element.replaceChildren(...keyFace(view));
    element.setAttribute('aria-label', keyAccessibleName(slot, view.text, view.value, view.diagnostics, this.layerNames));
    element.classList.toggle('unassigned', view.text === '');
    element.classList.toggle('changed', view.changed);
    element.classList.toggle('error', severity === 'error');
    element.classList.toggle('warning', severity === 'warning');
    element.classList.toggle('dual', !!view.value?.display.hold && !tapDanceWindows(view.value));
    element.dataset.kind = view.value?.kind ?? '';
    element.classList.toggle('marked', !!keyMark(view.value));
    element.classList.toggle('windowed', !!tapDanceWindows(view.value));
  }

  setSelected(slotId: string | undefined): void {
    this.selected = slotId;
    this.applySelection();
  }

  private applySelection(): void {
    for (const [id, element] of this.elements) {
      const selected = id === this.selected;
      element.classList.toggle('selected', selected);
      element.setAttribute('aria-pressed', String(selected));
    }
  }
}

/** キーの面: アイコン・文字（2 役なら tap と hold を上下に）・印 */
export function keyFace(view: Pick<SlotView, 'text' | 'value'>): Node[] {
  const nodes: Node[] = [];
  const value = view.value;
  const icon = iconElement(value?.icon, 'key-icon');
  if (icon) nodes.push(icon);
  if (view.text === '') return nodes;
  const mark = keyMark(value);
  // 印の意味は説明（app.ts の describe）と読み上げ（keyAccessibleName）で伝える
  if (mark) nodes.push(h('span', { class: `key-mark mark-${mark.kind}`, 'aria-hidden': 'true' }, mark.text));
  if (value === undefined || value === null) {
    // まだ解釈を聞いていない（未保存の値）か、読めない表記: 書いたとおりに出す
    nodes.push(h('span', { class: 'key-label raw' }, view.text));
    return nodes;
  }
  const { tap, hold, label } = value.display;
  const windows = tapDanceWindows(value);
  if (windows) {
    nodes.push(
      h(
        'span',
        { class: `td-windows td-${windows.length}`, 'aria-hidden': 'true' },
        ...windowLabels(windows).map((label, i) =>
          h(
            'span',
            { class: `td-window td-window-${i + 1}`, 'data-action': windows[i]!.action },
            // 1 語なら 1 行で省略（語の途中で折らない）、2 語以上なら語の切れ目で 2 行まで
            h('span', { class: `td-label${label.includes(' ') ? ' multi' : ''}` }, label),
          ),
        ),
        // エンコーダの帯ではタップの札とこの「+残りの数」だけを見せる（キーでは隠す。media/webview.css）
        windows.length > 1 ? h('span', { class: 'td-more' }, `+${windows.length - 1}`) : null,
      ),
    );
  } else if (hold) {
    // 下の帯（2 役のキーのホールド、レイヤー操作のレイヤー）。MO は面を空けて帯だけ
    nodes.push(h('span', { class: 'key-tap' }, tap ?? ''), h('span', { class: 'key-hold' }, hold));
  } else if (value.kind === 'transparent') {
    nodes.push(h('span', { class: 'key-label faint' }, label || '▽'));
  } else if (value.kind === 'noKey') {
    // 何もしないキーは空白（✕ や x は文字のキーと見間違えるため）。label はサーバーが空で返す
    if (label) nodes.push(h('span', { class: 'key-label faint' }, label));
  } else {
    nodes.push(h('span', { class: `key-label${label.length > 6 ? ' long' : ''}` }, label));
  }
  return nodes;
}
