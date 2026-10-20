// 上のペイン: Cornix のキーボード図。選んでいるレイヤーの割り当てを描き、キーを押すと onSelect（下の欄へ移る）。
// 2 役のキー（display の tap / hold）は上下に分けて描く。レイヤー操作も同じ形で、下の帯にレイヤー番号（MO は帯だけ）。割り当て済みのキーにアイコン（同梱のショートカットと preset: のマクロ）。
// マクロ・タップダンス・自分のショートカットは右上に小さな印（M・TD・★。model.ts の keyMark）。NoKey は何も描かない（空白）。
// KC_TRNS のキーには、レイヤー 0 の同じ位置の値を薄く描く（SlotView.base。protocol.md の 12.7）。
// 位置の名前の表示: 図の上のボタンで固定の切り替え、Alt を押している間だけ一時表示（ウィンドウがフォーカスを失ったら戻す）。
// 表示中はキーの面に割り当ての代わりに position_map の名前を紫で描き、読み上げも位置の名前にする。表示中にキーを押すと、
// 名前を変えられる位置（positionAddress のある位置）なら onRenamePosition（下の欄で名前を変える）。
// タップダンスは、キーの面を割り当てのある動作の数の窓に分けて描く（1 つは面全体、2 つ・3 つは横幅いっぱいの窓を上から順に
// 重ね、4 つは 2×2。順はタップ・ホールド・ダブルタップ・タップホールド）。エンコーダの帯では窓にせず、タップの札と「+残りの数」を並べる。
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
  /** KC_TRNS のときに薄く描く、レイヤー 0 の同じ位置の値（model.ts の baseLayerValue） */
  base?: KeyValue | null;
};

export type KeyboardViewOptions = {
  onSelect: (slotId: string) => void;
  /** 説明をつなぐ（欄は id で指す。作り直さずに slot の中身が変わることがあるため） */
  decorate?: (element: HTMLElement, slotId: string) => void;
  /** 位置の名前を表示している間にキーを押した（名前を変えられる位置だけ）。なければ onSelect */
  onRenamePosition?: (slotId: string) => void;
  /** Alt の一時表示を受ける窓（テストで差し替える。省くと window） */
  window?: Window;
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
  /** 最後に描いた中身（位置の名前の表示を切り替えたときに描き直す） */
  private readonly views = new Map<string, SlotView>();
  /** 位置の名前をボタンで固定して表示している */
  private pinned = false;
  /** Alt を押している間の一時表示 */
  private held = false;
  private readonly toggle: HTMLButtonElement;

  constructor(private readonly options: KeyboardViewOptions) {
    this.board = h('div', { class: 'board', style: `aspect-ratio: ${BOARD.width} / ${BOARD.height}` });
    this.toggle = h(
      'button',
      { type: 'button', class: 'position-toggle', 'aria-pressed': 'false', title: 'キーの面に位置の名前（position_map）を出す。Alt を押している間も出る。出している間にキーを押すと名前を変えられる' },
      '位置の名前',
    );
    this.toggle.addEventListener('click', () => this.setPinned(!this.pinned));
    const toolbar = h('div', { class: 'keyboard-toolbar' }, this.toggle);
    this.element = h('div', { class: 'keyboard', role: 'group', 'aria-label': 'キーボード図' }, toolbar, this.board);
    const win = options.window ?? window;
    win.addEventListener('keydown', (event) => {
      if (event.key === 'Alt') this.setHeld(true);
    });
    win.addEventListener('keyup', (event) => {
      if (event.key === 'Alt') this.setHeld(false);
    });
    win.addEventListener('blur', () => this.setHeld(false));
  }

  /** 位置の名前を出している（固定か Alt の一時表示） */
  get showingPositions(): boolean {
    return this.pinned || this.held;
  }

  /** ボタンでの固定の切り替え */
  setPinned(pinned: boolean): void {
    this.pinned = pinned;
    this.toggle.setAttribute('aria-pressed', String(pinned));
    this.toggle.classList.toggle('selected', pinned);
    this.renderAll();
  }

  /** Alt での一時表示 */
  setHeld(held: boolean): void {
    if (this.held === held) return;
    this.held = held;
    this.renderAll();
  }

  private renderAll(): void {
    this.board.classList.toggle('show-positions', this.showingPositions);
    for (const id of this.elements.keys()) this.render(id);
  }

  /** レイヤーの番号 → 名前（setSlots / update の前に入れる） */
  setLayerNames(names: ReadonlyMap<number, string>): void {
    this.layerNames = names;
  }

  /** レイヤーの欄で作り直す */
  setSlots(slots: Slot[]): void {
    this.slots = new Map(slots.map((slot) => [slot.id, slot]));
    this.elements.clear();
    this.views.clear();
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
    element.addEventListener('click', () => {
      const current = this.slots.get(slot.id) ?? slot;
      if (this.showingPositions && current.key?.positionAddress && this.options.onRenamePosition) this.options.onRenamePosition(slot.id);
      else this.options.onSelect(slot.id);
    });
    this.options.decorate?.(element, slot.id);
    this.elements.set(slot.id, element);
    parent.append(element);
  }

  /** 1 つの欄の中身を描く */
  update(slotId: string, view: SlotView): void {
    if (!this.elements.has(slotId)) return;
    this.views.set(slotId, view);
    this.render(slotId);
  }

  private render(slotId: string): void {
    const element = this.elements.get(slotId);
    const slot = this.slots.get(slotId);
    const view = this.views.get(slotId);
    if (!element || !slot || !view) return;
    const severity = severityOf(view.diagnostics);
    // 位置の名前はキーにだけある（エンコーダはいつも割り当てを描く）
    const positions = this.showingPositions && !!slot.key;
    element.classList.toggle('unassigned', view.text === '');
    element.classList.toggle('changed', view.changed);
    element.classList.toggle('error', severity === 'error');
    element.classList.toggle('warning', severity === 'warning');
    element.classList.toggle('position', positions);
    if (positions) {
      element.replaceChildren(h('span', { class: `key-label position-name${slot.label.length > 6 ? ' long' : ''}` }, slot.label));
      element.setAttribute('aria-label', `${HAND_LABEL[slot.hand]} 位置の名前 ${slot.label}`);
      element.classList.remove('dual', 'marked', 'windowed');
      element.dataset.kind = '';
      return;
    }
    element.replaceChildren(...keyFace(view));
    element.setAttribute('aria-label', keyAccessibleName(slot, view.text, view.value, view.diagnostics, this.layerNames, view.base));
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
export function keyFace(view: Pick<SlotView, 'text' | 'value' | 'base'>): Node[] {
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
    // レイヤー 0 の値があればそれを薄く（「レイヤー 0 の値」は説明と読み上げで伝える）
    if (view.base) nodes.push(h('span', { class: 'key-label faint base-value' }, view.base.display.label));
    else nodes.push(h('span', { class: 'key-label faint' }, label || '▽'));
  } else if (value.kind === 'noKey') {
    // 何もしないキーは空白（✕ や x は文字のキーと見間違えるため）。label はサーバーが空で返す
    if (label) nodes.push(h('span', { class: 'key-label faint' }, label));
  } else {
    nodes.push(h('span', { class: `key-label${label.length > 6 ? ' long' : ''}` }, label));
  }
  return nodes;
}
