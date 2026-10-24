// キー入力欄（どこも同じ部品。spec.md の「入力と補完」）。
// - 打つたびに keycode/candidates を間引いて聞き（protocol.md の 1. の「順序」）、新しい要求を送ったら古い結果は捨てる
// - 候補はサーバーの並びのまま出す。typed（打った文字をそのまま表記として読めたときの解釈）は先頭に「入力どおり」として出す
// - 候補を選ぶと insertText を入れる。手で打った表記は解釈できればそのまま残す（勝手に正規形に直さない）
// - 決めた（Enter・候補を選んだ・欄を離れた）ときに onCommit を呼ぶ。検証（keycode/inspect）と表示は呼んだ側がする
// - builder を渡すと、欄の右端に「組み立て」のボタンを置き、修飾キー式・LT・Mod-Tap の組み立て欄（modifierBuilder.ts）を開ける
// - v0.3: presetShortcuts を渡すと（Shortcut(...) を書ける context だけ）、候補の一覧の下に「同梱から選ぶ…」を置き、
//   同梱のショートカットの階層の選択（presetPicker.ts）を開いて Shortcut('アプリ:カテゴリ:ラベル') を入れる（tasks-v0.3.md の決めたことの 2）
import type { Candidate, CandidateContext, CandidatesParams, CandidatesResult, Diagnostic, KeyValue } from '../protocol';
import { h } from './dom';
import type { HostClient } from './hostClient';
import { iconElement } from './icons';
import { severityOf } from './model';
import { ModifierBuilder } from './modifierBuilder';
import { loadShortcutTree, PresetPicker } from './presetPicker';
import { hideTooltip } from './tooltip';

export const CANDIDATE_DEBOUNCE_MS = 50;
export const CANDIDATE_LIMIT = 50;

const CATEGORY_LABEL: Record<Candidate['category'], string> = {
  basic: '基本',
  modifier: '修飾',
  media: 'メディア',
  mouse: 'マウス',
  layer: 'レイヤー',
  macro: 'マクロ',
  tapDance: 'タップダンス',
  shortcut: '自分のショートカット',
  presetShortcut: '同梱のショートカット',
  special: '特殊',
  raw: '直接の値',
};

/**
 * Shortcut(...) を書ける context（「同梱から選ぶ…」を出すところ）。マクロの手順のキー・コンボの同時に押すキー・shortcuts.yaml の値は
 * 候補からショートカットを除く（data/keycode_categories.yaml の contexts と protocol.md の 12.4）ので出さない
 */
export const PRESET_SHORTCUT_CONTEXTS: ReadonlySet<CandidateContext> = new Set<CandidateContext>(['layerKey', 'encoder', 'tapDanceAction', 'comboOutput']);

/** 「同梱から選ぶ…」の行の文字 */
export const PRESET_ROW_LABEL = '同梱から選ぶ…';

/** keycode/candidates に足す params（v0.2 の all・exclude。protocol.md の 12.4） */
export type CandidateExtras = Pick<CandidatesParams, 'all' | 'exclude'>;

export type KeyInputOptions = {
  context: CandidateContext;
  host: HostClient;
  /** 決めた表記（前と同じなら呼ばない） */
  onCommit: (text: string) => void;
  /** 入力欄の名前（読み上げ用） */
  label: string;
  placeholder?: string;
  debounceMs?: number;
  /**
   * keycode/candidates に足す params（v0.2。中身の画面の context ごとの all・exclude）。
   * 関数なら要求のたびに読む（マクロの「すべて出す」の切り替えをすぐに効かせる）。false と undefined の項目は送らない
   */
  candidateParams?: CandidateExtras | (() => CandidateExtras);
  /** 空でも決める（組み立て欄のキーなど、割り当てでない欄） */
  allowEmpty?: boolean;
  /** 空にして決めたときの案内（省くと「割り当てを消すには NoKey を選んでください」） */
  emptyHint?: string;
  /** 修飾キー式・LT・Mod-Tap の組み立て欄を付ける。layers は LT のレイヤーの選び先（なければ 0〜15） */
  builder?: { layers?: () => readonly { index: number; name: string }[] };
  /** v0.3: 候補の一覧の下に「同梱から選ぶ…」を置く（PRESET_SHORTCUT_CONTEXTS の context のときだけ効く） */
  presetShortcuts?: boolean;
};

