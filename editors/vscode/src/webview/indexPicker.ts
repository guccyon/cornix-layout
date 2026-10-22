// 番号の選択（issue #110 の W0）。番号の変更と入れ替えを 1 つの選択にする: 0〜上限の番号を並べ、
// 空きを選べば移動、使っている番号を選べば入れ替え（どちらになるかを文で出す）。
// 書き添える注意（レイヤーなら MO(n) などの参照は書き換えないこと、マクロなら番号の参照も書き換えること）は呼ぶ側が渡す。
// 番号は radiogroup（上下左右・Home/End で選ぶ）。「やめる」と決定（「移動する」/「入れ替える」）。Escape で閉じる。
// 置き場所は呼ぶ側が決める（element を足す）。閉じたら element を外し、returnFocus にフォーカスを戻す。
import { h } from './dom';
import { moveFocusInList } from './focusList';

export type IndexMode = 'move' | 'swap';

export type IndexPickerOptions = {
  /** 何の番号か（例「レイヤー」「マクロ」） */
  noun: string;
  /** 番号を変える項目の名前 */
  name: string;
  /** 今の番号 */
  current: number;
  /** 番号の数（0〜limit-1 を並べる。レイヤーは 10、マクロなどは 32） */
  limit: number;
  /** 使っている番号と、その項目の名前（current は含めても含めなくてよい） */
  used: ReadonlyMap<number, string>;
  /** 書き添える注意（選んだ番号と、移動か入れ替えかで変えられる）。空なら出さない */
  note?: string | ((target: number, mode: IndexMode, other: string | undefined) => string | null);
  /** 決めた */
  onConfirm: (target: number, mode: IndexMode) => void;
  /** 閉じた（やめる・Escape・決めたとき） */
  onClose?: () => void;
  /** 閉じたあとにフォーカスを戻す先（「…」のボタンなど） */
  returnFocus?: HTMLElement | null;
};

export const INDEX_PICKER_CANCEL = 'やめる';
export const INDEX_PICKER_MOVE = '移動する';
export const INDEX_PICKER_SWAP = '入れ替える';

/** 番号の状態（「今」「使っている（名前）」「空き」） */
export function indexSlotLabel(index: number, options: Pick<IndexPickerOptions, 'current' | 'used'>): string {
  if (index === options.current) return '今';
  const name = options.used.get(index);
  return name === undefined ? '空き' : `使っている（${name}）`;
}

/** 選んだ番号でどうなるかの文 */
export function indexPlanText(target: number, options: Pick<IndexPickerOptions, 'noun' | 'name' | 'current' | 'used'>): string {
  const other = options.used.get(target);
  if (other === undefined) return `${options.noun}「${options.name}」を番号 ${options.current} から ${target} に移します。`;
  return `${options.noun}「${options.name}」（番号 ${options.current}）と「${other}」（番号 ${target}）の番号を入れ替えます。`;
}

let nextPickerId = 1;

export class IndexPicker {
  readonly element: HTMLElement;
  private readonly slots: HTMLButtonElement[];
  private readonly plan: HTMLElement;
  private readonly note: HTMLElement;
  private readonly confirm: HTMLButtonElement;
  private readonly id = `index-picker-${nextPickerId++}`;
  private target: number | undefined;
  private closed = false;

