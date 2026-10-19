// 下のペイン: 選んでいるレイヤーの編集画面。左手の節の下に右手の節を置き、手ごとにグループ（段・親指）ごとのキー入力欄を並べ、最後にエンコーダ。
// 欄の並べ方（広ければ横 1 列、狭ければ折り返す）は media/webview.css の .fields。
import type { Diagnostic } from '../protocol';
import { h } from './dom';
import type { HostClient } from './hostClient';
import { KeyInput } from './keyInput';
import { groupLabel, HAND_LABEL, slotLabel, type Slot } from './model';

export type LayerEditorOptions = {
  host: HostClient;
  /** 欄で値を決めた（欄は id で指す。作り直さずに slot の中身が変わることがあるため） */
  onCommit: (slotId: string, text: string) => void;
  onFocus: (slotId: string) => void;
  decorate?: (input: KeyInput, slotId: string) => void;
};

type Field = { element: HTMLElement; input: KeyInput };

export class LayerEditor {
  readonly element: HTMLElement;
  private readonly fields = new Map<string, Field>();

  constructor(private readonly options: LayerEditorOptions) {
    this.element = h('div', { class: 'layer-editor' });
  }

  get inputs(): ReadonlyMap<string, KeyInput> {
    return new Map([...this.fields].map(([id, field]) => [id, field.input]));
  }

  /** 欄を作り直す。前の欄は dispose する（外したときの blur で決めないように） */
  setSlots(slots: Slot[]): void {
    for (const field of this.fields.values()) field.input.dispose();
    this.fields.clear();
    this.element.replaceChildren();
    for (const hand of ['left', 'right'] as const) {
      const section = h('section', { class: 'hand' }, h('h3', {}, HAND_LABEL[hand]));
      const keys = slots.filter((slot) => slot.hand === hand && slot.key);
      const groups = [...new Set(keys.map((slot) => slot.key!.group))];
      for (const group of groups) {
        section.append(this.group(groupLabel(group), keys.filter((s) => s.key!.group === group)));
      }
      const encoders = slots.filter((slot) => slot.hand === hand && slot.encoder);
      if (encoders.length > 0) section.append(this.group('エンコーダ', encoders));
      this.element.append(section);
    }
  }

  private group(label: string, slots: Slot[]): HTMLElement {
    const fields = h('div', { class: 'fields' });
    for (const slot of slots) fields.append(this.field(slot));
    return h('div', { class: 'group' }, h('div', { class: 'group-label' }, label), fields);
  }

  private field(slot: Slot): HTMLElement {
    const input = new KeyInput({
      context: slot.context,
      host: this.options.host,
      label: slotLabel(slot),
      placeholder: '（なし）',
      onCommit: (text) => this.options.onCommit(slot.id, text),
    });
    const label = h('label', { class: 'field-label', for: input.inputId, title: slot.address.path.join('.') }, slot.label);
    const element = h('div', { class: 'field', 'data-slot': slot.id }, label, input.element);
    input.input.addEventListener('focus', () => this.options.onFocus(slot.id));
    this.options.decorate?.(input, slot.id);
    this.fields.set(slot.id, { element, input });
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
