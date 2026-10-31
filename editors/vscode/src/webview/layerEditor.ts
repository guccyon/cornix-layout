// 下のペイン: 選んでいるレイヤーの編集画面。区画（KeyboardSpec の sections の順。Cornix は左手の節の下に右手の節）ごとに
// グループ（段・親指）ごとのキー入力欄を並べ、最後にその区画のエンコーダ。
// 欄の並べ方（広ければ横 1 列、狭ければ折り返す）は media/webview.css の .fields。
// 欄ごとに、キー入力欄（組み立て欄付き）・注記の 1 行の欄・「割り当てを消す」を置く（注記の欄と消すボタンは、選んでいる欄と注記のある欄だけに見せる。CSS）。
// 割り当てのない欄は空白のまま（placeholder を出さない）。キー入力欄の候補の下には「同梱から選ぶ…」（v0.3）。
// キーの欄のラベルは位置の名前（position_map の名前。紫）で、名前を書いている場所の分かる位置（v0.2 のサーバー）は「名前を変える」で書き換えられる。
//
// v0.4（issue #84）: 「キー別」の並べ方（setPositions）。グループの並びと見出しはレイヤー別と同じで、位置ごとに位置の名前（紫）の下へ
// ファイルのあるレイヤーを index の順に「番号 名前」と入力欄の行で並べる。行の欄はレイヤー別の欄と同じ部品（入力欄・注記・消す・未保存の印）。
// 図で選んでいるレイヤーの行は current-layer（setCurrentLayer）。「▽ と空欄を畳む」（setFoldQuiet）では、▽ と書いていない行を
// 今のレイヤー・選んでいる行・未保存の行を除いて隠す。
import type { Diagnostic } from '../protocol';
import { h } from './dom';
import type { HostClient } from './hostClient';
import { KeyInput } from './keyInput';
import type { KeyboardSpec } from '../keyboard/spec';
import { groupLabel, layerTitle, sectionLabel, sectionOrder, slotLabel, type Slot } from './model';

export type LayerEditorOptions = {
  host: HostClient;
  /** 区画の並びと見出し、グループの見出し（App の spec） */
  keyboard: KeyboardSpec;
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
  /** v0.4: ▽ か書いていない（キー別の「畳む」で隠す行） */
  quiet?: boolean;
};

/** v0.4: キー別の位置 1 つ。slot は見出しに使う欄（位置の名前と名前を書く場所）、rows はレイヤーごとの欄（index の順） */
export type PositionSlots = { slot: Slot; rows: { layer: { index: number; name: string }; slot: Slot }[] };

/** 位置の名前を変える欄を出す場所（レイヤー別なら欄のラベル、キー別なら位置の見出し） */
type RenameTarget = { slot: Slot; labelBox: HTMLElement; element: HTMLElement; rename?: HTMLInputElement };

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
  /** キー別の行のレイヤー */
  layer?: number;
  /** 位置の名前を変える欄を出す場所 */
  target?: RenameTarget;
};

export class LayerEditor {
  readonly element: HTMLElement;
  private readonly fields = new Map<string, Field>();

  constructor(private readonly options: LayerEditorOptions) {
    this.element = h('div', { class: 'layer-editor' });
  }

  /** v0.4: キー別で描いている */
  get byKey(): boolean {
    return this.element.classList.contains('by-key');
  }

  get inputs(): ReadonlyMap<string, KeyInput> {
    return new Map([...this.fields].map(([id, field]) => [id, field.input]));
  }

  /** 欄を作り直す。前の欄は dispose する（外したときの blur で決めないように） */
  setSlots(slots: Slot[]): void {
    this.clear(false);
    const spec = this.options.keyboard;
    for (const id of sectionOrder(slots, spec)) {
      const keys = slots.filter((slot) => slot.section === id && slot.key);
      const encoders = slots.filter((slot) => slot.section === id && slot.encoder);
      if (keys.length === 0 && encoders.length === 0) continue;
      const section = h('section', { class: 'hand' }, h('h3', {}, sectionLabel(id, spec)));
      const groups = [...new Set(keys.map((slot) => slot.key!.group))];
      for (const group of groups) {
        section.append(this.group(groupLabel(group, spec), keys.filter((s) => s.key!.group === group)));
      }
      if (encoders.length > 0) section.append(this.group('エンコーダ', encoders));
      this.element.append(section);
    }
  }

  /** v0.4: キー別に並べる。位置の並び・グループの分け方は setSlots と同じ（positions は見出しの欄の position_map の順） */
  setPositions(positions: PositionSlots[]): void {
    this.clear(true);
    const spec = this.options.keyboard;
    for (const id of sectionOrder(positions.map((p) => p.slot), spec)) {
      const keys = positions.filter((p) => p.slot.section === id && p.slot.key);
      const encoders = positions.filter((p) => p.slot.section === id && p.slot.encoder);
      if (keys.length === 0 && encoders.length === 0) continue;
      const section = h('section', { class: 'hand' }, h('h3', {}, sectionLabel(id, spec)));
      const groups = [...new Set(keys.map((p) => p.slot.key!.group))];
      for (const group of groups) {
        section.append(this.positionGroup(groupLabel(group, spec), keys.filter((p) => p.slot.key!.group === group)));
      }
      if (encoders.length > 0) section.append(this.positionGroup('エンコーダ', encoders));
      this.element.append(section);
    }
  }

  /** v0.4: 図で選んでいるレイヤーの行を強調する（キー別だけ） */
  setCurrentLayer(index: number | undefined): void {
    for (const field of this.fields.values()) {
      field.element.classList.toggle('current-layer', field.layer !== undefined && field.layer === index);
    }
  }