/** 候補の一覧の 1 行（presets は「同梱から選ぶ…」） */
type Row = { insertText: string; candidate?: Candidate; typed?: KeyValue; presets?: true };

let nextId = 1;

export class KeyInput {
  readonly element: HTMLElement;
  readonly input: HTMLInputElement;
  private readonly list: HTMLElement;
  private readonly message: HTMLElement;
  private readonly listId = `key-input-list-${nextId}`;
  /** 入力欄の id（欄の名前の <label for> から結ぶ） */
  readonly inputId = `key-input-${nextId++}`;
  private disposed = false;

  /** 決まっている表記（外から setValue で入れたか、最後に onCommit したもの） */
  private committed = '';
  /** 打っている途中（committed と違う文字が入っていて、まだ決めていない） */
  private editing = false;
  private rows: Row[] = [];
  private active = -1;
  private timer: ReturnType<typeof setTimeout> | undefined;
  /** 候補の要求の番号。新しい要求を送るか閉じたら進め、古い結果を捨てる */
  private sequence = 0;
  /** 候補の要求の返事を待っている */
  private awaiting = false;
  private hint: string | undefined;
  private diagnostics: readonly Diagnostic[] = [];
  /** 組み立て欄（options.builder を渡したときだけ） */
  readonly builder: ModifierBuilder | undefined;
  private readonly builderButton: HTMLButtonElement | undefined;
  /** 同梱のショートカットの選択（「同梱から選ぶ…」を初めて選んだときに作る） */
  private picker: PresetPicker | undefined;

  constructor(private readonly options: KeyInputOptions) {
    this.input = h('input', {
      type: 'text',
      id: this.inputId,
      class: 'key-input-field',
      role: 'combobox',
      'aria-autocomplete': 'list',
      'aria-expanded': 'false',
      'aria-controls': this.listId,
      'aria-label': options.label,
      placeholder: options.placeholder ?? '',
      spellcheck: 'false',
      autocomplete: 'off',
    });
    this.list = h('div', { class: 'candidates', role: 'listbox', id: this.listId, hidden: true });
    this.message = h('div', { class: 'key-input-message', hidden: true });
    this.element = h('div', { class: 'key-input' }, this.input, this.list, this.message);
    if (options.builder) {
      const builder = new ModifierBuilder({
        host: options.host,
        context: options.context,
        ...(options.builder.layers ? { layers: options.builder.layers } : {}),
        onApply: (text) => {
          this.editing = false;
          this.input.value = text;
          this.commit(text);
        },
        onClose: (focusBack) => {
          this.builderButton?.setAttribute('aria-expanded', 'false');
          document.removeEventListener('mousedown', this.outside, true);
          if (focusBack) this.input.focus();
        },
      });
      const button = h(
        'button',
        { type: 'button', class: 'key-input-build', title: '修飾キー・LT・Mod-Tap を組み立てる', 'aria-label': `${options.label}を組み立てる`, 'aria-expanded': 'false' },
        '⌘+',
      );
      button.addEventListener('click', () => (builder.isOpen ? builder.close() : this.openBuilder()));
      this.builder = builder;
      this.builderButton = button;
      this.element.classList.add('has-builder');
      this.element.append(button, builder.element);
      // Tab で欄の外へ出たら閉じる（フォーカスは移った先のまま）
      builder.element.addEventListener('focusout', (event) => {
        const next = event.relatedTarget;
        if (next instanceof Node && !this.element.contains(next)) builder.close(false);
      });
    }

    this.input.addEventListener('input', () => {
      this.editing = true;
      this.hint = undefined;
      this.renderMessage();
      this.schedule();
    });
    this.input.addEventListener('keydown', (event) => this.onKeyDown(event));
    this.input.addEventListener('blur', () => {
      // 作り直しで外された欄（dispose 済み）は決めない（古い欄の値で Change を作らないため）
      if (this.disposed) return;
      this.close();
      this.commit(this.input.value);
    });
    // 候補を押したときに欄から離れない（blur で決まってしまわない）ように
    this.list.addEventListener('mousedown', (event) => event.preventDefault());
  }

  get value(): string {
    return this.committed;
  }

  get isOpen(): boolean {
    return !this.list.hidden;
  }

