// 同梱のショートカットの木（keycode/shortcutTree。protocol.md の 5.4）から「アプリ → カテゴリ → ラベル」で選ぶ欄（アイコン付きの階層選択）。
// - kind: 'macro'（既定）: マクロの preset: に書く名前を選ぶ（spec.md の「ファイルの種類ごと」の macros/ の preset:）。手順の定義がある項目（macro: true）だけを出す
// - kind: 'shortcut'（v0.3）: キー入力欄の「同梱から選ぶ…」とショートカットの節の「同梱からコピー」（tasks-v0.3.md の決めたことの 2）。
//   キーの組の項目（macro: true でないもの）だけを出し、選んだ項目の insertText（Shortcut('…')）と text（キーの組）を渡す
// 木はプロファイルによらないので、取るのは 1 回だけ（loadShortcutTree がホストごとにとっておく）。
import type { ShortcutTreeResult } from '../protocol';
import { h } from './dom';
import type { HostClient } from './hostClient';
import { iconElement } from './icons';

export type PresetKind = 'macro' | 'shortcut';

export type PresetPickerOptions = {
  /** 木を取る（失敗したら reject） */
  loadTree: () => Promise<ShortcutTreeResult>;
  /** 今の値の名前（その行に印を付け、そのアプリとカテゴリを開いておく） */
  current: () => string | null;
  /** 選んだ（name は preset に書く名前か Shortcut('…')。entry は選んだ行） */
  onPick: (name: string, entry: PresetEntry) => void;
  /** 出す項目（既定は 'macro'） */
  kind?: PresetKind;
  /** 開くボタンの文字。null ならボタンを置かず、open() で開く（キー入力欄の「同梱から選ぶ…」） */
  buttonLabel?: string | null;
  /** 閉じた（focusBack は Escape・選んだとき。ボタンのない欄で、フォーカスを戻す先を決める） */
  onClose?: (focusBack: boolean) => void;
  /** 部品の要素に足す class */
  className?: string;
};

/** 木の中の 1 行（選べるもの）。text は kind: 'shortcut' の項目のキーの組 */
export type PresetEntry = { app: string; icon: string | null; category: string; label: string; name: string; text?: string };

const NOUN: Record<PresetKind, string> = { macro: '同梱のマクロ', shortcut: '同梱のショートカット' };

/**
 * 木から選べるもの（kind: 'macro' は macro: true の項目、'shortcut' はそれ以外）を、アプリ・カテゴリ・定義の順のまま取り出す。
 * query はアプリ・カテゴリ・ラベルへの部分一致（大文字小文字を区別しない）
 */
export function presetEntries(tree: ShortcutTreeResult, query = '', kind: PresetKind = 'macro'): PresetEntry[] {
  const entries: PresetEntry[] = [];
  for (const app of tree.apps) {
    for (const category of app.categories) {
      for (const item of category.items) {
        if (item.macro !== (kind === 'macro')) continue;
        const entry: PresetEntry = { app: app.name, icon: app.icon, category: category.name, label: item.label, name: item.insertText };
        if (item.text !== undefined) entry.text = item.text;
        entries.push(entry);
      }
    }
  }
  return filterPresetEntries(entries, query);
}

/** アプリ・カテゴリ・ラベルへの部分一致（大文字小文字を区別しない）で絞る。空の query ならそのまま */
export function filterPresetEntries(entries: PresetEntry[], query: string): PresetEntry[] {
  const q = query.trim().toLowerCase();
  if (!q) return entries;
  return entries.filter((entry) => [entry.app, entry.category, entry.label].some((text) => text.toLowerCase().includes(q)));
}

export type PresetTreeOptions = {
  /** 絞り込みの文字（空でなければすべて開いておく） */
  query: string;
  /** 今の値の名前（その行に印を付け、そのアプリとカテゴリを開いておく） */
  current: string | null;
  /** 行を押した（selected は今の値の行か） */
  onPick: (entry: PresetEntry, selected: boolean) => void;
};

/** 絞った行をアプリ → カテゴリの details に組む（PresetPicker と追加の一覧（addMenu.ts）で共通） */
export function presetTreeNodes(entries: PresetEntry[], options: PresetTreeOptions): HTMLElement[] {
  const { query, current } = options;
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
        h('div', { class: 'preset-items' }, ...items.map((entry) => presetItemButton(entry, current, options.onPick))),
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
  return apps;
}

