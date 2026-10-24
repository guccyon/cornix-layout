// マクロ・タップダンス・コンボ・ショートカットの節の共通の部品（下のペイン。QMK 設定の節と同じく main.ts の sections に置く）。
// 節は左に項目の一覧、右に選んだ項目の編集欄。追加・削除・名前の変更はホストに ItemEdit を渡すだけ（確認のダイアログと書き込みはホスト）。
//
// 描き方: ホストから snapshot と未保存の変更（pending）を受け、項目ごとの姿（itemsModel.ts）を作って描く。編集欄を作り直すのは
// 姿の形（並びの長さ・手順の種類・項目）が変わったときだけで、値が変わっただけなら欄はそのまま値・印・メッセージだけを描き直す
// （打っている欄の文字を残す）。欄で決めた変更はホストに渡すと同時に手元の pending にも足し、ホストの snapshot を待たずに描く。
// 検証の表示はレイヤーの欄と同じ: 変えていない値は snapshot の diagnostics、変えた値は keycode/inspect（onchange の検証）。
// v0.3: 節は最初は畳んでおく（開閉は details のまま。snapshot の描き直しでは details を作り直さないので、開いた状態は残る）。
// キーの欄は割り当てがなければ空白（placeholder なし）で、Shortcut(...) を書ける欄の候補の下には「同梱から選ぶ…」。
// v0.5（issue #114。tasks-v0.5.md の決めたこと）:
// - 節の「追加」は追加の一覧（addMenu.ts）: 検索・「＋ 新しい〇〇」（今の名前の欄）・「未使用（N）」（選ぶと itemEdit の use）・同梱から（マクロとショートカット）
// - 一覧に並べるのは使っている項目だけで、番号は未保存の変更を当てたもの（itemIndex.ts の arrangeItems の used）。未使用の項目は追加の一覧からだけ使い始める
// - 項目の操作は一覧の各行の「…」（moreMenu.ts。行を指したとき・選んでいるときに出す）と行の右クリック（同じメニュー）: 名前を変える / 未使用にする（unuse）/
//   ファイルを開く / 削除…（ショートカットには未使用がないので 未使用にする は出さない）。W2（ADR 025）で編集欄の見出しの「…」から移した
// - 「追加」の隣の「並び替え」ボタン（使っている項目が 2 つ以上のときに押せる。ショートカットには番号がないので出さない）。
//   並び替えモードでは各行に ⬆⬇ を出し、押すたびに画面の並びだけを 1 つ動かす。「確定」で itemEdit の reorder を 1 回送り（並びが今と同じなら送らない。
//   ホストが未保存の変更に積む）、「やめる」で捨てる。モードの間は行の選択・「…」・「追加」はできない。番号は行の位置に付けたまま（確定するとその番号になる）
//   （番号の選択 indexPicker.ts と「番号を変える…」はやめた）
// - 項目は番号のある種類ではファイル、ショートカットでは名前で見分ける（未使用の項目と名前が重なることがあるため）
import type { Address, AnyChange, CandidateContext, Change, Diagnostic, IndexedKind, ItemEdit, ItemKind, ProfileSnapshot } from '../protocol';
import { arrangeItems, INDEX_LIMITS, nextIndex, snapshotItems } from '../itemIndex';
import { AddMenu, type AddMenuData, type AddMenuUnusedItem } from './addMenu';
import { h, nodes } from './dom';
import type { HostClient } from './hostClient';
import { Inspector } from './inspector';
import { diagnosticsIn, effectivePending, nameProblem, within, type KeyEntry, type ValueEntry } from './itemsModel';
import { KeyInput, type KeyInputOptions } from './keyInput';
import { addressKey, severityOf } from './model';
import { MoreMenu, type MoreMenuItem } from './moreMenu';
import { loadShortcutTree, presetEntries, type PresetEntry, type PresetKind } from './presetPicker';
import { attachTooltip, describeContent, hideTooltip } from './tooltip';

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
  /** 追加の一覧の「同梱から」（マクロとショートカットだけ） */
  bundled?: PresetKind;
};

/** 番号が埋まっているときの、未使用の行の理由（spec.md の「未使用の項目と番号（v0.5）」） */
export const UNUSED_BLOCKED_REASON = '番号が埋まっています。どれかを未使用にすると選べます';

