// 上のペイン: Cornix のキーボード図。選んでいるレイヤーの割り当てを描き、キーを押すと onSelect（下の欄へ移る）。
// 2 役のキー（display の tap / hold）は上下に分けて描く。レイヤー操作も同じ形で、下の帯にレイヤー番号（MO は帯だけ）。割り当て済みのキーにアイコン（同梱のショートカットと preset: のマクロ）。
// マクロ・タップダンス・自分のショートカットは右上に小さな印（M・TD・★。model.ts の keyMark）。NoKey は何も描かない（空白）。
// KC_TRNS のキーには、レイヤー 0 の同じ位置の値を薄く描く（SlotView.base。protocol.md の 12.7）。
// 位置の名前の表示: 図の上のボタンで固定の切り替え、Alt を押している間だけ一時表示（ウィンドウがフォーカスを失ったら戻す）。
// 表示中はキーの面に割り当ての代わりに position_map の名前を紫で描き、読み上げも位置の名前にする。表示中にキーを押すと、
// 名前を変えられる位置（positionAddress のある位置）なら onRenamePosition（下の欄で名前を変える）。
// v0.3: 「位置の名前」のボタンにマウスを載せている間も出す。出している間は図の下に名前の出所（position_map.yaml）を 1 行。
// v0.3 の「全レイヤー」のトグルは v0.4 でやめた（下の欄の「キーごと」に置き換えた。issue #84）。
// コンボ: 図の上にコンボの番号のボタン。押す（固定）か載せている（一時）間、そのトリガーのキーを強調する（どの欄かは options.comboTargets）。
// 選ぶ状態（setPicking。App#pickKey）: 図の上に案内を出し、キーを押すと onPick（Esc で onPickCancel）。
// タップダンスは、キーの面を割り当てのある動作の数の窓に分けて描く（1 つは面全体、2 つ・3 つは横幅いっぱいの窓を上から順に
// 重ね、4 つは 2×2。順はタップ・ホールド・ダブルタップ・タップホールド）。エンコーダの帯では窓にせず、タップの札と「+残りの数」を並べる。
import type { Diagnostic, Hand, KeyValue } from '../protocol';
import { BOARD, ENCODERS, keyRect } from './cornixLayout';
import { h, nodes } from './dom';
import { iconElement } from './icons';
import {
  ENCODER_OPS,
  HAND_LABEL,
  keyAccessibleName,
  keyMark,
  severityOf,
  tapDanceWindows,
  windowLabels,
  type Slot,
} from './model';

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

/** v0.3: 図の上のコンボのボタン 1 つ */
export type ComboButton = { index: number; name: string; reachable?: boolean | undefined };

