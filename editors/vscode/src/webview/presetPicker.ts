// マクロの preset: を、同梱のショートカットの木（keycode/shortcutTree。protocol.md の 5.4）から「アプリ → カテゴリ → ラベル」で選ぶ欄
// （spec.md の「ファイルの種類ごと」の macros/ の preset: の「アイコン付きの階層選択」）。
// 出すのは手順の定義がある同梱ショートカット（macro: true）だけ。1 シーケンスの定義の名前は preset の欄に打てば使える。
// 木はプロファイルによらないので、取るのは 1 回だけ（loadTree を渡す側がとっておく）。
import type { ShortcutTreeResult } from '../protocol';
import { h } from './dom';
import { iconElement } from './icons';

export type PresetPickerOptions = {
  /** 木を取る（失敗したら reject） */
  loadTree: () => Promise<ShortcutTreeResult>;
  /** 今の preset の名前（その行に印を付け、そのアプリとカテゴリを開いておく） */
  current: () => string | null;
  /** 選んだ（preset に書く名前） */
  onPick: (name: string) => void;
};

/** 木の中の 1 行（選べるもの） */
export type PresetEntry = { app: string; icon: string | null; category: string; label: string; name: string };

/** 木から preset に書けるもの（macro: true）を、アプリ・カテゴリ・定義の順のまま取り出す。query はアプリ・カテゴリ・ラベルへの部分一致（大文字小文字を区別しない） */
export function presetEntries(tree: ShortcutTreeResult, query = ''): PresetEntry[] {
  const q = query.trim().toLowerCase();
  const entries: PresetEntry[] = [];
  for (const app of tree.apps) {
    for (const category of app.categories) {
      for (const item of category.items) {
        if (!item.macro) continue;
        const entry = { app: app.name, icon: app.icon, category: category.name, label: item.label, name: item.insertText };
        if (q && ![entry.app, entry.category, entry.label].some((text) => text.toLowerCase().includes(q))) continue;
        entries.push(entry);
      }
    }
  }
  return entries;
}

let nextPickerId = 1;

export class PresetPicker {
  readonly element: HTMLElement;
  readonly button: HTMLButtonElement;
  private readonly panel: HTMLElement;
  private readonly search: HTMLInputElement;
  private readonly body: HTMLElement;
  private tree: ShortcutTreeResult | undefined;
  private readonly panelId = `preset-picker-${nextPickerId++}`;

  constructor(private readonly options: PresetPickerOptions) {
    this.button = h(
      'button',
      { type: 'button', class: 'item-button', 'aria-expanded': 'false', 'aria-controls': this.panelId, 'data-focus': 'preset-pick' },
      '同梱のマクロから選ぶ',
    );
    this.button.addEventListener('click', () => (this.isOpen ? this.close(true) : void this.open()));
    this.search = h('input', {
      type: 'search',
      class: 'preset-search',
      placeholder: 'アプリ・カテゴリ・名前で絞り込む',
      'aria-label': '同梱のマクロを絞り込む',
      spellcheck: 'false',
      autocomplete: 'off',
      'data-focus': 'preset-search',
    });
    this.search.addEventListener('input', () => this.render());
    this.body = h('div', { class: 'preset-tree', role: 'group', 'aria-label': '同梱のマクロ' });
    this.panel = h('div', { class: 'preset-picker-panel', id: this.panelId, hidden: true }, this.search, this.body);
    this.panel.addEventListener('keydown', (event) => {
      if (event.key !== 'Escape') return;
      event.preventDefault();
      event.stopPropagation();
      this.close(true);
    });
    this.element = h('div', { class: 'preset-picker' }, this.button, this.panel);
  }

  get isOpen(): boolean {
    return !this.panel.hidden;
  }

  async open(): Promise<void> {
    this.panel.hidden = false;
    this.button.setAttribute('aria-expanded', 'true');
    if (!this.tree) {
      this.body.replaceChildren(h('div', { class: 'item-empty' }, '読み込んでいます…'));
      try {
        this.tree = await this.options.loadTree();
      } catch (error) {
        this.body.replaceChildren(h('div', { class: 'message-line error' }, `同梱のマクロの一覧を読めませんでした: ${error instanceof Error ? error.message : String(error)}`));
        return;
      }
      if (!this.isOpen) return;
    }
    this.render();
    this.search.focus();
  }

  close(focusBack = false): void {
    this.panel.hidden = true;
    this.button.setAttribute('aria-expanded', 'false');
    if (focusBack) this.button.focus();
  }

  private render(): void {
    if (!this.tree) return;
    const query = this.search.value;
    const entries = presetEntries(this.tree, query);
    if (entries.length === 0) {
      this.body.replaceChildren(h('div', { class: 'item-empty' }, query.trim() ? '合うものがありません' : '同梱のマクロはありません'));
      return;
    }
    const current = this.options.current();
    // 絞り込んでいるときと、今の preset のあるところは開いておく
    const opened = (match: (entry: PresetEntry) => boolean) => query.trim() !== '' || entries.some((entry) => match(entry) && entry.name === current);
    const apps: HTMLElement[] = [];
    for (const app of unique(entries.map((entry) => entry.app))) {
      const inApp = entries.filter((entry) => entry.app === app);
      const categories = unique(inApp.map((entry) => entry.category)).map((category) => {
        const items = inApp.filter((entry) => entry.category === category);
        return h(
          'details',
          { class: 'preset-category', open: opened((entry) => entry.app === app && entry.category === category) },
          h('summary', {}, category, h('span', { class: 'preset-count' }, String(items.length))),
          h('div', { class: 'preset-items' }, ...items.map((entry) => this.itemButton(entry, current))),
        );
      });
      apps.push(
        h(
          'details',
          { class: 'preset-app', open: opened((entry) => entry.app === app) },
          h('summary', {}, h('span', { class: 'candidate-icon' }, iconElement(inApp[0]!.icon)), app, h('span', { class: 'preset-count' }, String(inApp.length))),
          ...categories,
        ),
      );
    }
    this.body.replaceChildren(...apps);
  }

  private itemButton(entry: PresetEntry, current: string | null): HTMLElement {
    const selected = entry.name === current;
    const button = h(
      'button',
      {
        type: 'button',
        class: `preset-item${selected ? ' selected' : ''}`,
        title: entry.name,
        'aria-current': selected ? 'true' : undefined,
        'data-preset': entry.name,
      },
      entry.label,
    );
    button.addEventListener('click', () => {
      this.close(true);
      if (!selected) this.options.onPick(entry.name);
    });
    return button;
  }
}

function unique(values: string[]): string[] {
  return [...new Set(values)];
}
