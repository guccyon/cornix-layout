// マクロの節（spec.md の「ファイルの種類ごと」の macros/）。手順の並び（追加・削除・上下に動かす）と、手順ごとの
// tap / down / up のキー（追加・削除）・delay のミリ秒・text の文字。preset: のマクロは手順を summary で読むだけにして、preset の名前を
// 同梱のショートカットの木から選び直すか、打って直せる。
// v0.3: preset: のマクロに「手順に展開」（tasks-v0.3.md の決めたことの 6）。itemEdit の expandPreset をホストに渡し、ホストが確認してすぐ書く。
// v0.5: 一覧は使っているマクロだけ（未保存の変更を当てた番号の順）。「追加」の「同梱から」で選んだ同梱のマクロは、
// その preset: のマクロを作る（itemEdit の create に preset。名前はラベル。同じ名前があれば名前の欄を開く。ホストが確認してすぐ書く）。
import type { MacroSnapshot, MacroStepValue, ProfileSnapshot } from '../protocol';
import { arrangeItems, snapshotItems } from '../itemIndex';
import { h } from './dom';
import { ItemSection, parseMilliseconds, type ItemSectionOptions, type ListEntry } from './itemList';
import { macroView, type MacroView, type StepView } from './itemsModel';
import { loadShortcutTree, PresetPicker, type PresetEntry } from './presetPicker';

export const STEP_ACTION_LABEL: Record<StepView['action'], string> = {
  tap: 'タップ（tap）',
  down: '押す（down）',
  up: '離す（up）',
  delay: '待つ（delay）',
  text: '文字（text）',
};

/** 手順を足すときの最初の値（キーは NoKey にしておいて、あとで選ぶ） */
export function newStep(action: StepView['action']): MacroStepValue {
  switch (action) {
    case 'delay':
      return { action: 'delay', duration: 100 };
    case 'text':
      return { action: 'text', content: '' };
    default:
      return { action, keys: ['NoKey'] };
  }
}

/** text の文字（ASCII の印字できる文字だけ。spec.md の「ファイルの種類ごと」） */
export function parseMacroText(text: string): { value: string } | { problem: string } {
  if (!/^[\x20-\x7e]*$/.test(text)) return { problem: 'ASCII の文字だけを書けます' };
  return { value: text };
}

let nextToggleId = 1;

export class MacroEditor extends ItemSection<MacroSnapshot, MacroView> {
  /** マクロのキーの候補を「すべて出す」（レイヤー操作・マクロなども出す） */
  private showAll = false;
  private addAction: StepView['action'] = 'tap';

  constructor(options: ItemSectionOptions) {
    super(options, {
      kind: 'macro',
      title: 'マクロ',
      namePlaceholder: 'Bracket Pair',
      className: 'macro-editor',
      bundled: 'macro',
    });
  }

  protected items(snapshot: ProfileSnapshot): MacroSnapshot[] | undefined {
    return snapshot.macros ? arrangeItems(snapshotItems(snapshot, 'macro'), this.pending).used : undefined;
  }

  /** 同梱のマクロを preset: のマクロとして作る。同じ名前があれば、名前を入れた追加の欄を開く */
  protected override pickBundled(entry: PresetEntry): void {
    if (this.itemNames().includes(entry.label)) {
      this.openCreateForm(entry.label, { preset: entry.name, message: `マクロ「${entry.label}」はすでにあります。別の名前にしてください` });
      return;
    }
    this.createItem({ op: 'create', kind: 'macro', name: entry.label, preset: entry.name });
  }

  protected entry(macro: MacroSnapshot, view: MacroView): ListEntry {
    return { name: macro.name, index: macro.index, detail: view.description.value ?? (macro.preset ? `preset: ${macro.preset}` : null), file: macro.file };
  }

  protected view(macro: MacroSnapshot): MacroView {
    return macroView(macro, this.pending);
  }

  protected shape(view: MacroView): unknown {
    return [view.preset !== null, view.steps.map((step) => (step.action === 'tap' || step.action === 'down' || step.action === 'up' ? [step.action, step.keys.keys.length] : step.action))];
  }

  protected buildDetail(macro: MacroSnapshot, body: HTMLElement): void {
    body.append(
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
    );
    if (this.current.preset) {
      body.append(this.presetPart(macro));
      return;
    }
    body.append(this.stepsPart());
  }

  private presetPart(macro: MacroSnapshot): HTMLElement {
    const field = this.valueField<string>({
      label: 'preset',
      focus: 'preset',
      type: 'text',
      entry: () => this.current.preset!,
      parse: (text) => (text.trim() === '' ? { problem: '同梱のマクロの名前を入れてください' } : { value: text.trim() }),
      hint: () => '同梱のマクロの名前（アプリ:カテゴリ:ラベル）',
    });
    const picker = new PresetPicker({
      loadTree: () => loadShortcutTree(this.host),
      current: () => this.current.preset?.value ?? null,
      onPick: (name) => this.set(this.current.preset!.address, name),
    });
    // 展開は保存済みの preset で書く（未保存の変更があれば、ホストが先に保存を促す）
    const expand = h(
      'button',
      { type: 'button', class: 'item-button', 'data-focus': 'expand-preset', title: 'preset: の行を同梱の定義の手順（sequence:）に置き換えて、手順を直せるようにする' },
      '手順に展開',
    );
    expand.addEventListener('click', () => this.host.itemEdit({ op: 'expandPreset', kind: 'macro', name: macro.name }));
    return h(
      'div',
      { class: 'macro-preset' },
      field,
      picker.element,
      h('div', { class: 'macro-summary-title' }, '手順（同梱の定義。読むだけ）', expand),
      h('ol', { class: 'macro-summary' }, ...macro.summary.map((line) => h('li', {}, line))),
    );
  }