  get isEditing(): boolean {
    return this.editing;
  }

  /** 「同梱から選ぶ…」を出す欄か */
  get offersPresets(): boolean {
    return !!this.options.presetShortcuts && PRESET_SHORTCUT_CONTEXTS.has(this.options.context);
  }

  /** 同梱のショートカットの選択を開いている */
  get isPickingPreset(): boolean {
    return this.picker?.isOpen ?? false;
  }

  /** 外から値を入れる（snapshot・元に戻す）。打っている途中なら入れない */
  setValue(text: string): void {
    if (this.editing) {
      this.committed = text;
      return;
    }
    this.committed = text;
    if (this.input.value !== text) this.input.value = text;
  }

  /** 打ちかけの文字を戻す（画面を作り直したとき、前の欄で打っていた文字を新しい欄に移す） */
  restoreDraft(text: string): void {
    this.input.value = text;
    this.editing = text !== this.committed;
  }

  /** 画面から外す前に呼ぶ。以降は blur でも決めない */
  dispose(): void {
    this.disposed = true;
    this.close();
    this.picker?.close(false);
    this.builder?.close(false);
    this.builder?.dispose();
  }

  /** 組み立て欄を今の値から開く */
  openBuilder(): void {
    if (!this.builder) return;
    this.close();
    hideTooltip(this.input);
    this.builderButton?.setAttribute('aria-expanded', 'true');
    this.builder.open(this.input.value);
    document.addEventListener('mousedown', this.outside, true);
  }

  /** 組み立て欄を開いている間、欄の外を押したら閉じる */
  private readonly outside = (event: MouseEvent): void => {
    if (event.target instanceof Node && this.element.contains(event.target)) return;
    this.builder?.close(false);
  };

  /**
   * 同梱のショートカットの選択を開く（候補の「同梱から選ぶ…」）。打ちかけの文字は捨てて決まっている値に戻す
   * （選択へフォーカスが移るときの blur で、打ちかけを決めてしまわないように）。選んだら Shortcut('…') を入れて決める
   */
  openPresets(): void {
    if (!this.offersPresets) return;
    this.close();
    this.builder?.close(false);
    hideTooltip(this.input);
    this.editing = false;
    this.input.value = this.committed;
    this.hint = undefined;
    this.renderMessage();
    if (!this.picker) {
      const picker = new PresetPicker({
        kind: 'shortcut',
        buttonLabel: null,
        className: 'key-input-presets',
        loadTree: () => loadShortcutTree(this.options.host),
        current: () => this.committed || null,
        onPick: (name) => {
          this.editing = false;
          this.input.value = name;
          this.commit(name);
        },
        onClose: (focusBack) => {
          document.removeEventListener('mousedown', this.outsidePresets, true);
          if (focusBack && !this.disposed) this.input.focus();
        },
      });
      // Tab で欄の外へ出たら閉じる（フォーカスは移った先のまま）
      picker.element.addEventListener('focusout', (event) => {
        const next = event.relatedTarget;
        if (next instanceof Node && !picker.element.contains(next)) picker.close(false);
      });
      this.picker = picker;
      this.element.append(picker.element);
    }
    document.addEventListener('mousedown', this.outsidePresets, true);
    void this.picker.open();
  }

  /** 同梱のショートカットの選択を開いている間、欄の外を押したら閉じる */
  private readonly outsidePresets = (event: MouseEvent): void => {
    if (event.target instanceof Node && this.element.contains(event.target)) return;
    this.picker?.close(false);
  };

  /** この欄の検証の結果。error / warning の印とメッセージを出す */
  setDiagnostics(diagnostics: readonly Diagnostic[]): void {
    this.diagnostics = diagnostics;
    this.renderMessage();
  }

  focus(): void {
    this.input.focus();
    this.input.select();
  }

  /** 候補を開く（今の文字で聞く） */
  open(): void {
    this.schedule(0);
  }

  close(): void {
    this.sequence++;
    this.awaiting = false;
    if (this.timer) clearTimeout(this.timer);
    this.timer = undefined;
    this.rows = [];
    this.active = -1;
    this.list.hidden = true;
    this.list.replaceChildren();
    this.input.setAttribute('aria-expanded', 'false');
    this.input.removeAttribute('aria-activedescendant');
  }

