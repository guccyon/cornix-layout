// @vitest-environment happy-dom
// v0.5 の画面の共通部品（issue #110 の W0）: 追加の一覧（addMenu.ts）・「…」メニュー（moreMenu.ts）・番号の選択（indexPicker.ts）
import { afterEach, describe, expect, it } from 'vitest';
import { AddMenu, type AddMenuOptions, type AddMenuUnusedItem } from '../../../src/webview/addMenu';
import { IndexPicker, type IndexPickerOptions, type IndexMode } from '../../../src/webview/indexPicker';
import { MORE_MENU_LABEL, MoreMenu, type MoreMenuItem } from '../../../src/webview/moreMenu';
import { presetEntries } from '../../../src/webview/presetPicker';
import * as data from '../../fake-server/fixtures';
import { settle } from './fakeHost';

function keydown(target: EventTarget, key: string): void {
  target.dispatchEvent(new KeyboardEvent('keydown', { key, bubbles: true, cancelable: true }));
}

function texts(elements: Iterable<Element>): string[] {
  return [...elements].map((element) => element.textContent ?? '');
}

afterEach(() => {
  document.body.replaceChildren();
});

describe('追加の一覧（AddMenu）', () => {
  const UNUSED: AddMenuUnusedItem[] = [
    { id: 'a', name: '数字', file: 'layers/数字.yaml', warnings: 2 },
    { id: 'b', name: '記号', file: 'layers/記号.yaml' },
  ];

  function mount(overrides: Partial<AddMenuOptions> = {}) {
    const picked: string[] = [];
    const menu = new AddMenu({
      buttonLabel: '追加',
      noun: 'マクロ',
      create: { note: '番号 3 に作る' },
      unused: UNUSED,
      onCreate: (query) => picked.push(`create:${query}`),
      onPickUnused: (item) => picked.push(`unused:${item.id}`),
      onPickBundled: (entry) => picked.push(`bundled:${entry.name}`),
      ...overrides,
    });
    document.body.append(menu.element);
    return { menu, picked };
  }

  it('開くボタンに未使用の数を小さく出し、0 なら出さない', () => {
    const { menu } = mount();
    const badge = menu.button.querySelector<HTMLElement>('.add-menu-badge')!;
    expect(badge.hidden).toBe(false);
    expect(badge.textContent).toBe('2');
    menu.update({ unused: [] });
    expect(badge.hidden).toBe(true);
    expect(menu.button.getAttribute('aria-expanded')).toBe('false');
  });

  it('「新しく作る」（補足付き）と「未使用（N）」（名前・ファイル名・警告の数）を並べ、検索で絞る', async () => {
    const { menu, picked } = mount();
    menu.button.click();
    await settle();
    expect(menu.isOpen).toBe(true);
    expect(document.activeElement?.classList.contains('add-menu-search')).toBe(true);
    const create = menu.element.querySelector<HTMLButtonElement>('.add-menu-create')!;
    expect(texts(create.children)).toEqual(['新しく作る', '番号 3 に作る']);
    expect(menu.element.querySelector('.add-menu-unused .add-menu-heading')?.textContent).toBe('未使用（2）');
    const rows = [...menu.element.querySelectorAll<HTMLButtonElement>('.add-menu-unused-item')];
    expect(texts(rows[0]!.children)).toEqual(['数字', 'layers/数字.yaml', '⚠ 2']);
    expect(rows[1]!.querySelector('.add-menu-warnings')).toBeNull();

    const search = menu.element.querySelector<HTMLInputElement>('.add-menu-search')!;
    search.value = '記号';
    search.dispatchEvent(new Event('input'));
    // 見出しの数は全体のまま
    expect(menu.element.querySelector('.add-menu-unused .add-menu-heading')?.textContent).toBe('未使用（2）');
    expect(texts(menu.element.querySelectorAll('.add-menu-unused-item .add-menu-label'))).toEqual(['記号']);

    menu.element.querySelector<HTMLButtonElement>('.add-menu-create')!.click();
    expect(picked).toEqual(['create:記号']);
    expect(menu.isOpen).toBe(false);
    expect(document.activeElement).toBe(menu.button);
  });

  it('未使用を選ぶと onPickUnused。まとまり全体が選べないときは理由を 1 行出して行を押せなくする', async () => {
    const { menu, picked } = mount();
    menu.button.click();
    await settle();
    menu.element.querySelector<HTMLButtonElement>("[data-unused='b']")!.click();
    expect(picked).toEqual(['unused:b']);

    menu.update({ unusedBlocked: '番号が埋まっています。どれかを未使用にすると選べます' });
    menu.button.click();
    await settle();
    expect(menu.element.querySelector('.add-menu-unused .add-menu-reason')?.textContent).toBe('番号が埋まっています。どれかを未使用にすると選べます');
    expect([...menu.element.querySelectorAll<HTMLButtonElement>('.add-menu-unused-item')].every((row) => row.disabled)).toBe(true);
  });

  it('行ごとに選べない状態と理由を出せる。「新しく作る」も選べなくできる', async () => {
    const { menu } = mount({
      create: { note: '番号 32 に作る', disabled: true, reason: '番号が埋まっています' },
      unused: [{ id: 'a', name: '数字', disabled: true, reason: '名前が使っているものと同じです' }, UNUSED[1]!],
    });
    menu.button.click();
    await settle();
    expect(menu.element.querySelector<HTMLButtonElement>('.add-menu-create')!.disabled).toBe(true);
    expect(menu.element.querySelector('.add-menu-group .add-menu-reason')?.textContent).toBe('番号が埋まっています');
    const [first, second] = [...menu.element.querySelectorAll<HTMLButtonElement>('.add-menu-unused-item')];
    expect(first!.disabled).toBe(true);
    expect(first!.querySelector('.add-menu-row-reason')?.textContent).toBe('名前が使っているものと同じです');
    expect(second!.disabled).toBe(false);
  });

  it('未使用がなければまとまりを出さず、create: null なら「新しく作る」も出さない', async () => {
    const { menu } = mount({ unused: [], create: null });
    menu.button.click();
    await settle();
    expect(menu.element.querySelector('.add-menu-unused')).toBeNull();
    expect(menu.element.querySelector('.add-menu-create')).toBeNull();
  });

  it('同梱から（kind: shortcut）: 階層の選択を中に出し、検索で絞り、選ぶと onPickBundled', async () => {
    let loads = 0;
    const { menu, picked } = mount({
      bundled: {
        kind: 'shortcut',
        loadEntries: async () => {
          loads++;
          return presetEntries(data.SHORTCUT_TREE, '', 'shortcut');
        },
      },
    });
    menu.button.click();
    await settle();
    const group = menu.element.querySelector<HTMLElement>('.add-menu-bundled')!;
    expect(group.getAttribute('aria-label')).toBe('同梱のショートカット');
    expect(group.querySelector('.add-menu-heading')?.textContent).toBe('同梱から');
    expect(group.querySelectorAll('.preset-item')).toHaveLength(2);

    const search = menu.element.querySelector<HTMLInputElement>('.add-menu-search')!;
    search.value = 'figma';
    search.dispatchEvent(new Event('input'));
    const items = [...menu.element.querySelectorAll<HTMLButtonElement>('.add-menu-bundled .preset-item')];
    expect(items.map((item) => item.dataset.preset)).toEqual(["Shortcut('Figma:ツール:フレーム')"]);
    items[0]!.click();
    expect(picked).toEqual(["bundled:Shortcut('Figma:ツール:フレーム')"]);

    menu.button.click();
    await settle();
    expect(loads).toBe(1);
  });

  it('同梱の一覧を読めなければそのまとまりにだけ出す', async () => {
    const { menu } = mount({ bundled: { kind: 'macro', loadEntries: () => Promise.reject(new Error('落ちた')) } });
    menu.button.click();
    await settle();
    expect(menu.element.querySelector('.add-menu-bundled .message-line.error')?.textContent).toBe('同梱の一覧を読めませんでした: 落ちた');
    expect(menu.element.querySelector('.add-menu-create')).not.toBeNull();
  });

  it('上下で行を動き、Escape で閉じてボタンに戻る。外を押すと閉じる', async () => {
    const { menu } = mount();
    menu.button.click();
    await settle();
    const search = menu.element.querySelector<HTMLInputElement>('.add-menu-search')!;
    keydown(search, 'ArrowDown');
    expect(document.activeElement?.classList.contains('add-menu-create')).toBe(true);
    keydown(document.activeElement!, 'ArrowDown');
    expect((document.activeElement as HTMLElement).dataset.unused).toBe('a');
    keydown(document.activeElement!, 'Escape');
    expect(menu.isOpen).toBe(false);
    expect(document.activeElement).toBe(menu.button);

    menu.button.click();
    await settle();
    const outside = document.createElement('div');
    document.body.append(outside);
    outside.dispatchEvent(new MouseEvent('mousedown', { bubbles: true }));
    expect(menu.isOpen).toBe(false);
  });

  it('「＋」のボタンには aria-label を付ける', () => {
    const { menu } = mount({ buttonLabel: '＋', noun: 'レイヤー' });
    expect(menu.button.getAttribute('aria-label')).toBe('レイヤーを追加');
    expect(menu.button.getAttribute('aria-haspopup')).toBe('true');
  });
});