  constructor(private readonly options: IndexPickerOptions) {
    this.slots = [];
    for (let index = 0; index < options.limit; index++) this.slots.push(this.slotButton(index));
    // Tab で入ったときの行（まだ選んでいないとき）
    const first = this.firstChoice();
    if (first) first.tabIndex = 0;
    const list = h(
      'div',
      { class: 'index-picker-list', role: 'radiogroup', 'aria-label': '番号', 'aria-describedby': `${this.id}-plan` },
      ...this.slots,
    );
    list.addEventListener('keydown', (event) => {
      const key = event.key === 'ArrowRight' ? 'ArrowDown' : event.key === 'ArrowLeft' ? 'ArrowUp' : event.key;
      const choices = this.slots.filter((slot) => !slot.disabled);
      if (!moveFocusInList(choices, key)) return;
      event.preventDefault();
      const focused = document.activeElement;
      if (focused instanceof HTMLButtonElement) this.select(Number(focused.dataset.index));
    });
    this.plan = h('div', { class: 'index-picker-plan', id: `${this.id}-plan`, 'aria-live': 'polite' }, '番号を選んでください。');
    this.note = h('div', { class: 'index-picker-note', hidden: true });
    const cancel = h('button', { type: 'button', class: 'item-button', 'data-focus': 'index-cancel' }, INDEX_PICKER_CANCEL);
    cancel.addEventListener('click', () => this.close());
    this.confirm = h('button', { type: 'button', class: 'item-button primary', disabled: true, 'data-focus': 'index-confirm' }, INDEX_PICKER_MOVE);
    this.confirm.addEventListener('click', () => {
      const target = this.target;
      if (target === undefined) return;
      const mode = this.mode(target);
      this.close();
      options.onConfirm(target, mode);
    });
    const title = `${options.noun}「${options.name}」の番号を変える`;
    this.element = h(
      'div',
      { class: 'index-picker', role: 'dialog', 'aria-label': title, id: this.id },
      h('div', { class: 'index-picker-title' }, title),
      list,
      this.plan,
      this.note,
      h('div', { class: 'index-picker-footer' }, cancel, this.confirm),
    );
    this.element.addEventListener('keydown', (event) => {
      if (event.key !== 'Escape') return;
      event.preventDefault();
      event.stopPropagation();
      this.close();
    });
  }

  /** 選んでいる番号 */
  get selected(): number | undefined {
    return this.target;
  }

  /** 最初の選べる番号（今の番号の次から）にフォーカスする。element を置いたあとに呼ぶ */
  focus(): void {
    const slot = this.target === undefined ? this.firstChoice() : this.slots[this.target];
    (slot ?? this.confirm).focus();
  }

  private firstChoice(): HTMLButtonElement | undefined {
    const choices = this.slots.filter((slot) => !slot.disabled);
    return choices.find((slot) => Number(slot.dataset.index) > this.options.current) ?? choices[0];
  }

  /** 番号を選ぶ（今の番号と範囲の外は選べない） */
  select(target: number): void {
    if (target === this.options.current || target < 0 || target >= this.options.limit) return;
    this.target = target;
    for (const slot of this.slots) {
      const checked = Number(slot.dataset.index) === target;
      slot.setAttribute('aria-checked', checked ? 'true' : 'false');
      slot.tabIndex = checked ? 0 : -1;
    }
    const mode = this.mode(target);
    this.plan.textContent = indexPlanText(target, this.options);
    const note = this.noteText(target, mode);
    this.note.hidden = !note;
    this.note.textContent = note ?? '';
    this.confirm.disabled = false;
    this.confirm.textContent = mode === 'move' ? INDEX_PICKER_MOVE : INDEX_PICKER_SWAP;
  }

  /** 閉じる（element を外し、returnFocus にフォーカスを戻す） */
  close(): void {
    if (this.closed) return;
    this.closed = true;
    this.element.remove();
    this.options.returnFocus?.focus();
    this.options.onClose?.();
  }

  private mode(target: number): IndexMode {
    return this.options.used.has(target) ? 'swap' : 'move';
  }

  private noteText(target: number, mode: IndexMode): string | null {
    const note = this.options.note;
    if (note === undefined) return null;
    const text = typeof note === 'string' ? note : note(target, mode, this.options.used.get(target));
    return text ? text : null;
  }

  private slotButton(index: number): HTMLButtonElement {
    const current = index === this.options.current;
    const used = !current && this.options.used.has(index);
    const button = h(
      'button',
      {
        type: 'button',
        class: `index-picker-slot${current ? ' current' : used ? ' used' : ' free'}`,
        role: 'radio',
        'aria-checked': 'false',
        tabindex: '-1',
        disabled: current,
        'data-index': index,
      },
      h('span', { class: 'index-picker-number' }, String(index)),
      h('span', { class: 'index-picker-state' }, indexSlotLabel(index, this.options)),
    );
    button.addEventListener('click', () => this.select(index));
    return button;
  }
}