  private schedule(delay = this.options.debounceMs ?? CANDIDATE_DEBOUNCE_MS): void {
    if (this.timer) clearTimeout(this.timer);
    this.timer = setTimeout(() => {
      this.timer = undefined;
      void this.fetch();
    }, delay);
  }

  /** 今の candidateParams（false と undefined の項目は除く） */
  private candidateExtras(): CandidateExtras {
    const params = this.options.candidateParams;
    const extras = typeof params === 'function' ? params() : params ?? {};
    return Object.fromEntries(Object.entries(extras).filter(([, value]) => value !== undefined && value !== false)) as CandidateExtras;
  }

  private async fetch(): Promise<void> {
    const sequence = ++this.sequence;
    const query = this.input.value;
    let result: CandidatesResult;
    this.awaiting = true;
    try {
      result = await this.options.host.request('keycode/candidates', {
        context: this.options.context,
        query,
        limit: CANDIDATE_LIMIT,
        ...this.candidateExtras(),
      });
    } catch {
      return;
    } finally {
      if (sequence === this.sequence) this.awaiting = false;
    }
    // 返ってくるまでに打ち進めた・閉じた・欄を離れたなら捨てる
    if (sequence !== this.sequence || document.activeElement !== this.input) return;
    this.show(query, result);
  }

  private show(query: string, result: CandidatesResult): void {
    const rows: Row[] = [];
    const trimmed = query.trim();
    // 打った表記と同じ insertText の候補があれば typed の行は出さず、その候補を選んでおく（Enter で打ったとおりのものが入る）
    const exact = trimmed ? result.items.findIndex((item) => item.insertText === trimmed) : -1;
    if (result.typed && trimmed && exact < 0) rows.push({ insertText: trimmed, typed: result.typed });
    for (const item of result.items) rows.push({ insertText: item.insertText, candidate: item });
    const presets = this.offersPresets;
    if (rows.length === 0 && !trimmed && !presets) {
      // 空の入力で候補もなければ、空の枠を開かない
      this.close();
      return;
    }
    const found = rows.length;
    this.active = !trimmed || found === 0 ? -1 : exact >= 0 ? exact : 0;
    // 「同梱から選ぶ…」はいちばん下（矢印で選べるが、最初に選んでおくことはない）
    if (presets) rows.push({ insertText: '', presets: true });
    this.rows = rows;
    hideTooltip(this.input);
    this.list.replaceChildren(...rows.slice(0, found).map((row, index) => this.renderRow(row, index)));
    if (result.truncated) this.list.append(h('div', { class: 'candidates-more' }, 'ほかにも候補があります。続けて打つと絞れます'));
    if (found === 0) this.list.append(h('div', { class: 'candidates-empty' }, '候補がありません'));
    if (presets) this.list.append(this.renderRow(rows[found]!, found));
    this.list.hidden = false;
    // 画面の右端からはみ出すなら、欄の右端にそろえる
    this.list.classList.remove('align-right');
    if (this.list.getBoundingClientRect().right > document.documentElement.clientWidth) this.list.classList.add('align-right');
    this.input.setAttribute('aria-expanded', 'true');
    this.highlight();
  }

  private renderRow(row: Row, index: number): HTMLElement {
    const id = `${this.listId}-${index}`;
    let element: HTMLElement;
    if (row.presets) {
      element = h(
        'div',
        { class: 'candidate presets-row', role: 'option', id, title: '同梱のショートカットをアプリ → カテゴリ → ラベルで選ぶ' },
        h('span', { class: 'candidate-icon' }),
        h('span', { class: 'candidate-label' }, PRESET_ROW_LABEL),
        h('span', { class: 'candidate-detail' }, '同梱のショートカットを一覧から'),
      );
    } else if (row.typed) {
      const typed = row.typed;
      element = h(
        'div',
        { class: 'candidate typed', role: 'option', id },
        h('span', { class: 'candidate-icon' }, iconElement(typed.icon)),
        h('span', { class: 'candidate-label' }, row.insertText),
        h('span', { class: 'candidate-detail' }, `入力どおり → ${typed.canonical}${typed.display.label ? `（${typed.display.label}）` : ''}`),
      );
    } else {
      const candidate = row.candidate!;
      element = h(
        'div',
        { class: `candidate${candidate.warning ? ' has-warning' : ''}`, role: 'option', id, title: candidate.warning ?? candidate.insertText },
        h('span', { class: 'candidate-icon' }, iconElement(candidate.icon)),
        h('span', { class: 'candidate-label' }, candidate.label),
        h('span', { class: 'candidate-detail' }, candidate.detail ?? ''),
        candidate.warning ? h('span', { class: 'candidate-warning', 'aria-label': candidate.warning }, '⚠') : null,
        h('span', { class: 'candidate-category' }, CATEGORY_LABEL[candidate.category] ?? candidate.category),
      );
    }
    element.dataset.insertText = row.insertText;
    element.addEventListener('mousemove', () => {
      if (this.active === index) return;
      this.active = index;
      this.highlight();
    });
    element.addEventListener('click', () => this.choose(index));
    return element;
  }

