// コンボの節（spec.md の「ファイルの種類ごと」の combos/）。同時に押すキー（追加・削除。最大 4）と出すキー。
import type { ComboSnapshot, ProfileSnapshot } from '../protocol';
import { h } from './dom';
import { ItemSection, type ItemSectionOptions, type ListEntry } from './itemList';
import { comboView, type ComboView } from './itemsModel';

/** 同時に押すキーの数の上限（Vial のコンボは 4 つ） */
export const MAX_COMBO_KEYS = 4;

export class ComboEditor extends ItemSection<ComboSnapshot, ComboView> {
  constructor(options: ItemSectionOptions) {
    super(options, { kind: 'combo', title: 'コンボ', namePlaceholder: 'Left Bracket', className: 'combo-editor' });
  }

  protected items(snapshot: ProfileSnapshot): ComboSnapshot[] | undefined {
    return snapshot.combos;
  }

  protected entry(combo: ComboSnapshot, view: ComboView): ListEntry {
    return { name: combo.name, index: combo.index, detail: view.description.value, file: combo.file };
  }

  protected view(combo: ComboSnapshot): ComboView {
    return comboView(combo, this.pending);
  }

  protected shape(view: ComboView): unknown {
    return view.triggers.keys.length;
  }

  protected buildDetail(_combo: ComboSnapshot, body: HTMLElement): void {
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
    body.append(
      h('div', { class: 'combo-triggers-part' }, heading, triggers, add),
      this.keyField({ label: '出すキー', focus: 'output', context: 'comboOutput', entry: () => this.current.output }),
    );
  }
}