  /** v0.4: ▽ と書いていない行を畳む（今のレイヤー・選んでいる行・未保存の行は残す。CSS） */
  setFoldQuiet(fold: boolean): void {
    this.element.classList.toggle('fold-quiet', fold);
  }

  private clear(byKey: boolean): void {
    for (const field of this.fields.values()) field.input.dispose();
    this.fields.clear();
    this.element.replaceChildren();
    this.element.classList.toggle('by-key', byKey);
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

  private positionGroup(label: string, positions: PositionSlots[]): HTMLElement {
    const blocks = h('div', { class: 'positions' });
    for (const position of positions) blocks.append(this.positionBlock(position));
    return h('div', { class: 'group' }, h('div', { class: 'group-label' }, label), blocks);
  }

  /** キー別の位置 1 つ: 位置の名前の見出しと、レイヤーごとの行 */
  private positionBlock(position: PositionSlots): HTMLElement {
    const { slot } = position;
    const heading = h('span', { class: `position-heading${slot.key ? ' position-label' : ''}`, title: slotLabel(slot) }, slot.label);
    const labelBox = h('span', { class: 'field-label-box position-heading-box' }, heading);
    const element = h('div', { class: 'position-block', role: 'group', 'aria-label': slotLabel(slot) }, labelBox);
    const target: RenameTarget = { slot, labelBox, element };
    if (slot.key?.positionAddress && this.options.onRenamePosition) {
      const rename = h(
        'button',
        { type: 'button', class: 'rename-position', title: '位置の名前を変える', 'aria-label': `位置の名前 ${slot.label} を変える` },
        '✎',
      );
      rename.addEventListener('click', () => this.openRename(target, position.rows[0]?.slot.id));
      labelBox.append(rename);
    }
    for (const row of position.rows) {
      element.append(this.field(row.slot, { label: layerTitle(row.layer), layer: row.layer.index, target }));
    }
    return element;
  }

  private field(slot: Slot, row?: { label: string; layer: number; target: RenameTarget }): HTMLElement {
    const removable = !!this.options.onRemove;
    const input = new KeyInput({
      context: slot.context,
      host: this.options.host,
      label: row ? `${slotLabel(slot)}（レイヤー ${row.label}）` : slotLabel(slot),
      // 割り当てのない欄は空白のまま（v0.3。図の書いていない位置と同じく何も出さない）
      onCommit: (text) => this.options.onCommit(slot.id, text),
      builder: this.options.layers ? { layers: this.options.layers } : {},
      presetShortcuts: true,
      ...(removable ? { emptyHint: '割り当てを消すには、欄の ✕（割り当てを消す）を押してください' } : {}),
    });
    const label = h(
      'label',
      {
        class: row ? 'field-label layer-row-label' : `field-label${slot.key ? ' position-label' : ''}`,
        for: input.inputId,
        title: row ? `${slot.address.file}: ${slot.address.path.join('.')}` : slot.address.path.join('.'),
      },
      row ? row.label : slot.label,
    );
    const labelBox = h('span', { class: 'field-label-box' }, label);
    const field: Field = { slot, element: h('div'), input, labelBox, label, committedNote: '', noteEditing: false };
    if (row) {
      field.layer = row.layer;
      field.target = row.target;
    }
    if (!row && slot.key?.positionAddress && this.options.onRenamePosition) {
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
    const element = h('div', { class: row ? 'field layer-row' : 'field', 'data-slot': slot.id, ...(row ? { 'data-layer': row.layer } : {}) }, labelBox, main);
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
    if (!field) return;
    if (field.target) {
      this.openRename(field.target, slotId);
      return;
    }
    field.target = { slot: field.slot, labelBox: field.labelBox, element: field.element };
    this.openRename(field.target, slotId);
  }

  /** focusId は名前を決めたあと（Enter・Esc）にフォーカスを返す欄 */
  private openRename(target: RenameTarget, focusId: string | undefined): void {
    const slot = target.slot;
    if (!slot.key?.positionAddress || !this.options.onRenamePosition) return;
    if (target.rename) {
      target.rename.focus();
      return;
    }
    const focusField = () => (focusId ? this.fields.get(focusId)?.input.input.focus() : undefined);
    const input = h('input', {
      type: 'text',
      class: 'position-name-input',
      value: slot.label,
      'aria-label': `${slot.sectionLabel} ${slot.label} の位置の名前`,
      spellcheck: 'false',
      autocomplete: 'off',
    });
    const message = h('div', { class: 'position-name-message', role: 'alert', hidden: true });
    const box = h('span', { class: 'position-name-edit' }, input, message);
    let done = false;
    const finish = (save: boolean) => {
      if (done) return;
      const to = input.value.trim();
      if (save && to !== slot.label) {
        const error = this.options.onRenamePosition?.(slot.id, to) ?? null;
        if (error) {
          message.textContent = error;
          message.hidden = false;
          input.setAttribute('aria-invalid', 'true');
          return;
        }
      }
      done = true;
      target.rename = undefined;
      box.replaceWith(target.labelBox);
    };
    input.addEventListener('keydown', (event) => {
      if (event.key === 'Enter') {
        event.preventDefault();
        finish(true);
        if (done) focusField();
      } else if (event.key === 'Escape') {
        event.preventDefault();
        event.stopPropagation();
        done = false;
        input.value = slot.label;
        finish(false);
        focusField();
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
    target.rename = input;
    target.labelBox.replaceWith(box);
    target.element.scrollIntoView?.({ block: 'nearest' });
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
    field.element.classList.toggle('quiet', view.quiet === true);
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