  private highlight(): void {
    const options = [...this.list.querySelectorAll<HTMLElement>('[role="option"]')];
    options.forEach((option, index) => {
      const selected = index === this.active;
      option.classList.toggle('active', selected);
      option.setAttribute('aria-selected', String(selected));
      if (selected) {
        this.input.setAttribute('aria-activedescendant', option.id);
        // 一覧の中だけを動かす（scrollIntoView だと画面ごと動く）
        if (option.offsetTop < this.list.scrollTop) this.list.scrollTop = option.offsetTop;
        else if (option.offsetTop + option.offsetHeight > this.list.scrollTop + this.list.clientHeight) {
          this.list.scrollTop = option.offsetTop + option.offsetHeight - this.list.clientHeight;
        }
      }
    });
    if (this.active < 0) this.input.removeAttribute('aria-activedescendant');
  }

  private choose(index: number): void {
    const row = this.rows[index];
    if (!row) return;
    if (row.presets) {
      this.openPresets();
      return;
    }
    this.input.value = row.insertText;
    this.close();
    this.commit(row.insertText);
  }

  private onKeyDown(event: KeyboardEvent): void {
    switch (event.key) {
      case 'ArrowDown':
      case 'ArrowUp': {
        event.preventDefault();
        if (!this.isOpen) {
          this.open();
          return;
        }
        if (this.rows.length === 0) return;
        const step = event.key === 'ArrowDown' ? 1 : -1;
        this.active = (this.active + step + this.rows.length) % this.rows.length;
        this.highlight();
        return;
      }
      case 'Enter':
        event.preventDefault();
        if (this.isOpen && this.active >= 0) this.choose(this.active);
        else {
          this.close();
          this.commit(this.input.value);
        }
        return;
      case 'Escape':
        // 候補を開いている（開こうとしている）なら閉じるだけ。打っている途中なら決まっている値に戻す
        if (this.isOpen || this.timer || this.awaiting) {
          event.preventDefault();
          event.stopPropagation();
          this.close();
          return;
        }
        if (this.editing) {
          event.preventDefault();
          this.editing = false;
          this.input.value = this.committed;
          this.hint = undefined;
          this.renderMessage();
        }
        return;
      case 'Tab':
        this.close();
        return;
    }
  }

  private commit(raw: string): void {
    const text = raw.trim();
    this.editing = false;
    if (text === '' && !this.options.allowEmpty) {
      // 空にしても消さない（消すのは欄の「割り当てを消す」。v0.1 の欄では NoKey を選ぶ）
      this.input.value = this.committed;
      this.hint = this.committed ? (this.options.emptyHint ?? '割り当てを消すには NoKey を選んでください') : undefined;
      this.renderMessage();
      return;
    }
    if (text !== raw) this.input.value = text;
    if (text === this.committed) return;
    this.committed = text;
    this.hint = undefined;
    this.options.onCommit(text);
  }

  private renderMessage(): void {
    const severity = severityOf(this.diagnostics);
    this.element.classList.toggle('error', severity === 'error');
    this.element.classList.toggle('warning', severity === 'warning');
    this.input.setAttribute('aria-invalid', String(severity === 'error'));
    const lines = this.diagnostics.map((d) => h('div', { class: `message-line ${d.severity}` }, d.message));
    if (this.hint) lines.push(h('div', { class: 'message-line hint' }, this.hint));
    this.message.replaceChildren(...lines);
    this.message.hidden = lines.length === 0;
  }
}
