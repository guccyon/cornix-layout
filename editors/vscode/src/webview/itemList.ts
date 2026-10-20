// マクロ・タップダンス・コンボ・ショートカットの節の共通の部品（下のペイン。QMK 設定の節と同じく main.ts の sections に置く）。
// 節は左に項目の一覧、右に選んだ項目の編集欄。追加・削除・名前の変更はホストに ItemEdit を渡すだけ（確認のダイアログと書き込みはホスト）。
//
// 描き方: ホストから snapshot と未保存の変更（pending）を受け、項目ごとの姿（itemsModel.ts）を作って描く。編集欄を作り直すのは
// 姿の形（並びの長さ・手順の種類・項目）が変わったときだけで、値が変わっただけなら欄はそのまま値・印・メッセージだけを描き直す
// （打っている欄の文字を残す）。欄で決めた変更はホストに渡すと同時に手元の pending にも足し、ホストの snapshot を待たずに描く。
// 検証の表示はレイヤーの欄と同じ: 変えていない値は snapshot の diagnostics、変えた値は keycode/inspect（onchange の検証）。
import type { Address, AnyChange, CandidateContext, Change, Diagnostic, ItemKind, ProfileSnapshot } from '../protocol';
import { h, nodes } from './dom';
import type { HostClient } from './hostClient';
import { Inspector } from './inspector';
import { diagnosticsIn, effectivePending, nameProblem, within, type KeyEntry, type ValueEntry } from './itemsModel';
import { KeyInput, type KeyInputOptions } from './keyInput';
import { addressKey, severityOf } from './model';

export type ItemSectionOptions = { host: HostClient };

/** 節ごとに決まるもの */
export type ItemSectionMeta = {
  kind: ItemKind;
  /** 節の見出し（「マクロ」） */
  title: string;
  /** 新しい項目の名前の例（入力欄の placeholder） */
  namePlaceholder: string;
  /** 節の要素の class */
  className: string;
};

/** 一覧の 1 行に出すもの */
export type ListEntry = { name: string; index?: number; detail?: string | null; file: string; prefix?: Address };

type NameForm = { mode: 'create' | 'rename'; name: string };

/**
 * 節 1 つ。T は snapshot の項目、V は未保存の変更を当てた姿。
 * 作るほうは items・entry・view・shape・buildDetail を決める
 */
export abstract class ItemSection<T extends { name: string }, V> {
  readonly element: HTMLElement;
  protected readonly host: HostClient;
  protected snapshot: ProfileSnapshot | undefined;
  protected pending: AnyChange[] = [];
  /** 選んでいる項目の今の姿（buildDetail の欄はこれを読む） */
  protected current!: V;
  protected readonly inspector: Inspector;

  private readonly listElement = h('div', { class: 'item-list', role: 'listbox' });
  private readonly detailElement = h('div', { class: 'item-detail' });
  private readonly formElement = h('div', { class: 'item-name-form-slot' });
  private readonly countElement = h('span', { class: 'item-count' });
  private snapshotKey = '';
  private selectedName: string | undefined;
  /** 追加・名前の変更をホストに頼んだ名前（次の snapshot に現れたら選ぶ。ホストの確認でやめたら現れない） */
  private wantedName: string | undefined;
  private shapeKey: string | undefined;
  private updaters: (() => void)[] = [];
  private inputs: KeyInput[] = [];
  /** 編集欄の値の Address（その Address の diagnostics は欄に出す。ほかは項目の問題として上に出す） */
  private fieldAddresses = new Set<string>();
  private readonly problems = h('div', { class: 'item-problems' });
  private form: NameForm | undefined;
  private formMessage = h('div', { class: 'item-form-message', 'aria-live': 'polite' });

  readonly kind: ItemKind;
  readonly title: string;
  private readonly namePlaceholder: string;

  /** snapshot の項目（v0.1 のサーバーが返さなければ undefined で、節を出さない） */
  protected abstract items(snapshot: ProfileSnapshot): T[] | undefined;
  protected abstract entry(item: T, view: V): ListEntry;
  protected abstract view(item: T): V;
  /** 編集欄を作り直すかを決める形（並びの長さ・種類など。値は入れない） */
  protected abstract shape(view: V): unknown;
  /** 選んだ項目の編集欄を作る（欄の値は addUpdater で描く） */
  protected abstract buildDetail(item: T, body: HTMLElement): void;

