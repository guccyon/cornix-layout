// 見出しの「…」メニュー（issue #110 の W0）。項目の操作（番号を変える… / 未使用にする / 名前を変える / 削除…）を 1 つにまとめ、
// 今の状態に合うものだけを呼ぶ側が渡す（items は開くたびに呼ぶ）。
// 押せない項目は残して理由を添える（隠すと、なぜできないのか分からない）。WAI-ARIA の menu button の形:
// ボタンは aria-haspopup・aria-expanded。上下・Home/End で動き、Enter / Space で選ぶ。Escape で閉じてボタンにフォーカスを戻す。外を押すか Tab で閉じる。
import { h } from './dom';
import { moveFocusInList } from './focusList';

export type MoreMenuAction = {
  /** 呼ぶ側が見分けるためのもの（そのまま onSelect に返す） */
  id: string;
  label: string;
  /** 右に添える補足（例「いま 1」）。読み上げは aria-describedby で */
  note?: string;
  /** 危ない操作（削除など。赤で出す） */
  danger?: boolean;
  /** 押せない（reason を下に出す） */
  disabled?: boolean;
  reason?: string;
};

/** 区切り */
export type MoreMenuSeparator = { separator: true };

export type MoreMenuItem = MoreMenuAction | MoreMenuSeparator;

export type MoreMenuOptions = {
  /** 出す項目（開くたびに呼ぶ） */
  items: () => MoreMenuItem[];
  /** 項目を選んだ（閉じてボタンにフォーカスを戻してから呼ぶ） */
  onSelect: (id: string) => void;
  /** ボタンの aria-label（既定は「ほかの操作」） */
  label?: string;
  /** 部品の要素に足す class */
  className?: string;
};

export const MORE_MENU_LABEL = 'ほかの操作';

let nextMenuId = 1;

export class MoreMenu {
  readonly element: HTMLElement;
  readonly button: HTMLButtonElement;
  private readonly menu: HTMLElement;
  private readonly menuId = `more-menu-${nextMenuId++}`;

  constructor(private readonly options: MoreMenuOptions) {
    const label = options.label ?? MORE_MENU_LABEL;
    this.button = h(
      'button',
      {
        type: 'button',
        class: 'icon-button more-menu-button',
        'aria-label': label,
        title: label,
        'aria-haspopup': 'menu',
        'aria-expanded': 'false',
        'aria-controls': this.menuId,
        'data-focus': 'more-menu',
      },
      '…',
    );
    this.button.addEventListener('click', () => (this.isOpen ? this.close(true) : this.open('first')));
    this.button.addEventListener('keydown', (event) => {
      if (event.key !== 'ArrowDown' && event.key !== 'ArrowUp') return;
      event.preventDefault();
      this.open(event.key === 'ArrowUp' ? 'last' : 'first');
    });
    this.menu = h('div', { class: 'more-menu-list', id: this.menuId, role: 'menu', 'aria-label': label, hidden: true });
    this.menu.addEventListener('keydown', (event) => this.onKeydown(event));
    this.menu.addEventListener('focusout', (event) => {
      const next = event.relatedTarget;
      if (next instanceof Node && !this.element.contains(next)) this.close(false);
    });
    this.element = h('div', { class: `more-menu ${options.className ?? ''}`.trim() }, this.button, this.menu);
  }

  get isOpen(): boolean {
    return !this.menu.hidden;
  }

  /** 開いて、最初（か最後）の項目にフォーカスする */
  open(focus: 'first' | 'last' = 'first'): void {
    this.render();
    this.menu.hidden = false;
    this.button.setAttribute('aria-expanded', 'true');
    document.addEventListener('mousedown', this.outside, true);
    const items = this.menuItems();
    (focus === 'first' ? items[0] : items[items.length - 1])?.focus();
  }

  close(focusBack = false): void {
    if (!this.isOpen) return;
    this.menu.hidden = true;
    this.button.setAttribute('aria-expanded', 'false');
    document.removeEventListener('mousedown', this.outside, true);
    if (focusBack) this.button.focus();
  }

  private readonly outside = (event: MouseEvent): void => {
    if (event.target instanceof Node && this.element.contains(event.target)) return;
    this.close(false);
  };

  private menuItems(): HTMLElement[] {
    return [...this.menu.querySelectorAll<HTMLElement>("[role='menuitem']")];
  }

  private onKeydown(event: KeyboardEvent): void {
    if (event.key === 'Escape') {
      event.preventDefault();
      event.stopPropagation();
      this.close(true);
      return;
    }
    if (event.key === 'Tab') {
      this.close(false);
      return;
    }
    if (moveFocusInList(this.menuItems(), event.key)) event.preventDefault();
  }

  private render(): void {
    let reasonId = 0;
    const rows = this.options.items().map((item) => {
      if ('separator' in item) return h('div', { class: 'more-menu-separator', role: 'separator' });
      const disabled = item.disabled === true;
      const reason = disabled && item.reason ? h('span', { class: 'more-menu-reason', id: `${this.menuId}-reason-${reasonId++}` }, item.reason) : null;
      const note = item.note ? h('span', { class: 'more-menu-note', id: `${this.menuId}-note-${reasonId++}` }, item.note) : null;
      const label = h('span', { class: 'more-menu-label' }, item.label);
      // 押せない項目もフォーカスできるように残す（aria-disabled。理由を読み上げる）
      const button = h(
        'button',
        {
          type: 'button',
          class: `more-menu-item${item.danger ? ' danger' : ''}${disabled ? ' disabled' : ''}`,
          role: 'menuitem',
          tabindex: '-1',
          'aria-disabled': disabled ? 'true' : undefined,
          'aria-describedby': [note?.id, reason?.id].filter(Boolean).join(' ') || undefined,
          'data-action': item.id,
        },
        note ? h('span', { class: 'more-menu-line' }, label, note) : label,
        reason,
      );
      button.addEventListener('click', () => {
        if (disabled) return;
        this.close(true);
        this.options.onSelect(item.id);
      });
      return button;
    });
    this.menu.replaceChildren(...rows);
  }
}
