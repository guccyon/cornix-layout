// コンボの節（spec.md の「ファイルの種類ごと」の combos/）。同時に押すキー（追加・削除。最大 4）と出すキー（と、その注記）。
// v0.3:
// - 「図から選ぶ」: 上の図のキーを押して、同時に押すキーに足す（App#pickKey。選んでいる間はボタンの文字が変わり、もう一度押すか Esc で抜ける）。
//   まだ NoKey の欄（作ったばかりのコンボ）があればそこに入れ、なければ末尾に足す（insert）
// - 押せないコンボ（snapshot の reachable が false。protocol.md の 13.2）は、一覧の行と詳細に ⚠ を付ける
import type { ComboSnapshot, ProfileSnapshot } from '../protocol';
import { h, nodes } from './dom';
import { ItemSection, type ItemSectionOptions, type ListEntry } from './itemList';
import { comboView, type ComboView, type KeyEntry } from './itemsModel';

/** 同時に押すキーの数の上限（Vial のコンボは 4 つ） */
export const MAX_COMBO_KEYS = 4;

/** 押せないコンボの説明 */
export const UNREACHABLE_MESSAGE = 'トリガーのキーがすべてそろうレイヤーがありません';

export const PICK_LABEL = '図から選ぶ';
export const PICKING_LABEL = '選んでいます…（Esc で戻る）';

export type ComboEditorOptions = ItemSectionOptions & {
  /** 図のキーを押して選ぶ状態に入る（App#pickKey）。戻り値は選ばずに抜ける関数。なければ「図から選ぶ」を出さない */
  pickKey?: (onPick: (text: string) => void) => () => void;
};

/** 何もしないキー（作ったばかりのコンボの欄。図から選んだキーはまずここに入れる） */
const NO_KEY_TEXTS = new Set(['NoKey', 'KC_NO', 'XXXXXXX']);

export function isNoKey(entry: KeyEntry): boolean {
  if (NO_KEY_TEXTS.has(entry.text)) return true;
  return !entry.changed && entry.saved?.kind === 'noKey';
}

export class ComboEditor extends ItemSection<ComboSnapshot, ComboView> {
  private readonly pickKey: ComboEditorOptions['pickKey'];
  /** 図から選んでいる間の、抜ける関数と選んでいるコンボの名前 */
  private picking: { stop: () => void; name: string } | undefined;

  constructor(options: ComboEditorOptions) {
    super(options, { kind: 'combo', title: 'コンボ', namePlaceholder: 'Left Bracket', className: 'combo-editor' });
    this.pickKey = options.pickKey;
  }

  /** 図から選んでいる（テスト用） */
  get isPicking(): boolean {
    return this.picking !== undefined;
  }

  protected items(snapshot: ProfileSnapshot): ComboSnapshot[] | undefined {
    return snapshot.combos;
  }

  protected entry(combo: ComboSnapshot, view: ComboView): ListEntry {
    return {
      name: combo.name,
      index: combo.index,
      detail: view.description.value,
      file: combo.file,
      mark: combo.reachable === false ? { text: '⚠', title: UNREACHABLE_MESSAGE } : null,
    };
  }

  protected view(combo: ComboSnapshot): ComboView {
    return comboView(combo, this.pending);
  }

  protected shape(view: ComboView): unknown {
    return view.triggers.keys.length;
  }