/** 並び替えモード（ADR 025）の文。レイヤーのタブ（app.ts）も同じものを使う */
export const REORDER_CONFIRM = '確定';
export const REORDER_CANCEL = 'やめる';
export const REORDER_HINT = '⬆⬇ で並べ替えて「確定」（番号は小さい順に当て直します）';
export const REORDER_TOO_FEW = '使っているものが 2 つ以上のときに並び替えられます';

/** 一覧の 1 行に出すもの。mark は名前の横の印（押せないコンボの ⚠ など。title はその説明） */
export type ListEntry = { name: string; index?: number; detail?: string | null; file: string; prefix?: Address; mark?: { text: string; title: string } | null };

/** 追加・名前の変更の欄。value はショートカットの値の初めの文字、message は開いたときに出すエラー、preset は同梱から作るマクロの preset */
type NameForm = { mode: 'create' | 'rename'; name: string; value?: string; message?: string; preset?: string; key?: string };

/** 追加の欄に入れておくもの */
export type CreateFormInit = { value?: string; message?: string; preset?: string };

/** 一覧の項目の頼みごと（次に一覧に現れたら選ぶ）。key は項目の見分け（番号のある種類はファイル）、name は名前 */
type Wanted = { key: string } | { name: string };

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
  /** 選んでいる項目（未保存の変更を当てた番号。描くたびに置き換える） */
  private currentItem: T | undefined;
  protected readonly inspector: Inspector;

  private readonly listElement = h('div', { class: 'item-list', role: 'listbox' });
  private readonly detailElement = h('div', { class: 'item-detail' });
  private readonly formElement = h('div', { class: 'item-name-form-slot' });
  private readonly countElement = h('span', { class: 'item-count' });
  /** 「追加」のボタンの並び（作るほうがボタンを足す） */
  protected readonly toolbar: HTMLElement;
  /** 節の「追加」（追加の一覧） */
  readonly addMenu: AddMenu;
  /** 「並び替え」のボタン（番号のある種類だけ） */
  readonly reorderButton: HTMLButtonElement | undefined;
  /** 一覧の各行の「…」（行の見分け → メニュー。一覧を描くたびに作り直す） */
  private rowMenus = new Map<string, MoreMenu>();
  /** 並び替えモードの並び（ファイル）。モードでなければ undefined */
  private reorderFiles: string[] | undefined;
  /** 並び替えモードの「確定」「やめる」 */
  private readonly reorderBar: HTMLElement;
  /** 見出しの番号（未保存の変更で変わるので描くたびに書き直す） */
  private headerIndex: HTMLElement | undefined;
  /** 節の開閉（最初は畳む） */
  readonly details: HTMLDetailsElement;
  private snapshotKey = '';
  /** 選んでいる項目の見分け（itemKey） */
  private selectedKey: string | undefined;
  /**
   * 追加・名前の変更・取り出しをホストに頼んだ項目（次の snapshot か未保存の変更の知らせで一覧に現れたら選ぶ。ホストの確認でやめたら現れない）
   */
  private wanted: Wanted | undefined;
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
  /** 番号のある種類（ショートカットは undefined） */
  protected readonly indexedKind: IndexedKind | undefined;

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
    this.indexedKind = meta.kind === 'shortcut' ? undefined : meta.kind;
    const bundled = meta.bundled;
    this.addMenu = new AddMenu({
      buttonLabel: '追加',
      noun: meta.title,
      create: { label: `＋ 新しい${meta.title}` },
      className: 'item-add-menu',
      ...(bundled
        ? { bundled: { kind: bundled, loadEntries: async () => presetEntries(await loadShortcutTree(this.host), '', bundled) }, onPickBundled: (entry: PresetEntry) => this.pickBundled(entry) }
        : {}),
      onCreate: (query) => this.openForm({ mode: 'create', name: query }),
      onPickUnused: (item) => this.useItem(item),
    });
    // 節の全体の操作は並び替えだけなので、「…」ではなくボタンを直に置く（Tetsuro の確かめ）
    if (this.indexedKind) {
      const button = h('button', { type: 'button', class: 'item-button item-reorder-button', 'data-focus': 'section-reorder' }, '並び替え');
      button.addEventListener('click', () => this.startReorder());
      this.reorderButton = button;
    }
    const confirm = h('button', { type: 'button', class: 'item-button primary', 'data-focus': 'reorder-confirm' }, REORDER_CONFIRM);
    confirm.addEventListener('click', () => this.confirmReorder());
    const cancel = h('button', { type: 'button', class: 'item-button', 'data-focus': 'reorder-cancel' }, REORDER_CANCEL);
    cancel.addEventListener('click', () => this.endReorder());
    this.reorderBar = h(
      'div',
      { class: 'reorder-bar', role: 'group', 'aria-label': `${meta.title}の並び替え`, hidden: true },
      h('span', { class: 'reorder-hint' }, REORDER_HINT),
      confirm,
      cancel,
    );
    this.toolbar = h('div', { class: 'item-toolbar' }, ...nodes(this.addMenu.element, this.reorderButton, this.reorderBar));
    this.details = h(
      'details',
      { class: 'section-details' },
      h('summary', {}, h('h2', {}, this.title), this.countElement),
      this.toolbar,
      this.formElement,
      h('div', { class: 'item-body' }, this.listElement, this.detailElement),
    );
    this.element = h('section', { class: `item-section ${meta.className}`, 'aria-label': this.title }, this.details);
    this.listElement.setAttribute('aria-label', `${this.title}の一覧`);
    // 並び替えモードの間の Escape は「やめる」（メニューや欄が使った Escape は除く）
    this.element.addEventListener('keydown', (event) => {
      if (event.key !== 'Escape' || !this.reorderFiles || event.defaultPrevented) return;
      event.preventDefault();
      this.endReorder();
    });
    this.element.hidden = true;
  }

  /** 選んでいる項目の名前（テスト用） */
  get selected(): string | undefined {
    const items = this.snapshot && this.snapshot.status === 'ok' ? this.items(this.snapshot) : undefined;
    return items?.find((item) => this.itemKey(item) === this.selectedKey)?.name;
  }

  /** 項目の見分け: 番号のある種類はファイル（未使用の項目と名前が重なることがある）、ショートカットは名前 */
  protected itemKey(item: T): string {
    const file = (item as { file?: unknown }).file;
    return typeof file === 'string' ? file : item.name;
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

  /** 名前で項目を選ぶ */
  select(name: string): void {
    const items = this.snapshot && this.snapshot.status === 'ok' ? this.items(this.snapshot) : undefined;
    const item = items?.find((i) => i.name === name);
    this.selectedKey = item ? this.itemKey(item) : name;
    this.wanted = undefined;
    this.render();
  }

  /**
   * v0.4: 検証の結果の行（節「デバイス転送」など）から移る。そのファイルの項目を選び、節を開いて一覧の行へ移る。
   * この節の項目でなければ何もしない。移ったら true
   */
  revealFile(file: string): boolean {
    const items = this.snapshot && this.snapshot.status === 'ok' ? this.items(this.snapshot) : undefined;
    const item = items?.find((i) => (i as { file?: string }).file === file);
    if (!item) return false;
    this.details.open = true;
    this.selectedKey = this.itemKey(item);
    this.wanted = undefined;
    this.render();
    const row = [...this.listElement.querySelectorAll<HTMLElement>('.item-row')].find((r) => r.dataset.key === this.itemKey(item));
    (row ?? this.element).scrollIntoView?.({ block: 'nearest', behavior: 'smooth' });
    row?.focus();
    return true;
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
    const wanted = this.wanted;
    const found = wanted === undefined ? undefined : items.find((i) => ('key' in wanted ? this.itemKey(i) === wanted.key : i.name === wanted.name));
    if (found) {
      this.selectedKey = this.itemKey(found);
      this.wanted = undefined;
    }
    let item = items.find((i) => this.itemKey(i) === this.selectedKey);
    if (!item) {
      item = items[0];
      this.selectedKey = item ? this.itemKey(item) : undefined;
    }
    this.countElement.textContent = `${items.length} 件`;
    this.reconcileOrder();
    const reordering = this.reorderFiles !== undefined;
    this.element.classList.toggle('reordering', reordering);
    this.reorderBar.hidden = !reordering;
    this.addMenu.element.hidden = reordering;
    if (this.reorderButton) {
      this.reorderButton.hidden = reordering || items.length === 0;
      const few = this.arranged(snapshot).used.length < 2;
      this.reorderButton.disabled = few;
      this.reorderButton.title = few ? REORDER_TOO_FEW : `${this.title}の番号を並べ直す`;
    }
    this.renderList(items);
    this.addMenu.update(this.addMenuData(snapshot, items));
    if (!item) {
      this.disposeDetail();
      this.detailElement.replaceChildren(h('p', { class: 'item-empty' }, `${this.title}はまだありません。「追加」で作れます`));
    } else {
      this.current = this.view(item);
      this.currentItem = item;
      const shape = JSON.stringify([this.itemKey(item), item.name, this.shape(this.current)]);
      if (shape !== this.shapeKey) {
        this.shapeKey = shape;
        this.buildFrame(item);
      }
      for (const update of this.updaters) update();
      this.renderProblems(item);
    }
    if (focus) this.restoreFocus(focus);
  }

  // ---- 番号と未使用（v0.5） ----

  /** 使っている項目と未使用の項目（未保存の変更を当てた番号。番号のない種類は使っているものだけ） */
  private arranged(snapshot: ProfileSnapshot): { used: { name: string; file: string; index: number }[]; unused: { name: string; file: string }[] } {
    if (!this.indexedKind) return { used: [], unused: [] };
    return arrangeItems(snapshotItems(snapshot, this.indexedKind), this.pending);
  }

  /** 追加の一覧に出すもの（「新しく作る」・未使用の行）。番号が埋まっていれば作れず、未使用の行も選べない */
  private addMenuData(snapshot: ProfileSnapshot, items: T[]): AddMenuData {
    const kind = this.indexedKind;
    if (!kind) return { create: { label: `＋ 新しい${this.title}` }, unused: [], unusedBlocked: null };
    const { used, unused } = this.arranged(snapshot);
    const full = nextIndex(kind, used.map((item) => item.index)) === null;
    const limit = INDEX_LIMITS[kind];
    const unusedRows: AddMenuUnusedItem[] = unused.map((item) => ({
      id: item.file,
      name: item.name,
      file: item.file,
      warnings: diagnosticsIn(snapshot, item.file).filter((d) => d.severity === 'warning').length,
    }));
    return {
      create: full
        ? { label: `＋ 新しい${this.title}`, disabled: true, reason: `${this.title}は ${limit} 件までです。どれかを未使用にすると作れます` }
        : { label: `＋ 新しい${this.title}` },
      unused: unusedRows,
      unusedBlocked: full && items.length > 0 ? UNUSED_BLOCKED_REASON : null,
    };
  }

  /** 未使用の項目を使い始める（ホストが未保存の変更に積む）。一覧に現れたら選ぶ */
  private useItem(item: AddMenuUnusedItem): void {
    const kind = this.indexedKind;
    if (!kind) return;
    this.host.itemEdit({ op: 'use', kind, file: item.id });
    this.wanted = { key: item.id };
  }

  /** 追加の一覧の「同梱から」で選んだ（マクロとショートカットが決める） */
  protected pickBundled(_entry: PresetEntry): void {}

  // ---- 項目の操作（行の「…」と右クリック）----

  /** 行の「…」の項目（状態に合うものだけ） */
  private rowItems(): MoreMenuItem[] {
    const items: MoreMenuItem[] = [{ id: 'rename', label: '名前を変える' }];
    if (this.indexedKind) items.push({ id: 'unuse', label: '未使用にする' });
    items.push({ id: 'open', label: 'ファイルを開く' }, { separator: true }, { id: 'delete', label: '削除…', danger: true });
    return items;
  }

  private onRowAction(item: T, id: string): void {
    const entry = this.entry(item, this.view(item));
    const kind = this.indexedKind;
    switch (id) {
      case 'rename':
        this.openForm({ mode: 'rename', name: item.name, key: this.itemKey(item) });
        return;
      case 'unuse':
        if (kind) this.host.itemEdit({ op: 'unuse', kind, file: entry.file });
        return;
      case 'open':
        this.host.openFile(entry.file);
        return;
      case 'delete':
        this.host.itemEdit({ op: 'delete', kind: this.kind, name: item.name });
        return;
    }
  }

  /** 項目を選んでからその行のメニューを開く（右クリックと、選んでいない行の「…」）。at は右クリックの位置 */
  private openRowMenu(key: string, at?: { x: number; y: number }): void {
    if (this.selectedKey !== key) {
      this.selectedKey = key;
      this.wanted = undefined;
      this.render();
    }
    this.rowMenus.get(key)?.open('first', at);
  }

  // ---- 並び替え ----

  /** 並び替えモードか（テスト用） */
  get reordering(): boolean {
    return this.reorderFiles !== undefined;
  }

  /** 今の並び（未保存の変更を当てた番号の順）のファイル */
  private usedFiles(): string[] {
    return this.snapshot ? this.arranged(this.snapshot).used.map((item) => item.file) : [];
  }

  private startReorder(): void {
    if (!this.indexedKind || this.usedFiles().length < 2) return;
    this.closeRowMenus();
    this.reorderFiles = this.usedFiles();
    this.render();
    // 最初の行の ⬇ にフォーカスする（⬆ は先頭なので押せない）
    this.listElement.querySelector<HTMLButtonElement>('.reorder-down:not(:disabled)')?.focus();
  }

  /** 並び替えモードを抜ける（並びは捨てる） */
  private endReorder(): void {
    if (!this.reorderFiles) return;
    this.reorderFiles = undefined;
    this.render();
    this.reorderButton?.focus();
  }

  /** 確定: 並びが変わっていれば reorder を 1 回送る（ホストが未保存の変更に積む）。モードは抜ける */
  private confirmReorder(): void {
    const files = this.reorderFiles;
    const kind = this.indexedKind;
    if (!files || !kind) return;
    const now = this.usedFiles();
    if (files.length !== now.length || files.some((file, i) => file !== now[i])) this.host.itemEdit({ op: 'reorder', kind, files: [...files] });
    this.endReorder();
  }

  /** 並び替えモードで 1 つ上（-1）・下（+1）へ動かす。押したボタンにフォーカスを残す（端で押せなくなったら反対のボタンへ） */
  private moveInOrder(file: string, step: -1 | 1): void {
    const files = this.reorderFiles;
    if (!files) return;
    const from = files.indexOf(file);
    const to = from + step;
    if (from < 0 || to < 0 || to >= files.length) return;
    [files[from], files[to]] = [files[to]!, files[from]!];
    this.render();
    const row = [...this.listElement.querySelectorAll<HTMLElement>('.item-row-wrap')].find((r) => r.dataset.key === file);
    const own = row?.querySelector<HTMLButtonElement>(step < 0 ? '.reorder-up' : '.reorder-down');
    const other = row?.querySelector<HTMLButtonElement>(step < 0 ? '.reorder-down' : '.reorder-up');
    (own && !own.disabled ? own : other)?.focus();
  }

  /** 並び替えモードの並びを今の使っている項目に合わせる（モードの間に外で変わったとき: 消えたものを外し、増えたものを末尾に） */
  private reconcileOrder(): void {
    if (!this.reorderFiles) return;
    const now = this.usedFiles();
    const kept = this.reorderFiles.filter((file) => now.includes(file));
    this.reorderFiles = [...kept, ...now.filter((file) => !kept.includes(file))];
    if (this.reorderFiles.length < 2) this.reorderFiles = undefined;
  }

  private closeRowMenus(): void {
    for (const menu of this.rowMenus.values()) menu.close(false);
  }

  // ---- 一覧 ----

  private renderList(items: T[]): void {
    const snapshot = this.snapshot!;
    const order = this.reorderFiles;
    // 並び替えモードでは画面の並び。番号は行の位置に付けたまま（今の番号を小さい順に並べたもの。確定するとその番号になる）
    const listed = order ? [...items].sort((a, b) => order.indexOf(this.itemFile(a)) - order.indexOf(this.itemFile(b))) : items;
    const slots = order
      ? listed.map((item) => this.entry(item, this.view(item)).index).filter((index): index is number => index !== undefined).sort((a, b) => a - b)
      : undefined;
    this.closeRowMenus();
    this.rowMenus = new Map();
    const rows = listed.map((item, position) => {
      const entry = this.entry(item, this.view(item));
      const diagnostics = this.itemDiagnostics(entry, snapshot);
      const severity = severityOf(diagnostics);
      const changed = this.pending.some((change) => (entry.prefix ? within(change.address, entry.prefix) : change.address.file === entry.file));
      const key = this.itemKey(item);
      const selected = key === this.selectedKey;
      const row = h(
        'button',
        {
          type: 'button',
          role: 'option',
          'aria-selected': String(selected),
          class: ['item-row', selected && 'selected', changed && 'changed', severity].filter(Boolean).join(' '),
          'data-item': item.name,
          'data-key': key,
          'data-focus': `item:${key}`,
          title: entry.file,
        },
        ...nodes(
          entry.index !== undefined && h('span', { class: 'item-index' }, String(slots?.[position] ?? entry.index)),
          h('span', { class: 'item-name' }, item.name),
          entry.mark && h('span', { class: 'item-mark', title: entry.mark.title, 'aria-label': entry.mark.title }, entry.mark.text),
          entry.detail ? h('span', { class: 'item-row-detail' }, entry.detail) : null,
          severity && h('span', { class: `item-severity ${severity}`, 'aria-label': severity === 'error' ? 'エラー' : '警告' }, severity === 'error' ? '●' : '▲'),
        ),
      );
      const wrap = h('div', { class: `item-row-wrap${selected ? ' selected' : ''}${order ? ' reordering' : ''}`, role: 'presentation', 'data-key': key }, row);
      if (order) {
        // 並び替えモード: 行は選べない。⬆⬇ で画面の並びを動かす
        row.tabIndex = -1;
        row.setAttribute('aria-disabled', 'true');
        const file = entry.file;
        const up = h(
          'button',
          { type: 'button', class: 'icon-button reorder-up', 'aria-label': `「${item.name}」を 1 つ上へ`, title: '1 つ上へ', 'data-focus': `reorder-up:${key}`, disabled: position === 0 },
          '⬆',
        );
        up.addEventListener('click', () => this.moveInOrder(file, -1));
        const down = h(
          'button',
          {
            type: 'button',
            class: 'icon-button reorder-down',
            'aria-label': `「${item.name}」を 1 つ下へ`,
            title: '1 つ下へ',
            'data-focus': `reorder-down:${key}`,
            disabled: position === listed.length - 1,
          },
          '⬇',
        );
        down.addEventListener('click', () => this.moveInOrder(file, 1));
        wrap.append(h('span', { class: 'reorder-buttons' }, up, down));
        return wrap;
      }
      row.addEventListener('click', () => {
        this.selectedKey = key;
        this.wanted = undefined;
        this.render();
      });
      const menu = new MoreMenu({
        label: `「${item.name}」の操作`,
        className: 'item-row-menu',
        fixed: true,
        items: () => this.rowItems(),
        onSelect: (id) => this.onRowAction(item, id),
      });
      menu.button.dataset.focus = `item-more:${key}`;
      this.rowMenus.set(key, menu);
      // 選んでいない行の「…」は、先にその行を選んでから開く（どの項目の操作かを編集欄でも見せる）
      wrap.addEventListener(
        'click',
        (event) => {
          if (event.target instanceof Node && menu.button.contains(event.target) && !menu.isOpen && this.selectedKey !== key) {
            event.stopPropagation();
            this.openRowMenu(key);
          }
        },
        true,
      );
      row.addEventListener('contextmenu', (event) => {
        event.preventDefault();
        // キーボード（Shift+F10 など）から開いたときは位置がないので、行の左下に出す
        const rect = row.getBoundingClientRect();
        const at = event.clientX === 0 && event.clientY === 0 ? { x: rect.left, y: rect.bottom } : { x: event.clientX, y: event.clientY };
        this.openRowMenu(key, at);
      });
      wrap.append(menu.element);
      return wrap;
    });
    this.listElement.replaceChildren(...(rows.length > 0 ? rows : [h('div', { class: 'item-empty' }, '（なし）')]));
  }

  /** 項目のファイル（番号のある種類の並び替えで使う） */
  private itemFile(item: T): string {
    return (item as { file?: string }).file ?? item.name;
  }

  private itemDiagnostics(entry: ListEntry, snapshot: ProfileSnapshot): Diagnostic[] {
    return diagnosticsIn(snapshot, entry.file, entry.prefix);
  }

  // ---- 編集欄 ----

  private disposeDetail(): void {
    for (const input of this.inputs) {
      // 作り直しで消える欄の説明は mouseleave が来ないので、ここで消す
      hideTooltip(input.input);
      input.dispose();
    }
    this.inputs = [];
    this.updaters = [];
    this.fieldAddresses.clear();
    this.shapeKey = undefined;
    this.headerIndex = undefined;
  }

  private buildFrame(item: T): void {
    this.disposeDetail();
    this.shapeKey = JSON.stringify([this.itemKey(item), item.name, this.shape(this.current)]);
    const entry = this.entry(item, this.current);
    const index = entry.index !== undefined ? h('span', { class: 'item-index' }, String(entry.index)) : undefined;
    this.headerIndex = index;
    const body = h('div', { class: 'item-fields' });
    this.detailElement.replaceChildren(
      h('div', { class: 'item-header' }, h('h3', { title: entry.file }, ...nodes(index, item.name))),
      this.problems,
      body,
    );
    // 番号は未保存の変更（並び替えなど）で変わるが、欄は作り直さない
    this.addUpdater(() => {
      const now = this.entry(this.currentItem ?? item, this.current).index;
      if (this.headerIndex && now !== undefined) this.headerIndex.textContent = String(now);
    });
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

  /** 値を書き換える（Change）。field: 'note' は注記を書く */
  protected set(address: Address, value: string | number | boolean, field?: 'note'): void {
    const change: Change = { address, value, ...(field ? { field } : {}) };
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

  /**
   * キーの欄。entry は描くたびに今の姿から引く。説明（keycode/inspect の description）はレイヤーの欄と同じく、載せるかフォーカスすると出す。
   * note を付けると注記の欄も置く（注記付きの形を書ける場所だけ: タップダンスの動作・コンボの出すキー。protocol.md の 12.3）
   */
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
    /** 注記の欄を置く */
    note?: boolean;
    className?: string;
  }): HTMLElement {
    const input = new KeyInput({
      context: options.context,
      host: this.host,
      label: options.label,
      ...(options.candidateParams ? { candidateParams: options.candidateParams } : {}),
      // 割り当てのない欄は空白のまま（v0.3）
      placeholder: options.placeholder ?? '',
      presetShortcuts: true,
      onCommit: (text) => this.set(options.entry().address, text),
    });
    input.input.dataset.focus = options.focus;
    this.inputs.push(input);
    attachTooltip(input.input, () => this.describeKey(options.context, options.entry()), {
      focus: 'always',
      canShow: () => !input.isOpen && !input.isEditing,
    });
    const note = options.note ? this.noteInput(options.label, `${options.focus}:note`, options.entry) : undefined;
    const element = h(
      'div',
      { class: `item-field ${options.className ?? ''}`.trim() },
      h('label', { class: 'field-label', for: input.inputId, title: options.label }, options.visibleLabel ?? options.label),
      note ? h('div', { class: 'item-key-control' }, input.element, note.element) : input.element,
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
      note?.update(entry);
      element.classList.toggle('changed', entry.changed || entry.noteChanged);
      element.classList.toggle('has-note', entry.note !== '');
    });
    return element;
  }

  /**
   * キーの欄の注記の欄（レイヤーの欄の注記と同じ: Enter か欄を離れたら決め、Escape で戻す。空にしたら注記だけを消す）。
   * 割り当てを書いていない場所には書けない（注記は { key:, note: } の形でだけ書ける）
   */
  private noteInput(label: string, focus: string, entryOf: () => KeyEntry): { element: HTMLInputElement; update: (entry: KeyEntry) => void } {
    const element = h('input', {
      type: 'text',
      class: 'note-input',
      placeholder: '注記',
      'aria-label': `${label}の注記`,
      'data-focus': focus,
      spellcheck: 'false',
      autocomplete: 'off',
    });
    let editing = false;
    const commit = (): void => {
      if (!editing) return;
      editing = false;
      const text = element.value.trim();
      element.value = text;
      const entry = entryOf();
      if (text === entry.note) return;
      if (text === '') this.edit({ op: 'remove', address: entry.address, field: 'note' });
      else this.set(entry.address, text, 'note');
    };
    element.addEventListener('input', () => (editing = true));
    element.addEventListener('keydown', (event) => {
      if (event.key === 'Enter') {
        event.preventDefault();
        commit();
      } else if (event.key === 'Escape' && editing) {
        event.preventDefault();
        event.stopPropagation();
        editing = false;
        element.value = entryOf().note;
      }
    });
    element.addEventListener('blur', commit);
    return {
      element,
      update: (entry) => {
        if (!editing && element.value !== entry.note) element.value = entry.note;
        element.disabled = entry.text === '' && entry.note === '';
      },
    };
  }

  /** キーの欄の説明（レイヤーの欄の説明と同じ中身: 題・説明の行・注記・その欄の問題） */
  private async describeKey(context: CandidateContext, entry: KeyEntry): Promise<Node | null> {
    if (!entry.text) return null;
    const result = await this.inspector.load(context, entry.text).catch(() => undefined);
    const saved = entry.changed ? [] : this.diagnosticsAt(entry.address);
    const own = result?.diagnostics ?? [];
    const diagnostics = [...saved, ...own.filter((d) => !saved.some((s) => s.message === d.message))];
    return describeContent(entry.text, result, { note: entry.note, diagnostics });
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

  /**
   * 項目を足す。マクロ・タップダンス・コンボはホストが確認してすぐ書き、ショートカットは未保存の変更に積む（protocol.md の 15.3）。
   * 足したものが次の snapshot か未保存の変更の知らせで一覧に現れたら選ぶ
   */
  protected createItem(edit: Extract<ItemEdit, { op: 'create' }>): void {
    this.host.itemEdit(edit);
    this.wanted = { name: edit.name };
  }

  /** 今の項目の名前（追加の名前が重ならないかを見る。未使用の項目の名前も含める） */
  protected itemNames(): string[] {
    if (!this.snapshot) return [];
    const used = this.items(this.snapshot)?.map((i) => i.name) ?? [];
    return [...used, ...this.arranged(this.snapshot).unused.map((i) => i.name)];
  }

  /** 追加の欄を、名前（とショートカットの値・同梱の preset）を入れた形で開く。message は開いたときに出すエラー */
  protected openCreateForm(name: string, init: CreateFormInit = {}): void {
    this.openForm({ mode: 'create', name, ...init });
  }

  private openForm(form: NameForm): void {
    this.form = form;
    const names = this.itemNames();
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
    if (valueInput && form.value !== undefined) valueInput.setValue(form.value);
    const submit = h('button', { type: 'button', class: 'item-button primary' }, form.mode === 'create' ? '追加する' : '名前を変える');
    const cancel = h('button', { type: 'button', class: 'item-button' }, 'やめる');
    this.formMessage.replaceChildren(...(form.message ? [h('div', { class: 'message-line error' }, form.message)] : []));
    const close = (): void => {
      valueInput?.dispose();
      this.form = undefined;
      this.formElement.replaceChildren();
      if (form.mode === 'create') this.addMenu.button.focus();
      else if (form.key !== undefined) this.restoreFocus(`item-more:${form.key}`);
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
          this.wanted = { name };
        }
      } else if (this.kind === 'shortcut') {
        const value = valueInput!.input.value.trim();
        if (!value) {
          this.formMessage.replaceChildren(h('div', { class: 'message-line error' }, '値を入れてください'));
          return;
        }
        this.createItem({ op: 'create', kind: 'shortcut', name, value });
      } else {
        this.createItem({ op: 'create', kind: this.kind as 'macro' | 'tapDance' | 'combo', name, ...(form.preset ? { preset: form.preset } : {}) });
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
        h('span', { class: 'item-form-title' }, form.mode === 'create' ? `新しい${this.title}${form.preset ? `（同梱の ${form.preset}）` : ''}` : `「${form.name}」の新しい名前`),
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