describe('「…」メニュー（MoreMenu）', () => {
  const ITEMS: MoreMenuItem[] = [
    { id: 'index', label: '番号を変える…' },
    { id: 'unuse', label: '未使用にする', disabled: true, reason: '使っているレイヤーが 1 つだけです' },
    { id: 'rename', label: '名前を変える' },
    { separator: true },
    { id: 'delete', label: '削除…', danger: true },
  ];

  function mount(items: MoreMenuItem[] = ITEMS) {
    const selected: string[] = [];
    const menu = new MoreMenu({ items: () => items, onSelect: (id) => selected.push(id) });
    document.body.append(menu.element);
    return { menu, selected };
  }

  function focusedAction(): string | undefined {
    return (document.activeElement as HTMLElement | null)?.dataset.action;
  }

  it('ボタンは aria-label「ほかの操作」・aria-haspopup・aria-expanded', () => {
    const { menu } = mount();
    expect(menu.button.getAttribute('aria-label')).toBe(MORE_MENU_LABEL);
    expect(menu.button.getAttribute('aria-haspopup')).toBe('menu');
    expect(menu.button.getAttribute('aria-expanded')).toBe('false');
    menu.button.click();
    expect(menu.button.getAttribute('aria-expanded')).toBe('true');
  });

  it('項目・区切り・危ない操作・押せない項目と理由を出し、押せない項目は選べない', () => {
    const { menu, selected } = mount();
    menu.button.click();
    const items = [...menu.element.querySelectorAll<HTMLButtonElement>("[role='menuitem']")];
    expect(items.map((item) => item.querySelector('.more-menu-label')?.textContent)).toEqual(['番号を変える…', '未使用にする', '名前を変える', '削除…']);
    expect(menu.element.querySelectorAll("[role='separator']")).toHaveLength(1);
    expect(items[3]!.classList.contains('danger')).toBe(true);
    const disabled = items[1]!;
    expect(disabled.getAttribute('aria-disabled')).toBe('true');
    const reasonId = disabled.getAttribute('aria-describedby')!;
    expect(document.getElementById(reasonId)?.textContent).toBe('使っているレイヤーが 1 つだけです');
    disabled.click();
    expect(selected).toEqual([]);
    expect(menu.isOpen).toBe(true);
    items[2]!.click();
    expect(selected).toEqual(['rename']);
    expect(menu.isOpen).toBe(false);
    expect(document.activeElement).toBe(menu.button);
  });

  it('上下・Home/End で動き（端で回る）、Escape で閉じてボタンにフォーカスを戻す', () => {
    const { menu } = mount();
    menu.button.click();
    expect(focusedAction()).toBe('index');
    keydown(document.activeElement!, 'ArrowDown');
    expect(focusedAction()).toBe('unuse');
    keydown(document.activeElement!, 'End');
    expect(focusedAction()).toBe('delete');
    keydown(document.activeElement!, 'ArrowDown');
    expect(focusedAction()).toBe('index');
    keydown(document.activeElement!, 'ArrowUp');
    expect(focusedAction()).toBe('delete');
    keydown(document.activeElement!, 'Home');
    expect(focusedAction()).toBe('index');
    keydown(document.activeElement!, 'Escape');
    expect(menu.isOpen).toBe(false);
    expect(document.activeElement).toBe(menu.button);
  });

  it('ボタンで上を押すと最後の項目から開く。開くたびに items を呼び直す', () => {
    let items: MoreMenuItem[] = ITEMS;
    const menu = new MoreMenu({ items: () => items, onSelect: () => {} });
    document.body.append(menu.element);
    keydown(menu.button, 'ArrowUp');
    expect(focusedAction()).toBe('delete');
    menu.close();
    items = [{ id: 'rename', label: '名前を変える' }];
    menu.open();
    expect(menu.element.querySelectorAll("[role='menuitem']")).toHaveLength(1);
  });

  it('外を押すと閉じる（フォーカスは戻さない）', () => {
    const { menu } = mount();
    menu.button.click();
    const outside = document.createElement('button');
    document.body.append(outside);
    outside.dispatchEvent(new MouseEvent('mousedown', { bubbles: true }));
    expect(menu.isOpen).toBe(false);
    expect(menu.button.getAttribute('aria-expanded')).toBe('false');
  });
});