export type KeyboardViewOptions = {
  onSelect: (slotId: string) => void;
  /** 説明をつなぐ（欄は id で指す。作り直さずに slot の中身が変わることがあるため） */
  decorate?: (element: HTMLElement, slotId: string) => void;
  /** 位置の名前を表示している間にキーを押した（名前を変えられる位置だけ）。なければ onSelect */
  onRenamePosition?: (slotId: string) => void;
  /** Alt の一時表示を受ける窓（テストで差し替える。省くと window） */
  window?: Window;
  /** v0.3: コンボのトリガーのキーを割り当てた欄の id（強調する欄） */
  comboTargets?: (index: number) => ReadonlySet<string>;
  /** v0.3: コンボのボタンに説明をつなぐ */
  decorateCombo?: (element: HTMLElement, index: number) => void;
  /** v0.3: 選ぶ状態でキーを押した */
  onPick?: (slotId: string) => void;
  /** v0.3: 選ぶ状態で Esc を押した */
  onPickCancel?: () => void;
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
  /** 「位置の名前」のボタンにマウスを載せている間の一時表示 */
  private hovering = false;
  /** コンボのボタン（並びの中身が同じなら作り直さない） */
  private combos: ComboButton[] = [];
  private combosKey = '';
  private pinnedCombo: number | undefined;
  private hoveredCombo: number | undefined;
  /** 選ぶ状態（App#pickKey） */
  private pickingKey = false;
  private readonly toggle: HTMLButtonElement;
  private readonly comboBar: HTMLElement;
  private readonly positionHint: HTMLElement;
  private readonly pickBanner: HTMLElement;

  constructor(private readonly options: KeyboardViewOptions) {
    this.board = h('div', { class: 'board', style: `aspect-ratio: ${BOARD.width} / ${BOARD.height}` });
    this.toggle = h(
      'button',
      {
        type: 'button',
        class: 'position-toggle',
        'aria-pressed': 'false',
        title:
          'キーの面に位置の名前を出す（マウスを載せている間と Alt を押している間も出る）。名前は position_map.yaml のもので、ファイルを変えるとラベルが変わる。出している間にキーを押すと名前を変えられる',
      },
      '位置の名前',
    );
    this.toggle.addEventListener('click', () => this.setPinned(!this.pinned));
    this.toggle.addEventListener('mouseenter', () => this.setHovering(true));
    this.toggle.addEventListener('mouseleave', () => this.setHovering(false));
    this.comboBar = h('div', { class: 'combo-buttons', role: 'group', 'aria-label': 'コンボ', hidden: true });
    const toolbar = h('div', { class: 'keyboard-toolbar' }, this.comboBar, h('div', { class: 'keyboard-toggles' }, this.toggle));
    this.pickBanner = h('div', { class: 'pick-banner', role: 'status', hidden: true }, 'キーを押して選ぶ（Esc で戻る）');
    this.positionHint = h('div', { class: 'position-hint', 'aria-hidden': 'true' });
    // 最初から文を入れて行の高さを取っておく
    this.renderHint();
    this.element = h('div', { class: 'keyboard', role: 'group', 'aria-label': 'キーボード図' }, toolbar, this.pickBanner, this.board, this.positionHint);
    const win = options.window ?? window;
    win.addEventListener('keydown', (event) => {
      if (event.key === 'Alt') this.setHeld(true);
      if (event.key === 'Escape' && this.pickingKey) this.options.onPickCancel?.();
    });
    win.addEventListener('keyup', (event) => {
      if (event.key === 'Alt') this.setHeld(false);
    });
    win.addEventListener('blur', () => this.setHeld(false));
  }

  /** 位置の名前を出している（固定か、Alt・ボタンに載せている間の一時表示） */
  get showingPositions(): boolean {
    return this.pinned || this.held || this.hovering;
  }

  /** キーを並べた図の部分（コンボのボタンの説明をここに重ねないため） */
  get boardElement(): HTMLElement {
    return this.board;
  }

  /** 選ぶ状態 */
  get picking(): boolean {
    return this.pickingKey;
  }

  /** 強調しているコンボ（載せているもの、なければ固定したもの） */
  get activeCombo(): number | undefined {
    return this.hoveredCombo ?? this.pinnedCombo;
  }

  /** ボタンでの固定の切り替え */
  setPinned(pinned: boolean): void {
    this.pinned = pinned;
    this.renderAll();
  }

  /** Alt での一時表示 */
  setHeld(held: boolean): void {
    if (this.held === held) return;
    this.held = held;
    this.renderAll();
  }

  /** 「位置の名前」のボタンに載せている間の一時表示 */
  setHovering(hovering: boolean): void {
    if (this.hovering === hovering) return;
    this.hovering = hovering;
    this.renderAll();
  }

  /** 選ぶ状態の切り替え（案内と図の見た目） */
  setPicking(picking: boolean): void {
    this.pickingKey = picking;
    this.pickBanner.hidden = !picking;
    this.board.classList.toggle('picking', picking);
    this.element.classList.toggle('picking', picking);
  }

  private renderAll(): void {
    this.toggle.setAttribute('aria-pressed', String(this.pinned));
    this.toggle.classList.toggle('selected', this.pinned);
    this.board.classList.toggle('show-positions', this.showingPositions);
    this.renderHint();
    for (const id of this.elements.keys()) this.render(id);
  }

  /**
   * 位置の名前を出している間、図の下に名前の出所を 1 行（名前を変えられるなら、その入口も）。
   * 出していない間も行の高さは取っておき、文字だけを隠す（ホバーで出し入れしても下の欄が動かないように）
   */
  private renderHint(): void {
    const show = this.showingPositions;
    this.positionHint.classList.toggle('shown', show);
    this.positionHint.setAttribute('aria-hidden', String(!show));
    const renamable = !!this.options.onRenamePosition && [...this.slots.values()].some((slot) => slot.key?.positionAddress);
    this.positionHint.textContent = renamable
      ? '名前は position_map.yaml のもの。キーを押すとここで名前を変えられる'
      : '名前は position_map.yaml のもの。ファイルを変えるとラベルが変わる';
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
    this.renderHint();
    this.refreshCombo();
  }

  /** 作り直さずに欄の中身（保存済みの値など）だけを差し替える。並びと Address は同じであること */
  replaceSlots(slots: Slot[]): void {
    this.slots = new Map(slots.map((slot) => [slot.id, slot]));
  }

  /** v0.3: コンボのボタンを並べる（なければボタン列を出さない）。固定していたコンボがなくなれば外す */
  setCombos(combos: readonly ComboButton[]): void {
    const key = JSON.stringify(combos.map((c) => [c.index, c.name, c.reachable]));
    if (key === this.combosKey) {
      this.refreshCombo();
      return;
    }
    this.combosKey = key;
    this.combos = [...combos];
    if (!this.combos.some((c) => c.index === this.pinnedCombo)) this.pinnedCombo = undefined;
    this.hoveredCombo = undefined;
    this.comboBar.hidden = this.combos.length === 0;
    this.comboBar.replaceChildren(
      ...(this.combos.length > 0 ? [h('span', { class: 'combo-buttons-label', 'aria-hidden': 'true' }, 'コンボ')] : []),
      ...this.combos.map((combo) => this.comboButton(combo)),
    );
    this.refreshCombo();
  }

  private comboButton(combo: ComboButton): HTMLElement {
    const unreachable = combo.reachable === false;
    const button = h(
      'button',
      {
        type: 'button',
        class: `combo-button${unreachable ? ' unreachable' : ''}`,
        'data-combo': combo.index,
        'aria-pressed': 'false',
        'aria-label': `コンボ ${combo.index} ${combo.name}${unreachable ? '（押せない）' : ''}`,
      },
      ...nodes(unreachable && h('span', { class: 'combo-warning', 'aria-hidden': 'true' }, '⚠'), String(combo.index)),
    );
    button.addEventListener('click', () => this.setPinnedCombo(this.pinnedCombo === combo.index ? undefined : combo.index));
    button.addEventListener('mouseenter', () => {
      this.hoveredCombo = combo.index;
      this.refreshCombo();
    });
    button.addEventListener('mouseleave', () => {
      if (this.hoveredCombo === combo.index) this.hoveredCombo = undefined;
      this.refreshCombo();
    });
    this.options.decorateCombo?.(button, combo.index);
    return button;
  }

  /** コンボを固定して強調する（undefined で外す） */
  setPinnedCombo(index: number | undefined): void {
    this.pinnedCombo = index;
    this.refreshCombo();
  }

  /** 強調を描き直す（値が変わったとき App が呼ぶ） */
  refreshCombo(): void {
    const active = this.activeCombo;
    const targets = active !== undefined && this.options.comboTargets ? this.options.comboTargets(active) : new Set<string>();
    this.board.classList.toggle('combo-active', active !== undefined);
    for (const [id, element] of this.elements) element.classList.toggle('combo-trigger', targets.has(id));
    for (const button of this.comboBar.querySelectorAll<HTMLElement>('.combo-button')) {
      const index = Number(button.dataset.combo);
      button.setAttribute('aria-pressed', String(index === this.pinnedCombo));
      button.classList.toggle('selected', index === this.pinnedCombo);
      button.classList.toggle('active', index === active);
    }
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
      if (this.pickingKey && this.options.onPick) this.options.onPick(slot.id);
      else if (this.showingPositions && current.key?.positionAddress && this.options.onRenamePosition) this.options.onRenamePosition(slot.id);
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
    // 位置の名前の表示はキーにだけある（エンコーダはいつも割り当てを描く）
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