  constructor(options: ItemSectionOptions, meta: ItemSectionMeta) {
    this.host = options.host;
    this.inspector = new Inspector(options.host);
    this.kind = meta.kind;
    this.title = meta.title;
    this.namePlaceholder = meta.namePlaceholder;
    const add = h('button', { type: 'button', class: 'item-button', 'data-focus': 'add' }, '追加');
    add.addEventListener('click', () => this.openForm({ mode: 'create', name: '' }));
    this.element = h(
      'section',
      { class: `item-section ${meta.className}`, 'aria-label': this.title },
      h(
        'details',
        { class: 'section-details', open: true },
        h('summary', {}, h('h2', {}, this.title), this.countElement),
        h('div', { class: 'item-toolbar' }, add),
        this.formElement,
        h('div', { class: 'item-body' }, this.listElement, this.detailElement),
      ),
    );
    this.listElement.setAttribute('aria-label', `${this.title}の一覧`);
    this.element.hidden = true;
  }

  /** 選んでいる項目の名前（テスト用） */
  get selected(): string | undefined {
    return this.selectedName;
  }

  update(snapshot: ProfileSnapshot, changes: Change[], pending?: AnyChange[]): void {
    const key = JSON.stringify(snapshot);
    if (key !== this.snapshotKey) {
      // 参照先は保存済みのプロファイルで決まるので、snapshot が変わったら解釈を聞き直す
      this.snapshotKey = key;
      this.inspector.clear();
    }
    this.snapshot = snapshot;
    this.pending = [...effectivePending(changes, pending)];
    this.render();
  }

  select(name: string): void {
    this.selectedName = name;
    this.wantedName = undefined;
    this.render();
  }

  protected render(): void {
    const snapshot = this.snapshot;
    const items = snapshot && snapshot.status === 'ok' ? this.items(snapshot) : undefined;
    this.element.hidden = items === undefined;
    if (!snapshot || !items) {
      this.disposeDetail();
      return;
    }
    const focus = this.focusKey();
    const wanted = this.wantedName === undefined ? undefined : items.find((i) => i.name === this.wantedName);
    if (wanted) {
      this.selectedName = wanted.name;
      this.wantedName = undefined;
    }
    let item = items.find((i) => i.name === this.selectedName);
    if (!item) {
      item = items[0];
      this.selectedName = item?.name;
    }
    this.countElement.textContent = `${items.length} 件`;
    this.renderList(items);
    if (!item) {
      this.disposeDetail();
      this.detailElement.replaceChildren(h('p', { class: 'item-empty' }, `${this.title}はまだありません。「追加」で作れます`));
    } else {
      this.current = this.view(item);
      const shape = JSON.stringify([item.name, this.shape(this.current)]);
      if (shape !== this.shapeKey) {
        this.shapeKey = shape;
        this.buildFrame(item);
      }
      for (const update of this.updaters) update();
      this.renderProblems(item);
    }
    if (focus) this.restoreFocus(focus);
  }

  // ---- 一覧 ----

  private renderList(items: T[]): void {
    const snapshot = this.snapshot!;
    const rows = items.map((item) => {
      const entry = this.entry(item, this.view(item));
      const diagnostics = this.itemDiagnostics(entry, snapshot);
      const severity = severityOf(diagnostics);
      const changed = this.pending.some((change) => (entry.prefix ? within(change.address, entry.prefix) : change.address.file === entry.file));
      const selected = item.name === this.selectedName;
      const row = h(
        'button',
        {
          type: 'button',
          role: 'option',
          'aria-selected': String(selected),
          class: ['item-row', selected && 'selected', changed && 'changed', severity].filter(Boolean).join(' '),
          'data-item': item.name,
          'data-focus': `item:${item.name}`,
          title: entry.file,
        },
        ...nodes(
          entry.index !== undefined && h('span', { class: 'item-index' }, String(entry.index)),
          h('span', { class: 'item-name' }, item.name),
          entry.detail ? h('span', { class: 'item-row-detail' }, entry.detail) : null,
          severity && h('span', { class: `item-severity ${severity}`, 'aria-label': severity === 'error' ? 'エラー' : '警告' }, severity === 'error' ? '●' : '▲'),
        ),
      );
      row.addEventListener('click', () => this.select(item.name));
      return row;
    });
    this.listElement.replaceChildren(...(rows.length > 0 ? rows : [h('div', { class: 'item-empty' }, '（なし）')]));
  }

