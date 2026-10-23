// 追加の一覧（issue #110 の W0）。レイヤーの「＋」とほかの節の「追加」から開き、
// 検索・「新しく作る」・「未使用（N）」・（マクロとショートカットは）同梱から、を 1 つの一覧に並べる。
// 未使用の項目は使っているものと並べず、ここからだけ使い始める（選ぶと呼ぶ側が末尾の番号で使い始める）。
// ショートカットの節の「同梱からコピー」はこの一覧の「同梱から」にまとめる。
// 約束（protocol.ts）には依存しない。渡されたデータを描いて、選んだものを callback で返すだけ（ホストとのやりとりは呼ぶ側）。
import { h } from './dom';
import { isShownInDetails, moveFocusInList } from './focusList';
import { filterPresetEntries, presetTreeNodes, type PresetEntry, type PresetKind } from './presetPicker';

/** 「新しく作る」の行。note は右に出す補足（例「番号 3 に作る」）。disabled なら reason を出す */
export type AddMenuCreate = { label?: string; note?: string; disabled?: boolean; reason?: string };

/** 未使用の 1 件。id は呼ぶ側が見分けるためのもの（そのまま onPickUnused に返す） */
export type AddMenuUnusedItem = {
  id: string;
  name: string;
  /** ファイル名（例 layers/4_数字.yaml） */
  file?: string;
  /** 警告の数（0 か省略なら出さない） */
  warnings?: number;
  /** この行だけ選べない（reason を行に出す） */
  disabled?: boolean;
  reason?: string;
};

export type AddMenuData = {
  /** 「新しく作る」の行。null なら出さない */
  create?: AddMenuCreate | null;
  /** 未使用の項目（空なら「未使用」のまとまりを出さない） */
  unused?: AddMenuUnusedItem[];
  /** 未使用のまとまり全体が選べない理由（例「番号が埋まっています。どれかを未使用にすると選べます」）。null なら選べる */
  unusedBlocked?: string | null;
};

export type AddMenuBundled = {
  /** 何の同梱か（まとまりの aria-label を「同梱のマクロ」「同梱のショートカット」にする） */
  kind: PresetKind;
  /** 同梱の行を取る（失敗したら reject）。開いたときに 1 回だけ呼ぶ */
  loadEntries: () => Promise<PresetEntry[]>;
  /** まとまりの見出し（既定は「同梱から」） */
  label?: string;
};

export type AddMenuOptions = AddMenuData & {
  /** 開くボタンの文字（レイヤーは「＋」、ほかは「追加」） */
  buttonLabel: string;
  /** 何を足すか（aria-label などに使う。例「マクロ」） */
  noun: string;
  /** 同梱から（マクロとショートカットだけ） */
  bundled?: AddMenuBundled;
  /** 「新しく作る」を選んだ（query は検索欄の文字。名前の候補に使える） */
  onCreate: (query: string) => void;
  /** 未使用の行を選んだ */
  onPickUnused: (item: AddMenuUnusedItem) => void;
  /** 同梱の行を選んだ */
  onPickBundled?: (entry: PresetEntry) => void;
  /** 閉じた（focusBack は Escape・選んだとき） */
  onClose?: (focusBack: boolean) => void;
  /** 部品の要素に足す class */
  className?: string;
};

export const ADD_MENU_CREATE_LABEL = '新しく作る';
export const ADD_MENU_BUNDLED_LABEL = '同梱から';

/** 「未使用（N）」の見出し */
export function unusedHeading(count: number): string {
  return `未使用（${count}）`;
}

let nextMenuId = 1;

export class AddMenu {
  readonly element: HTMLElement;
  readonly button: HTMLButtonElement;
  private readonly badge: HTMLElement;
  private readonly panel: HTMLElement;
  private readonly search: HTMLInputElement;
  private readonly body: HTMLElement;
  private readonly panelId = `add-menu-${nextMenuId++}`;
  private data: AddMenuData;
  private bundled: PresetEntry[] | undefined;
  private bundledError: string | undefined;

