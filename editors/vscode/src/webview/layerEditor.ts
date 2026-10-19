// 下のペイン: 選んでいるレイヤーの編集画面。手ごと・グループ（段・親指）ごとにキー入力欄を並べ、最後にエンコーダ。
import type { Diagnostic } from '../protocol';
import { h } from './dom';
import type { HostClient } from './hostClient';
import { KeyInput } from './keyInput';
import { groupLabel, HAND_LABEL, type Slot } from './model';

export type LayerEditorOptions = {
  host: HostClient;
  onCommit: (slot: Slot, text: string) => void;
  onFocus: (slotId: string) => void;
  decorate?: (element: HTMLElement, slot: Slot) => void;
};

type Field = { slot: Slot; element: HTMLElement; input: KeyInput };

export class LayerEditor {
  readonly element: HTMLElement;
  private readonly fields = new Map<string, Field>();

  constructor(private readonly options: LayerEditorOptions) {
    this.element = h('div', { class: 'layer-editor' });
  }

  get inputs(): ReadonlyMap<string, KeyInput> {
    return new Map([...this.fields].map(([id, field]) => [id, field.input]));
  }

  setSlots(slots: Slot[]): void {
    this.fields.clear();
    this.element.replaceChildren();
    for (const hand of ['left', 'right'] as const) {
      const section = h('section', { class: 'hand' }, h('h3', {}, HAND_LABEL[hand]));
      const keys = slots.filter((slot) => slot.hand === hand && slot.key);
      const groups = [...new Set(keys.map((slot) => slot.key!.group))];
      for (const group of groups) {
        const row = h('div', { class: 'group' }, h('div', { class: 'group-label' }, groupLabel(group)));
        const fields = h('div', { class: 'fields' });
        for (const slot of keys.filter((s) => s.key!.group === group)) fields.append(this.field(slot));
        row.append(fields);
        section.append(row);
      }
      const encoders = slots.filter((slot) => slot.hand === hand && slot.encoder);
      if (encoders.length > 0) {
        const row = h('div', { class: 'group' }, h('div', { class: 'group-label' }, 'エンコーダ'));
        const fields = h('div', { class: 'fields' });
        for (const slot of encoders) fields.append(this.field(slot));
        row.append(fields);
        section.append(row);
      }
      this.element.append(section);
    }
  }

  private field(slot: Slot): HTMLElement {
    const input = new KeyInput({
      context: slot.context,
      host: this.options.host,
      label: `${HAND_LABEL[slot.hand]} ${slot.encoder ? 'エンコーダの' : ''}${slot.label}`,
      placeholder: '（なし）',
      onCommit: (text) => this.options.onCommit(slot, text),
    });
    const label = h('label', { class: 'field-label', title: slot.address.path.join('.') }, slot.label);
    const element = h('div', { class: 'field', 'data-slot': slot.id }, label, input.element);
    label.addEventListener('click', () => input.focus());
    input.input.addEventListener('focus', () => this.options.onFocus(slot.id));
    this.options.decorate?.(input.input, slot);
    this.fields.set(slot.id, { slot, element, input });
    return element;
  }

  update(slotId: string, text: string, diagnostics: readonly Diagnostic[], changed: boolean): void {
    const field = this.fields.get(slotId);
    if (!field) return;
    field.input.setValue(text);
    field.input.setDiagnostics(diagnostics);
    field.element.classList.toggle('changed', changed);
  }

  setSelected(slotId: string | undefined): void {
    for (const [id, field] of this.fields) field.element.classList.toggle('selected', id === slotId);
  }

  /** その欄へ移る（図のキーを押したとき） */
  reveal(slotId: string): void {
    const field = this.fields.get(slotId);
    if (!field) return;
    field.element.scrollIntoView?.({ block: 'nearest', behavior: 'smooth' });
    field.input.focus();
    field.element.classList.remove('flash');
    void field.element.offsetWidth; // アニメーションをやり直す
    field.element.classList.add('flash');
  }
}