  private itemDiagnostics(entry: ListEntry, snapshot: ProfileSnapshot): Diagnostic[] {
    return diagnosticsIn(snapshot, entry.file, entry.prefix);
  }

  // ---- 編集欄 ----

  private disposeDetail(): void {
    for (const input of this.inputs) input.dispose();
    this.inputs = [];
    this.updaters = [];
    this.fieldAddresses.clear();
    this.shapeKey = undefined;
  }

  private buildFrame(item: T): void {
    this.disposeDetail();
    this.shapeKey = JSON.stringify([item.name, this.shape(this.current)]);
    const entry = this.entry(item, this.current);
    const rename = h('button', { type: 'button', class: 'item-button', 'data-focus': 'rename' }, '名前を変える');
    rename.addEventListener('click', () => this.openForm({ mode: 'rename', name: item.name }));
    const remove = h('button', { type: 'button', class: 'item-button danger', 'data-focus': 'delete' }, '削除');
    remove.addEventListener('click', () => this.host.itemEdit({ op: 'delete', kind: this.kind, name: item.name }));
    const open = h('button', { type: 'button', class: 'link-button', 'data-focus': 'open' }, entry.file);
    open.addEventListener('click', () => this.host.openFile(entry.file));
    const body = h('div', { class: 'item-fields' });
    this.detailElement.replaceChildren(
      h(
        'div',
        { class: 'item-header' },
        h('h3', {}, ...nodes(entry.index !== undefined && h('span', { class: 'item-index' }, String(entry.index)), item.name)),
        open,
        h('span', { class: 'item-actions' }, rename, remove),
      ),
      this.problems,
      body,
    );
    this.buildDetail(item, body);
  }

  private renderProblems(item: T): void {
    const entry = this.entry(item, this.current);
    const list = this.itemDiagnostics(entry, this.snapshot!).filter((d) => !d.address || !this.fieldAddresses.has(addressKey(d.address)));
    this.problems.replaceChildren(...list.map((d) => h('div', { class: `message-line ${d.severity}` }, d.message)));
  }

  /** 値を描き直す関数を足す（作り直さずに描き直すたびに呼ぶ） */
  protected addUpdater(update: () => void): void {
    this.updaters.push(update);
    update();
  }

  /** 値を書き換える（Change） */
  protected set(address: Address, value: string | number | boolean): void {
    const change: Change = { address, value };
    this.host.change(change);
    this.pending.push(change);
    this.render();
  }

  /** 並びの操作・行の削除（AnyChange） */
  protected edit(change: AnyChange, focus?: string): void {
    this.host.edit(change);
    this.pending.push(change);
    this.render();
    if (focus) this.restoreFocus(focus);
  }

  /** キーの欄。entry は描くたびに今の姿から引く */
  protected keyField(options: {
    /** 入力欄の名前（読み上げ） */
    label: string;
    /** 欄の横に出す短い名前（省けば label） */
    visibleLabel?: string;
    focus: string;
    context: CandidateContext;
    entry: () => KeyEntry;
    /** keycode/candidates に足す all・exclude（KeyInput に渡す） */
    candidateParams?: KeyInputOptions['candidateParams'];
    placeholder?: string;
    remove?: { label: string; onClick: () => void };
    className?: string;
  }): HTMLElement {
    const input = new KeyInput({
      context: options.context,
      host: this.host,
      label: options.label,
      ...(options.candidateParams ? { candidateParams: options.candidateParams } : {}),
      placeholder: options.placeholder ?? '（なし）',
      onCommit: (text) => this.set(options.entry().address, text),
    });
    input.input.dataset.focus = options.focus;
    this.inputs.push(input);
    const element = h(
      'div',
      { class: `item-field ${options.className ?? ''}`.trim() },
      h('label', { class: 'field-label', for: input.inputId, title: options.label }, options.visibleLabel ?? options.label),
      input.element,
    );
    if (options.remove) {
      const button = h('button', { type: 'button', class: 'icon-button', title: options.remove.label, 'aria-label': options.remove.label, 'data-focus': `${options.focus}:remove` }, '×');
      button.addEventListener('click', options.remove.onClick);
      element.append(button);
    }
    this.addUpdater(() => {
      const entry = options.entry();
      this.fieldAddresses.add(addressKey(entry.address));
      input.setValue(entry.text);
      input.setDiagnostics(this.keyDiagnostics(options.context, entry));
      element.classList.toggle('changed', entry.changed);
    });
    return element;
  }