  protected buildDetail(combo: ComboSnapshot, body: HTMLElement): void {
    body.append(
      ...nodes(
        combo.reachable === false && h('div', { class: 'combo-unreachable', role: 'note' }, h('span', { class: 'item-mark', 'aria-hidden': 'true' }, '⚠'), UNREACHABLE_MESSAGE),
        this.valueField<string>({
          label: '説明',
          focus: 'description',
          type: 'text',
          entry: () => this.current.description,
          parse: (text) => ({ value: text }),
          removable: true,
          placeholder: () => '（なし）',
          className: 'item-description',
        }),
      ),
    );
    const triggers = h('div', { class: 'combo-triggers' });
    const count = this.current.triggers.keys.length;
    for (let i = 0; i < count; i++) {
      triggers.append(
        this.keyField({
          label: `キー ${i + 1}`,
          focus: `trigger:${i}`,
          context: 'comboTrigger',
          entry: () => this.current.triggers.keys[i]!,
          remove: {
            label: `同時に押すキー ${i + 1} を消す`,
            onClick: () => this.edit({ op: 'remove', address: this.current.triggers.keys[i]!.address }, 'add-trigger'),
          },
        }),
      );
    }
    const add = h('button', { type: 'button', class: 'item-button small', 'data-focus': 'add-trigger', disabled: count >= MAX_COMBO_KEYS }, 'キーを足す');
    add.addEventListener('click', () => {
      const list = this.current.triggers;
      if (list.keys.length >= MAX_COMBO_KEYS) return;
      this.edit({ op: 'insert', address: list.address, index: list.keys.length, value: 'NoKey' }, `trigger:${list.keys.length}`);
    });
    const heading = h('div', { class: 'item-subheading' }, `同時に押すキー（最大 ${MAX_COMBO_KEYS}）`);
    this.addUpdater(() => heading.classList.toggle('changed', this.current.triggers.restructured));
    const buttons = h('div', { class: 'combo-trigger-buttons' }, add);
    if (this.pickKey) buttons.append(this.pickButton(combo.name));
    body.append(
      h('div', { class: 'combo-triggers-part' }, heading, triggers, buttons),
      this.keyField({ label: '出すキー', focus: 'output', context: 'comboOutput', entry: () => this.current.output, note: true }),
    );
  }

  /** 「図から選ぶ」。選んでいる間は文字を変え（aria-pressed）、もう一度押すと抜ける */
  private pickButton(name: string): HTMLElement {
    const button = h(
      'button',
      { type: 'button', class: 'item-button small combo-pick', 'data-focus': 'pick-trigger', title: '上の図のキーを押して、同時に押すキーに足す' },
      PICK_LABEL,
    );
    const render = (): void => {
      const active = this.picking?.name === name;
      const keys = this.current.triggers.keys;
      button.textContent = active ? PICKING_LABEL : PICK_LABEL;
      button.setAttribute('aria-pressed', String(active));
      button.classList.toggle('picking', active);
      // 入れる欄がない（4 つとも NoKey でない）なら押せない。選んでいる間は抜けるために押せる
      button.disabled = !active && keys.length >= MAX_COMBO_KEYS && !keys.some(isNoKey);
    };
    button.addEventListener('click', () => {
      const same = this.picking?.name === name;
      if (this.picking) this.stopPicking();
      if (!same) this.startPicking(name);
      render();
    });
    this.addUpdater(render);
    return button;
  }

  private startPicking(name: string): void {
    const stop = this.pickKey!((text) => {
      // 図で選んで抜けた（App が選ぶ状態を抜けてから呼ぶ）
      this.endPicking();
      this.addTrigger(name, text);
    });
    this.picking = { stop, name };
    // App は Esc で選ぶ状態を抜ける（onPick は呼ばない）ので、ここでもボタンを戻す
    document.addEventListener('keydown', this.onEscape, true);
  }

  /** 選ばずに抜ける */
  stopPicking(): void {
    const picking = this.picking;
    this.endPicking();
    picking?.stop();
  }

  private endPicking(): void {
    this.picking = undefined;
    document.removeEventListener('keydown', this.onEscape, true);
    this.render();
  }

  private readonly onEscape = (event: KeyboardEvent): void => {
    if (event.key === 'Escape' && this.picking) this.stopPicking();
  };

  /** 選んだキーを、選び始めたコンボの同時に押すキーに入れる（NoKey の欄があればそこ、なければ末尾に足す） */
  private addTrigger(name: string, text: string): void {
    if (this.selected !== name || !text) return;
    const list = this.current.triggers;
    const empty = list.keys.find(isNoKey);
    if (empty) {
      this.set(empty.address, text);
      return;
    }
    if (list.keys.length >= MAX_COMBO_KEYS) return;
    this.edit({ op: 'insert', address: list.address, index: list.keys.length, value: text }, 'pick-trigger');
  }
}