  constructor(private readonly options: AddMenuOptions) {
    this.data = { create: options.create, unused: options.unused, unusedBlocked: options.unusedBlocked };
    this.badge = h('span', { class: 'add-menu-badge', hidden: true });
    this.button = h(
      'button',
      {
        type: 'button',
        class: 'item-button add-menu-button',
        'aria-haspopup': 'true',
        'aria-expanded': 'false',
        'aria-controls': this.panelId,
        'aria-label': options.buttonLabel === '追加' ? undefined : `${options.noun}を追加`,
        'data-focus': 'add-menu',
      },
      options.buttonLabel,
      this.badge,
    );
    this.button.addEventListener('click', () => (this.isOpen ? this.close(true) : void this.open()));
    this.button.addEventListener('keydown', (event) => {
      if (event.key !== 'ArrowDown' || this.isOpen) return;
      event.preventDefault();
      void this.open();
    });
    this.search = h('input', {
      type: 'search',
      class: 'add-menu-search',
      placeholder: '名前で絞り込む',
      'aria-label': `追加する${options.noun}を絞り込む`,
      spellcheck: 'false',
      autocomplete: 'off',
      'data-focus': 'add-menu-search',
    });
    this.search.addEventListener('input', () => this.render());
    this.body = h('div', { class: 'add-menu-body' });
    this.panel = h('div', { class: 'add-menu-panel', id: this.panelId, role: 'dialog', 'aria-label': `${options.noun}を追加`, hidden: true }, this.search, this.body);
    this.panel.addEventListener('keydown', (event) => this.onKeydown(event));
    this.panel.addEventListener('focusout', (event) => {
      // Tab で一覧の外へ出たら閉じる（フォーカスは移った先のまま）
      const next = event.relatedTarget;
      if (next instanceof Node && !this.element.contains(next)) this.close(false);
    });
    this.element = h('div', { class: `add-menu ${options.className ?? ''}`.trim() }, this.button, this.panel);
    this.updateBadge();
  }

  get isOpen(): boolean {
    return !this.panel.hidden;
  }

  /** 未使用の項目や「新しく作る」の補足が変わった（開いていれば描き直す） */
  update(data: AddMenuData): void {
    this.data = { ...this.data, ...data };
    this.updateBadge();
    if (this.isOpen) this.render();
  }

  async open(): Promise<void> {
    if (this.isOpen) return;
    this.panel.hidden = false;
    this.button.setAttribute('aria-expanded', 'true');
    document.addEventListener('mousedown', this.outside, true);
    this.search.value = '';
    this.render();
    this.search.focus();
    const bundled = this.options.bundled;
    if (bundled && !this.bundled) {
      try {
        this.bundled = await bundled.loadEntries();
        this.bundledError = undefined;
      } catch (error) {
        this.bundledError = error instanceof Error ? error.message : String(error);
      }
      if (this.isOpen) this.render();
    }
  }

  close(focusBack = false): void {
    if (!this.isOpen) return;
    this.panel.hidden = true;
    this.button.setAttribute('aria-expanded', 'false');
    document.removeEventListener('mousedown', this.outside, true);
    if (focusBack) this.button.focus();
    this.options.onClose?.(focusBack);
  }

  /** 開いている間、部品の外を押したら閉じる */
  private readonly outside = (event: MouseEvent): void => {
    if (event.target instanceof Node && this.element.contains(event.target)) return;
    this.close(false);
  };

  private updateBadge(): void {
    const count = this.data.unused?.length ?? 0;
    this.badge.hidden = count === 0;
    this.badge.textContent = count === 0 ? '' : String(count);
    this.button.title = count === 0 ? '' : `未使用の${this.options.noun}が ${count} 件あります`;
  }

  private onKeydown(event: KeyboardEvent): void {
    if (event.key === 'Escape') {
      event.preventDefault();
      event.stopPropagation();
      this.close(true);
      return;
    }
    if (!['ArrowDown', 'ArrowUp', 'Home', 'End'].includes(event.key)) return;
    // 検索欄の中の Home / End は文字の移動に使う
    if (event.target === this.search && (event.key === 'Home' || event.key === 'End')) return;
    const items = [this.search, ...this.focusables()];
    if (moveFocusInList(items, event.key)) event.preventDefault();
  }

  /** 上下で動ける行（押せる行と、開いて見えている details の summary） */
  private focusables(): HTMLElement[] {
    return [...this.body.querySelectorAll<HTMLElement>('button:not(:disabled), summary')].filter((element) => isShownInDetails(element, this.body));
  }