  /** キーの欄の検証の結果（変えていなければ snapshot の diagnostics、変えたら keycode/inspect） */
  private keyDiagnostics(context: CandidateContext, entry: KeyEntry): readonly Diagnostic[] {
    if (!entry.changed) return this.diagnosticsAt(entry.address);
    if (!entry.text) return [];
    const result = this.inspector.get(context, entry.text);
    if (result) return result.diagnostics;
    this.inspector.load(context, entry.text).then(
      () => this.refresh(),
      () => undefined,
    );
    return [];
  }

  private refresh(): void {
    for (const update of this.updaters) update();
  }

  protected diagnosticsAt(address: Address): Diagnostic[] {
    const key = addressKey(address);
    return (this.snapshot?.diagnostics ?? []).filter((d) => d.address && addressKey(d.address) === key);
  }

  /**
   * 数値・文字の欄。parse が文字を値にする（合わなければ { problem }）。空にしたとき removable なら行を消す（remove）
   */
  protected valueField<TValue extends string | number>(options: {
    label: string;
    focus: string;
    type: 'number' | 'text';
    entry: () => ValueEntry<TValue>;
    parse: (text: string) => { value: TValue } | { problem: string };
    removable?: boolean;
    placeholder?: () => string;
    hint?: () => string | null;
    className?: string;
  }): HTMLElement {
    const id = `item-value-${nextFieldId++}`;
    const input = h('input', {
      type: options.type,
      id,
      class: `item-value-input ${options.type === 'number' ? 'number' : 'text'}`,
      'data-focus': options.focus,
      spellcheck: 'false',
      autocomplete: 'off',
      ...(options.type === 'number' ? { step: 1, inputmode: 'numeric' } : {}),
    });
    const hint = h('span', { class: 'item-value-hint' });
    const message = h('div', { class: 'item-value-message', 'aria-live': 'polite' });
    const element = h(
      'div',
      { class: `item-field ${options.className ?? ''}`.trim() },
      h('label', { class: 'field-label', for: id }, options.label),
      h('div', { class: 'item-value-control' }, input, hint, message),
    );
    let typing = false;
    let local: string | undefined;
    const render = (): void => {
      const entry = options.entry();
      this.fieldAddresses.add(addressKey(entry.address));
      if (!typing && !local) input.value = entry.value === null ? '' : String(entry.value);
      input.placeholder = options.placeholder?.() ?? '';
      hint.textContent = options.hint?.() ?? '';
      element.classList.toggle('changed', entry.changed);
      const diagnostics = entry.changed ? [] : this.diagnosticsAt(entry.address);
      const severity = local ? 'error' : severityOf(diagnostics);
      element.classList.toggle('error', severity === 'error');
      element.classList.toggle('warning', severity === 'warning');
      input.setAttribute('aria-invalid', String(severity === 'error'));
      message.replaceChildren(
        ...[...(local ? [h('div', { class: 'message-line error' }, local)] : []), ...diagnostics.map((d) => h('div', { class: `message-line ${d.severity}` }, d.message))],
      );
    };
    input.addEventListener('input', () => {
      typing = true;
    });
    input.addEventListener('keydown', (event) => {
      if (event.key !== 'Escape') return;
      typing = false;
      local = undefined;
      render();
    });
    input.addEventListener('change', () => {
      typing = false;
      const entry = options.entry();
      const text = input.value;
      if (options.type === 'number' && input.validity?.badInput) {
        local = '整数を入れてください';
        render();
        return;
      }
      const empty = options.type === 'number' ? text.trim() === '' : text === '';
      if (empty) {
        local = undefined;
        if (entry.value === null) return render();
        if (options.removable) {
          this.edit({ op: 'remove', address: entry.address });
          return;
        }
        local = '空にはできません';
        render();
        return;
      }
      const parsed = options.parse(text);
      if ('problem' in parsed) {
        local = parsed.problem;
        render();
        return;
      }
      local = undefined;
      if (parsed.value === entry.value) return render();
      this.set(entry.address, parsed.value);
    });
    this.addUpdater(render);
    return element;
  }

