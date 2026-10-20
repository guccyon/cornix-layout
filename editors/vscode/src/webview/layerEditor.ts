// 下のペイン: 選んでいるレイヤーの編集画面。左手の節の下に右手の節を置き、手ごとにグループ（段・親指）ごとのキー入力欄を並べ、最後にエンコーダ。
// 欄の並べ方（広ければ横 1 列、狭ければ折り返す）は media/webview.css の .fields。
// 欄ごとに、キー入力欄（組み立て欄付き）・注記の 1 行の欄・「割り当てを消す」を置く（注記の欄と消すボタンは、選んでいる欄と注記のある欄だけに見せる。CSS）。
// キーの欄のラベルは位置の名前（position_map の名前。紫）で、名前を書いている場所の分かる位置（v0.2 のサーバー）は「名前を変える」で書き換えられる。
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
  /** 「割り当てを消す」を押した。なければボタンを出さない */
  onRemove?: (slotId: string) => void;
  /** 注記を決めた（空なら消す）。なければ注記の欄を出さない */
  onNote?: (slotId: string, note: string) => void;
  /** 位置の名前を変える。名前の決まりに合わなければその理由を返す（そのときは欄を閉じない） */
  onRenamePosition?: (slotId: string, to: string) => string | null;
  /** 組み立て欄の LT のレイヤーの選び先 */
  layers?: () => readonly { index: number; name: string }[];
};

/** 欄 1 つの描き方 */
export type FieldView = {
  text: string;
  diagnostics: readonly Diagnostic[];
  /** 割り当てか注記に未保存の変更がある */
  changed: boolean;
  /** 今の注記（なければ空） */
  note: string;
};