function presetItemButton(entry: PresetEntry, current: string | null, onPick: PresetTreeOptions['onPick']): HTMLElement {
  const selected = entry.name === current;
  const button = h(
    'button',
    {
      type: 'button',
      class: `preset-item${selected ? ' selected' : ''}`,
      title: entry.text === undefined ? entry.name : `${entry.name}（${entry.text}）`,
      'aria-current': selected ? 'true' : undefined,
      'data-preset': entry.name,
    },
    entry.label,
    entry.text === undefined ? null : h('span', { class: 'preset-item-text' }, entry.text),
  );
  button.addEventListener('click', () => onPick(entry, selected));
  return button;
}

const trees = new WeakMap<HostClient, Promise<ShortcutTreeResult>>();

/** 同梱のショートカットの木をホストから取る。ホストごとに 1 回だけ取り、失敗したら次に取り直す */
export function loadShortcutTree(host: HostClient): Promise<ShortcutTreeResult> {
  let tree = trees.get(host);
  if (!tree) {
    tree = host.request('keycode/shortcutTree', {}).catch((error: unknown) => {
      trees.delete(host);
      throw error;
    });
    trees.set(host, tree);
  }
  return tree;
}

let nextPickerId = 1;

export class PresetPicker {
  readonly element: HTMLElement;
  /** 開くボタン（buttonLabel: null なら undefined） */
  readonly button: HTMLButtonElement | undefined;
  private readonly panel: HTMLElement;
  private readonly search: HTMLInputElement;
  private readonly body: HTMLElement;
  private tree: ShortcutTreeResult | undefined;
  private readonly panelId = `preset-picker-${nextPickerId++}`;
  private readonly kind: PresetKind;
  private readonly noun: string;

  constructor(private readonly options: PresetPickerOptions) {
    this.kind = options.kind ?? 'macro';
    this.noun = NOUN[this.kind];
    const label = options.buttonLabel === undefined ? '同梱のマクロから選ぶ' : options.buttonLabel;
    if (label !== null) {
      const button = h(
        'button',
        { type: 'button', class: 'item-button', 'aria-expanded': 'false', 'aria-controls': this.panelId, 'data-focus': `${this.kind === 'macro' ? 'preset' : 'shortcut-preset'}-pick` },
        label,
      );
      button.addEventListener('click', () => (this.isOpen ? this.close(true) : void this.open()));
      this.button = button;
    }
    this.search = h('input', {
      type: 'search',
      class: 'preset-search',
      placeholder: 'アプリ・カテゴリ・名前で絞り込む',
      'aria-label': `${this.noun}を絞り込む`,
      spellcheck: 'false',
      autocomplete: 'off',
      'data-focus': 'preset-search',
    });
    this.search.addEventListener('input', () => this.render());
    this.body = h('div', { class: 'preset-tree', role: 'group', 'aria-label': this.noun });
    this.panel = h('div', { class: 'preset-picker-panel', id: this.panelId, hidden: true }, this.search, this.body);
    this.panel.addEventListener('keydown', (event) => {
      if (event.key !== 'Escape') return;
      event.preventDefault();
      event.stopPropagation();
      this.close(true);
    });
    this.element = h('div', { class: `preset-picker ${options.className ?? ''}`.trim() }, this.button, this.panel);
  }

  get isOpen(): boolean {
    return !this.panel.hidden;
  }

  async open(): Promise<void> {
    this.panel.hidden = false;
    this.button?.setAttribute('aria-expanded', 'true');
    if (!this.tree) {
      this.body.replaceChildren(h('div', { class: 'item-empty' }, '読み込んでいます…'));
      try {
        this.tree = await this.options.loadTree();
      } catch (error) {
        this.body.replaceChildren(h('div', { class: 'message-line error' }, `${this.noun}の一覧を読めませんでした: ${error instanceof Error ? error.message : String(error)}`));
        return;
      }
      if (!this.isOpen) return;
    }
    this.render();
    this.search.focus();
  }

  close(focusBack = false): void {
    const wasOpen = this.isOpen;
    this.panel.hidden = true;
    this.button?.setAttribute('aria-expanded', 'false');
    if (focusBack) this.button?.focus();
    if (wasOpen) this.options.onClose?.(focusBack);
  }

  private render(): void {
    if (!this.tree) return;
    const query = this.search.value;
    const entries = presetEntries(this.tree, query, this.kind);
    if (entries.length === 0) {
      this.body.replaceChildren(h('div', { class: 'item-empty' }, query.trim() ? '合うものがありません' : `${this.noun}はありません`));
      return;
    }
    this.body.replaceChildren(
      ...presetTreeNodes(entries, {
        query,
        current: this.options.current(),
        onPick: (entry, selected) => {
          this.close(true);
          if (!selected) this.options.onPick(entry.name, entry);
        },
      }),
    );
  }
}

function unique(values: string[]): string[] {
  return [...new Set(values)];
}