  // ---- 追加・名前の変更 ----

  private openForm(form: NameForm): void {
    this.form = form;
    const names = (this.snapshot && this.items(this.snapshot)?.map((i) => i.name)) ?? [];
    const nameInput = h('input', {
      type: 'text',
      class: 'item-name-input',
      'aria-label': form.mode === 'create' ? `新しい${this.title}の名前` : '新しい名前',
      placeholder: this.namePlaceholder,
      spellcheck: 'false',
      autocomplete: 'off',
      'data-focus': 'form-name',
    });
    nameInput.value = form.name;
    // ショートカットは作るときに値も要る
    const valueInput =
      form.mode === 'create' && this.kind === 'shortcut'
        ? new KeyInput({ context: 'shortcutValue', host: this.host, label: '新しいショートカットの値', placeholder: '値（Command + Shift + [ など）', onCommit: () => undefined })
        : undefined;
    const submit = h('button', { type: 'button', class: 'item-button primary' }, form.mode === 'create' ? '追加する' : '名前を変える');
    const cancel = h('button', { type: 'button', class: 'item-button' }, 'やめる');
    this.formMessage.replaceChildren();
    const close = (): void => {
      valueInput?.dispose();
      this.form = undefined;
      this.formElement.replaceChildren();
      this.restoreFocus(form.mode === 'create' ? 'add' : 'rename');
    };
    const send = (): void => {
      const name = nameInput.value;
      const problem = nameProblem(name, names, form.mode === 'rename' ? form.name : undefined);
      if (problem) {
        this.formMessage.replaceChildren(h('div', { class: 'message-line error' }, problem));
        return;
      }
      if (form.mode === 'rename') {
        if (name !== form.name) {
          this.host.itemEdit({ op: 'rename', kind: this.kind, name: form.name, to: name });
          this.wantedName = name;
        }
      } else if (this.kind === 'shortcut') {
        const value = valueInput!.input.value.trim();
        if (!value) {
          this.formMessage.replaceChildren(h('div', { class: 'message-line error' }, '値を入れてください'));
          return;
        }
        this.host.itemEdit({ op: 'create', kind: 'shortcut', name, value });
        this.wantedName = name;
      } else {
        this.host.itemEdit({ op: 'create', kind: this.kind, name });
        this.wantedName = name;
      }
      close();
    };
    submit.addEventListener('click', send);
    cancel.addEventListener('click', close);
    nameInput.addEventListener('keydown', (event) => {
      if (event.key === 'Enter') {
        event.preventDefault();
        send();
      } else if (event.key === 'Escape') {
        event.preventDefault();
        close();
      }
    });
    this.formElement.replaceChildren(
      h(
        'div',
        { class: 'item-name-form', role: 'group', 'aria-label': form.mode === 'create' ? `${this.title}を追加` : `「${form.name}」の名前を変える` },
        h('span', { class: 'item-form-title' }, form.mode === 'create' ? `新しい${this.title}` : `「${form.name}」の新しい名前`),
        nameInput,
        valueInput?.element,
        submit,
        cancel,
        this.formMessage,
      ),
    );
    nameInput.focus();
    nameInput.select();
  }

  /** 名前の欄が開いている（テスト用） */
  get formOpen(): boolean {
    return this.form !== undefined;
  }

  // ---- フォーカス ----

  private focusKey(): string | undefined {
    const active = document.activeElement;
    if (!(active instanceof HTMLElement) || !this.element.contains(active)) return undefined;
    return active.dataset.focus;
  }

  protected restoreFocus(key: string): void {
    const target = [...this.element.querySelectorAll<HTMLElement>('[data-focus]')].find((e) => e.dataset.focus === key);
    if (target && document.activeElement !== target) target.focus();
  }
}

let nextFieldId = 1;

/** 0 以上の整数（ミリ秒） */
export function parseMilliseconds(text: string): { value: number } | { problem: string } {
  const trimmed = text.trim();
  if (!/^\d+$/.test(trimmed)) return { problem: '0 以上の整数（ミリ秒）を入れてください' };
  return { value: Number(trimmed) };
}