describe('番号の選択（IndexPicker）', () => {
  function mount(overrides: Partial<IndexPickerOptions> = {}) {
    const confirmed: [number, IndexMode][] = [];
    let closed = 0;
    const back = document.createElement('button');
    document.body.append(back);
    const picker = new IndexPicker({
      noun: 'レイヤー',
      name: '数字',
      current: 1,
      limit: 10,
      used: new Map([
        [0, '基本'],
        [1, '数字'],
        [2, '記号'],
      ]),
      onConfirm: (target, mode) => confirmed.push([target, mode]),
      onClose: () => closed++,
      returnFocus: back,
      ...overrides,
    });
    document.body.append(picker.element);
    return { picker, confirmed, back, closed: () => closed };
  }

  function slot(picker: IndexPicker, index: number): HTMLButtonElement {
    return picker.element.querySelector<HTMLButtonElement>(`[data-index='${index}']`)!;
  }

  function confirmButton(picker: IndexPicker): HTMLButtonElement {
    return picker.element.querySelector<HTMLButtonElement>("[data-focus='index-confirm']")!;
  }

  it('0〜上限-1 の番号を「今」「使っている（名前）」「空き」で並べ、今の番号は選べない', () => {
    const { picker } = mount();
    const states = texts(picker.element.querySelectorAll('.index-picker-state'));
    expect(states).toHaveLength(10);
    expect(states.slice(0, 4)).toEqual(['使っている（基本）', '今', '使っている（記号）', '空き']);
    expect(slot(picker, 1).disabled).toBe(true);
    expect(confirmButton(picker).disabled).toBe(true);
  });

  it('空きを選べば移動、使っている番号なら入れ替えと分かる文と決定ボタン', () => {
    const { picker, confirmed, back, closed } = mount();
    slot(picker, 5).click();
    expect(picker.element.querySelector('.index-picker-plan')?.textContent).toBe('レイヤー「数字」を番号 1 から 5 に移します。');
    expect(confirmButton(picker).textContent).toBe('移動する');
    expect(slot(picker, 5).getAttribute('aria-checked')).toBe('true');
    slot(picker, 2).click();
    expect(picker.element.querySelector('.index-picker-plan')?.textContent).toBe('レイヤー「数字」（番号 1）と「記号」（番号 2）の番号を入れ替えます。');
    expect(confirmButton(picker).textContent).toBe('入れ替える');
    expect(slot(picker, 5).getAttribute('aria-checked')).toBe('false');
    confirmButton(picker).click();
    expect(confirmed).toEqual([[2, 'swap']]);
    expect(picker.element.isConnected).toBe(false);
    expect(document.activeElement).toBe(back);
    expect(closed()).toBe(1);
  });

  it('注意は文字列か、選んだ番号と移動か入れ替えかに応じた関数で渡せる', () => {
    const { picker } = mount({
      note: (target, mode, other) => `MO(n) などの参照は書き換えないので、MO(${target}) で出るのは「${mode === 'swap' ? other : '数字'}」の中身になります`,
    });
    const note = picker.element.querySelector<HTMLElement>('.index-picker-note')!;
    expect(note.hidden).toBe(true);
    slot(picker, 0).click();
    expect(note.hidden).toBe(false);
    expect(note.textContent).toBe('MO(n) などの参照は書き換えないので、MO(0) で出るのは「基本」の中身になります');

    const macro = mount({ noun: 'マクロ', limit: 32, note: '番号の参照も書き換えます' }).picker;
    expect(macro.element.querySelectorAll('.index-picker-slot')).toHaveLength(32);
    macro.element.querySelector<HTMLButtonElement>("[data-index='31']")!.click();
    expect(macro.element.querySelector('.index-picker-note')?.textContent).toBe('番号の参照も書き換えます');
  });

  it('矢印で選べる番号を動いて選び（今の番号は飛ばす）、Escape と「やめる」で閉じる', () => {
    const { picker, confirmed, back, closed } = mount();
    picker.focus();
    expect((document.activeElement as HTMLElement).dataset.index).toBe('2');
    keydown(document.activeElement!, 'ArrowUp');
    expect(picker.selected).toBe(0);
    keydown(document.activeElement!, 'ArrowUp');
    expect(picker.selected).toBe(9);
    keydown(document.activeElement!, 'Home');
    keydown(document.activeElement!, 'ArrowRight');
    expect(picker.selected).toBe(2);
    keydown(document.activeElement!, 'Escape');
    expect(picker.element.isConnected).toBe(false);
    expect(document.activeElement).toBe(back);
    expect(confirmed).toEqual([]);
    expect(closed()).toBe(1);

    const again = mount().picker;
    again.element.querySelector<HTMLButtonElement>("[data-focus='index-cancel']")!.click();
    expect(again.element.isConnected).toBe(false);
  });
});