  private render(): void {
    const query = this.search.value;
    const q = query.trim().toLowerCase();
    const groups: HTMLElement[] = [];
    const create = this.data.create;
    if (create !== null && create !== undefined) groups.push(this.createRow(create, query));

    const unused = this.data.unused ?? [];
    if (unused.length > 0) {
      const shown = q ? unused.filter((item) => [item.name, item.file ?? ''].some((text) => text.toLowerCase().includes(q))) : unused;
      const blocked = this.data.unusedBlocked ?? null;
      groups.push(
        h(
          'div',
          { class: `add-menu-group add-menu-unused${blocked ? ' blocked' : ''}`, role: 'group', 'aria-label': unusedHeading(unused.length) },
          h('div', { class: 'add-menu-heading' }, unusedHeading(unused.length)),
          blocked ? h('div', { class: 'add-menu-reason' }, blocked) : null,
          ...(shown.length === 0 ? [h('div', { class: 'add-menu-empty' }, '合うものがありません')] : shown.map((item) => this.unusedRow(item, blocked))),
        ),
      );
    }

    const bundled = this.options.bundled;
    if (bundled) groups.push(this.bundledGroup(bundled, query));
    this.body.replaceChildren(...groups);
  }

  private createRow(create: AddMenuCreate, query: string): HTMLElement {
    const disabled = create.disabled === true;
    const button = h(
      'button',
      { type: 'button', class: 'add-menu-row add-menu-create', disabled, 'data-add': 'create' },
      h('span', { class: 'add-menu-label' }, create.label ?? ADD_MENU_CREATE_LABEL),
      create.note ? h('span', { class: 'add-menu-note' }, create.note) : null,
    );
    button.addEventListener('click', () => {
      this.close(true);
      this.options.onCreate(query.trim());
    });
    return h('div', { class: 'add-menu-group' }, button, disabled && create.reason ? h('div', { class: 'add-menu-reason' }, create.reason) : null);
  }

  private unusedRow(item: AddMenuUnusedItem, blocked: string | null): HTMLElement {
    const disabled = blocked !== null || item.disabled === true;
    const reason = blocked === null && item.disabled ? item.reason : undefined;
    const warnings = item.warnings ?? 0;
    const button = h(
      'button',
      { type: 'button', class: 'add-menu-row add-menu-unused-item', disabled, title: item.file, 'data-unused': item.id },
      h('span', { class: 'add-menu-label' }, item.name),
      item.file ? h('span', { class: 'add-menu-file' }, item.file) : null,
      warnings > 0 ? h('span', { class: 'add-menu-warnings', title: `警告 ${warnings} 件` }, `⚠ ${warnings}`) : null,
      reason ? h('span', { class: 'add-menu-row-reason' }, reason) : null,
    );
    button.addEventListener('click', () => {
      this.close(true);
      this.options.onPickUnused(item);
    });
    return button;
  }

  private bundledGroup(bundled: AddMenuBundled, query: string): HTMLElement {
    const label = bundled.label ?? ADD_MENU_BUNDLED_LABEL;
    const noun = bundled.kind === 'macro' ? '同梱のマクロ' : '同梱のショートカット';
    const group = h('div', { class: 'add-menu-group add-menu-bundled', role: 'group', 'aria-label': noun, 'data-kind': bundled.kind }, h('div', { class: 'add-menu-heading' }, label));
    if (this.bundledError !== undefined) {
      group.append(h('div', { class: 'message-line error' }, `同梱の一覧を読めませんでした: ${this.bundledError}`));
      return group;
    }
    if (!this.bundled) {
      group.append(h('div', { class: 'add-menu-empty' }, '読み込んでいます…'));
      return group;
    }
    const entries = filterPresetEntries(this.bundled, query);
    if (entries.length === 0) {
      group.append(h('div', { class: 'add-menu-empty' }, query.trim() ? '合うものがありません' : 'ありません'));
      return group;
    }
    group.append(
      h(
        'div',
        { class: 'preset-tree add-menu-tree' },
        ...presetTreeNodes(entries, {
          query,
          current: null,
          onPick: (entry) => {
            this.close(true);
            this.options.onPickBundled?.(entry);
          },
        }),
      ),
    );
    return group;
  }
}