type Field = {
  slot: Slot;
  element: HTMLElement;
  input: KeyInput;
  labelBox: HTMLElement;
  label: HTMLElement;
  note?: HTMLInputElement;
  remove?: HTMLButtonElement;
  /** 決まっている注記 */
  committedNote: string;
  /** 注記を打っている途中 */
  noteEditing: boolean;
  /** 位置の名前を変えている途中の入力欄 */
  rename?: HTMLInputElement;
};

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

  /** 作り直さずに欄の中身（保存済みの値など）だけを差し替える。並びと Address は同じであること */
  replaceSlots(slots: Slot[]): void {
    for (const slot of slots) {
      const field = this.fields.get(slot.id);
      if (field) field.slot = slot;
    }
  }

  private group(label: string, slots: Slot[]): HTMLElement {
    const fields = h('div', { class: 'fields' });
    for (const slot of slots) fields.append(this.field(slot));
    return h('div', { class: 'group' }, h('div', { class: 'group-label' }, label), fields);
  }

  private field(slot: Slot): HTMLElement {
    const removable = !!this.options.onRemove;
    const input = new KeyInput({
      context: slot.context,
      host: this.options.host,
      label: slotLabel(slot),
      placeholder: '（なし）',
      onCommit: (text) => this.options.onCommit(slot.id, text),
      builder: this.options.layers ? { layers: this.options.layers } : {},
      ...(removable ? { emptyHint: '割り当てを消すには、欄の ✕（割り当てを消す）を押してください' } : {}),
    });
    const label = h(
      'label',
      { class: `field-label${slot.key ? ' position-label' : ''}`, for: input.inputId, title: slot.address.path.join('.') },
      slot.label,
    );
    const labelBox = h('span', { class: 'field-label-box' }, label);
    const field: Field = { slot, element: h('div'), input, labelBox, label, committedNote: '', noteEditing: false };
    if (slot.key?.positionAddress && this.options.onRenamePosition) {
      const rename = h(
        'button',
        { type: 'button', class: 'rename-position', title: '位置の名前を変える', 'aria-label': `位置の名前 ${slot.label} を変える` },
        '✎',
      );
      rename.addEventListener('click', () => this.startRename(slot.id));
      labelBox.append(rename);
    }
    const extra = h('div', { class: 'field-extra' });
    if (this.options.onNote) {
      const note = h('input', {
        type: 'text',
        class: 'note-input',
        placeholder: '注記',
        'aria-label': `${slotLabel(slot)}の注記`,
        spellcheck: 'false',
        autocomplete: 'off',
      });
      note.addEventListener('focus', () => this.options.onFocus(slot.id));
      note.addEventListener('input', () => (field.noteEditing = true));
      note.addEventListener('keydown', (event) => {
        if (event.key === 'Enter') {
          event.preventDefault();
          this.commitNote(field);
        } else if (event.key === 'Escape' && field.noteEditing) {
          event.preventDefault();
          event.stopPropagation();
          field.noteEditing = false;
          note.value = field.committedNote;
        }
      });
      note.addEventListener('blur', () => this.commitNote(field));
      field.note = note;
      extra.append(note);
    }
    if (removable) {
      const remove = h(
        'button',
        { type: 'button', class: 'remove-assignment', title: '割り当てを消す（行ごと消して「書いていない」にする）', 'aria-label': `${slotLabel(slot)}の割り当てを消す` },
        '✕',
      );
      remove.addEventListener('focus', () => this.options.onFocus(slot.id));
      remove.addEventListener('click', () => this.options.onRemove?.(field.slot.id));
      field.remove = remove;
      extra.append(remove);
    }
    const main = h('div', { class: 'field-main' }, input.element, extra.childElementCount > 0 ? extra : null);
    const element = h('div', { class: 'field', 'data-slot': slot.id }, labelBox, main);
    field.element = element;
    input.input.addEventListener('focus', () => this.options.onFocus(slot.id));
    this.options.decorate?.(input, slot.id);
    this.fields.set(slot.id, field);
    return element;
  }

  private commitNote(field: Field): void {
    const note = field.note;
    if (!note || !field.noteEditing) return;
    field.noteEditing = false;
    const text = note.value.trim();
    note.value = text;
    if (text === field.committedNote) return;
    field.committedNote = text;
    this.options.onNote?.(field.slot.id, text);
  }

  /** 位置の名前を変える欄を開く（ラベルの ✎ か、位置の名前を出している図のキーから） */
  startRename(slotId: string): void {
    const field = this.fields.get(slotId);
    if (!field || !field.slot.key?.positionAddress || !this.options.onRenamePosition) return;
    if (field.rename) {
      field.rename.focus();
      return;
    }
    const input = h('input', {
      type: 'text',
      class: 'position-name-input',
      value: field.slot.label,
      'aria-label': `${HAND_LABEL[field.slot.hand]} ${field.slot.label} の位置の名前`,
      spellcheck: 'false',
      autocomplete: 'off',
    });
    const message = h('div', { class: 'position-name-message', role: 'alert', hidden: true });
    const box = h('span', { class: 'position-name-edit' }, input, message);
    let done = false;
    const finish = (save: boolean) => {
      if (done) return;
      const to = input.value.trim();
      if (save && to !== field.slot.label) {
        const error = this.options.onRenamePosition?.(slotId, to) ?? null;
        if (error) {
          message.textContent = error;
          message.hidden = false;
          input.setAttribute('aria-invalid', 'true');
          return;
        }
      }
      done = true;
      field.rename = undefined;
      box.replaceWith(field.labelBox);
    };
    input.addEventListener('keydown', (event) => {
      if (event.key === 'Enter') {
        event.preventDefault();
        finish(true);
        if (done) field.input.input.focus();
      } else if (event.key === 'Escape') {
        event.preventDefault();
        event.stopPropagation();
        done = false;
        input.value = field.slot.label;
        finish(false);
        field.input.input.focus();
      }
    });
    input.addEventListener('input', () => {
      message.hidden = true;
      input.removeAttribute('aria-invalid');
    });
    // 欄を離れたら、変えていれば決める（名前の決まりに合わなければ元に戻して閉じる）
    input.addEventListener('blur', () => {
      finish(true);
      if (!done) finish(false);
    });
    field.rename = input;
    field.labelBox.replaceWith(box);
    field.element.scrollIntoView?.({ block: 'nearest' });
    input.focus();
    input.select();
  }

  update(slotId: string, view: FieldView): void {
    const field = this.fields.get(slotId);
    if (!field) return;
    field.input.setValue(view.text);
    field.input.setDiagnostics(view.diagnostics);
    field.element.classList.toggle('changed', view.changed);
    field.element.classList.toggle('has-note', view.note !== '');
    field.element.classList.toggle('unassigned', view.text === '');
    field.committedNote = view.note;
    if (field.note) {
      if (!field.noteEditing && field.note.value !== view.note) field.note.value = view.note;
      // 割り当てのない位置には注記を書けない（注記は { key:, note: } の形でだけ書ける）
      field.note.disabled = view.text === '' && view.note === '';
    }
    if (field.remove) field.remove.disabled = view.text === '';
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