  private stepsPart(): HTMLElement {
    const all = h('input', { type: 'checkbox', id: `macro-all-${nextToggleId++}`, 'data-focus': 'all' });
    all.checked = this.showAll;
    all.addEventListener('change', () => {
      this.showAll = all.checked;
    });
    const steps = h('ol', { class: 'macro-steps' });
    this.current.steps.forEach((step, index) => steps.append(this.stepRow(step, index)));
    const select = h(
      'select',
      { class: 'item-select', 'aria-label': '足す手順の種類', 'data-focus': 'add-step-kind' },
      ...(['tap', 'down', 'up', 'delay', 'text'] as const).map((action) => h('option', { value: action, selected: action === this.addAction }, STEP_ACTION_LABEL[action])),
    );
    select.addEventListener('change', () => {
      this.addAction = select.value as StepView['action'];
    });
    const add = h('button', { type: 'button', class: 'item-button', 'data-focus': 'add-step' }, '手順を足す');
    add.addEventListener('click', () => {
      const index = this.current.steps.length;
      this.edit({ op: 'insert', address: this.current.stepsAddress, index, value: newStep(this.addAction) }, firstFocus(this.addAction, index));
    });
    const heading = h('div', { class: 'item-subheading' }, h('span', { class: 'macro-steps-title' }, '手順'));
    const title = heading.firstElementChild as HTMLElement;
    this.addUpdater(() => title.classList.toggle('changed', this.current.restructured));
    heading.append(h('label', { class: 'item-toggle', for: all.id }, all, 'キーの候補をすべて出す'));
    return h('div', { class: 'macro-steps-part' }, heading, steps, h('div', { class: 'item-toolbar' }, select, add));
  }

  private stepRow(step: StepView, index: number): HTMLElement {
    const count = this.current.steps.length;
    const button = (label: string, text: string, focus: string, onClick: () => void, disabled = false): HTMLElement => {
      const element = h('button', { type: 'button', class: 'icon-button', title: label, 'aria-label': label, 'data-focus': focus, disabled }, text);
      element.addEventListener('click', onClick);
      return element;
    };
    const address = this.current.stepsAddress;
    const controls = h(
      'span',
      { class: 'step-controls' },
      button(`手順 ${index + 1} を上へ`, '↑', `step:${index}:up`, () => this.edit({ op: 'move', address, from: index, to: index - 1 }, `step:${index - 1}:up`), index === 0),
      button(`手順 ${index + 1} を下へ`, '↓', `step:${index}:down`, () => this.edit({ op: 'move', address, from: index, to: index + 1 }, `step:${index + 1}:down`), index === count - 1),
      button(`手順 ${index + 1} を消す`, '×', `step:${index}:remove`, () => this.edit({ op: 'remove', address: this.current.steps[index]!.address }, count > 1 ? `step:${Math.min(index, count - 2)}:remove` : 'add-step')),
    );
    const row = h('li', { class: 'macro-step', 'data-step': index }, h('span', { class: 'step-number' }, `${index + 1}`), h('span', { class: 'step-action' }, STEP_ACTION_LABEL[step.action]));
    const content = h('div', { class: 'step-content' });
    if (step.action === 'delay') {
      content.append(
        this.valueField<number>({
          label: 'ミリ秒',
          focus: `step:${index}:duration`,
          type: 'number',
          entry: () => (this.current.steps[index] as Extract<StepView, { action: 'delay' }>).duration,
          parse: parseMilliseconds,
        }),
      );
    } else if (step.action === 'text') {
      content.append(
        this.valueField<string>({
          label: '文字',
          focus: `step:${index}:content`,
          type: 'text',
          entry: () => (this.current.steps[index] as Extract<StepView, { action: 'text' }>).content,
          parse: parseMacroText,
        }),
      );
    } else {
      const keysOf = () => (this.current.steps[index] as Extract<StepView, { action: 'tap' | 'down' | 'up' }>).keys;
      step.keys.keys.forEach((_, j) => {
        content.append(
          this.keyField({
            label: `手順 ${index + 1} のキー ${j + 1}`,
            visibleLabel: `キー ${j + 1}`,
            focus: `step:${index}:key:${j}`,
            context: 'macroKey',
            candidateParams: () => ({ all: this.showAll }),
            entry: () => keysOf().keys[j]!,
            className: 'step-key',
            remove: {
              label: `手順 ${index + 1} のキー ${j + 1} を消す`,
              onClick: () => this.edit({ op: 'remove', address: keysOf().keys[j]!.address }, `step:${index}:add-key`),
            },
          }),
        );
      });
      const addKey = h('button', { type: 'button', class: 'item-button small', 'data-focus': `step:${index}:add-key` }, 'キーを足す');
      addKey.addEventListener('click', () => {
        const keys = keysOf();
        this.edit({ op: 'insert', address: keys.address, index: keys.keys.length, value: 'NoKey' }, `step:${index}:key:${keys.keys.length}`);
      });
      content.append(addKey);
    }
    row.append(content, controls);
    this.addUpdater(() => row.classList.toggle('changed', this.current.steps[index]?.changed ?? false));
    return row;
  }
}

function firstFocus(action: StepView['action'], index: number): string {
  if (action === 'delay') return `step:${index}:duration`;
  if (action === 'text') return `step:${index}:content`;
  return `step:${index}:key:0`;
}
