// @vitest-environment happy-dom
// v0.5（issue #113）: レイヤーの「＋」（新しく作る・未使用から取り出す）と見出しの「…」（未使用にする / 名前を変える / 削除…）、
// 未保存の番号を当てたタブ・図・キー別の並び。W2（ADR 025）: タブの右クリックのメニューと、タブの並びの「…」の並び替え（◀▶・確定・やめる）
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { CORNIX } from '../../../src/keyboard/cornix';
import type { AnyChange, LayerSnapshot, ProfileSnapshot, Unused } from '../../../src/protocol';
import { App, BY_KEY_FEATURE, type ViewState } from '../../../src/webview/app';
import { hideTooltip } from '../../../src/webview/tooltip';
import { FakeHost, fixtureSnapshot } from './fakeHost';

const base = 'layers/0_base.yml';
const symbols = 'layers/1_symbols.yml';
const ipad = 'layers/ipad_base.yml';
const nav = 'layers/nav.yml';
const slotOf = (file: string, hand: string, group: string, symbol: string) => JSON.stringify([file, 'mapping', hand, group, symbol]);
const indexSet = (file: string, value: number): AnyChange => ({ address: { file, path: ['index'] }, value });
const indexRemove = (file: string): AnyChange => ({ op: 'remove', address: { file, path: ['index'] } });

let host: FakeHost;
let root: HTMLElement;
let app: App;
let state: ViewState | undefined;

/** ファイルを差し替えた（Address も差し替えた）レイヤーの写し */
function copyLayer(layer: LayerSnapshot, index: number, name: string, file: string): LayerSnapshot {
  const json = JSON.stringify(layer).split(JSON.stringify(layer.file)).join(JSON.stringify(file));
  return { ...(JSON.parse(json) as LayerSnapshot), index, name };
}

function unusedLayer(layer: LayerSnapshot, name: string, file: string): Unused<LayerSnapshot> {
  return { ...copyLayer(layer, 0, name, file), index: null };
}

/** 未使用のレイヤーが 2 つあるプロファイル（iPad Base には警告が 1 件） */
function withUnused(overrides: Partial<ProfileSnapshot> = {}): ProfileSnapshot {
  const snapshot = fixtureSnapshot();
  return {
    ...snapshot,
    unused: { layers: [unusedLayer(snapshot.layers[0]!, 'iPad Base', ipad), unusedLayer(snapshot.layers[1]!, 'Nav', nav)], macros: [], tapDances: [], combos: [] },
    diagnostics: [{ severity: 'warning', source: 'structure', message: 'index: がありません', file: ipad }],
    ...overrides,
  };
}

function tabs(): string[] {
  return [...root.querySelectorAll<HTMLElement>('.layer-tabs .layer-tab[data-layer]')].map((tab) => tab.textContent ?? '');
}

function addButton(): HTMLButtonElement {
  return root.querySelector<HTMLButtonElement>('.layer-tabs [data-layer-add]')!;
}

function openMore(): void {
  root.querySelector<HTMLButtonElement>('.layer-info .more-menu-button')!.click();
}

function moreAction(id: string): void {
  openMore();
  root.querySelector<HTMLButtonElement>(`.layer-info .more-menu-item[data-action='${id}']`)!.click();
}

function receive(snapshot: ProfileSnapshot, pending: AnyChange[] = []): void {
  app.receive({ type: 'snapshot', snapshot, changes: [], pending });
}

beforeEach(() => {
  host = new FakeHost();
  root = document.createElement('div');
  document.body.replaceChildren(root);
  state = undefined;
  app = new App(root, { keyboard: CORNIX, host, state: { get: () => state, set: (s) => (state = s) } });
});

afterEach(() => {
  hideTooltip();
  document.body.replaceChildren();
});

describe('「＋」の一覧と未使用のレイヤー', () => {
  it('未使用のレイヤーはタブに並べず、「＋」に数を出し、一覧の「未使用（N）」に名前・ファイル・警告の数を出す', () => {
    receive(withUnused());
    expect(tabs()).toEqual(['0 Base', '1 Symbols']);
    expect(addButton().querySelector('.add-menu-badge')?.textContent).toBe('2');
    addButton().click();
    expect(root.querySelector('.layer-tabs .add-menu-create')?.textContent).toBe('新しいレイヤー番号 2 に作る');
    expect(root.querySelector('.layer-tabs .add-menu-unused .add-menu-heading')?.textContent).toBe('未使用（2）');
    const rows = [...root.querySelectorAll<HTMLButtonElement>('.layer-tabs .add-menu-unused-item')];
    expect(rows.map((row) => row.textContent)).toEqual([`iPad Base${ipad}⚠ 1`, `Nav${nav}`]);
    expect(rows.every((row) => !row.disabled)).toBe(true);
  });

  it('未使用を選ぶと use をホストに渡し、未保存の変更が届いて並びに現れたら選ぶ（未保存の印付き）', () => {
    const snapshot = withUnused();
    receive(snapshot);
    addButton().click();
    root.querySelector<HTMLButtonElement>(`.layer-tabs [data-unused='${nav}']`)!.click();
    expect(host.itemEdits).toEqual([{ op: 'use', kind: 'layer', file: nav }]);
    // まだ届いていない
    expect(app.currentLayer).toBe(0);

    receive(snapshot, [indexSet(nav, 2)]);
    expect(tabs()).toEqual(['0 Base', '1 Symbols', '2 Nav●']);
    expect(app.currentLayer).toBe(2);
    const tab = root.querySelector<HTMLElement>('.layer-tab.selected')!;
    expect(tab.classList.contains('layer-tab-changed')).toBe(true);
    expect(tab.title).toContain('未使用から取り出しました（未保存）');
    expect(root.querySelector('.layer-info h2 .layer-heading-title')?.textContent).toBe('レイヤー 2 Nav');
    // 図と下の欄は取り出したレイヤーの中身（Address はそのファイル）
    expect(root.querySelector(`.board [data-slot='${CSS.escape(slotOf(nav, 'left_hand', 'row0', 'Q'))}']`)).not.toBeNull();
    expect(root.querySelector(`.layer-editor .field[data-slot='${CSS.escape(slotOf(nav, 'left_hand', 'row0', 'Q'))}']`)).not.toBeNull();
    expect(addButton().querySelector('.add-menu-badge')?.textContent).toBe('1');
  });

  it('番号が 10 個とも使われていれば未使用の行は選べず、理由を出す', () => {
    const snapshot = withUnused();
    const layers = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9].map((index) => copyLayer(snapshot.layers[0]!, index, `L${index}`, `layers/${index}_l.yml`));
    receive({ ...snapshot, layers });
    addButton().click();
    expect(root.querySelector('.layer-tabs .add-menu-unused .add-menu-reason')?.textContent).toBe(
      '番号が 10 個とも使われています。使っているレイヤーのどれかを「未使用にする」と、ここから選べます。',
    );
    expect([...root.querySelectorAll<HTMLButtonElement>('.layer-tabs .add-menu-unused-item')].every((row) => row.disabled)).toBe(true);
    expect(root.querySelector<HTMLButtonElement>('.layer-tabs .add-menu-create')!.disabled).toBe(true);
  });

  it('レイヤーの数は KeyboardSpec の limits から取る（Cornix 以外の上限）', () => {
    app = new App(root, { keyboard: { ...CORNIX, limits: { ...CORNIX.limits, layers: 2 } }, host });
    receive(withUnused());
    addButton().click();
    expect(root.querySelector('.layer-tabs .add-menu-unused .add-menu-reason')?.textContent).toBe(
      '番号が 2 個とも使われています。使っているレイヤーのどれかを「未使用にする」と、ここから選べます。',
    );
    expect(root.querySelector('.layer-tabs .add-menu-group .add-menu-reason')?.textContent).toBe('空いている番号（0〜1）がありません');
  });

  it('番号が埋まっていても、未保存で未使用にしたレイヤーがあれば空いた番号で選べる', () => {
    const snapshot = withUnused();
    const layers = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9].map((index) => copyLayer(snapshot.layers[0]!, index, `L${index}`, `layers/${index}_l.yml`));
    receive({ ...snapshot, layers }, [indexRemove('layers/4_l.yml')]);
    expect(tabs()).not.toContain('4 L4');
    addButton().click();
    expect(root.querySelector('.layer-tabs .add-menu-unused .add-menu-reason')).toBeNull();
    expect(root.querySelector('.layer-tabs .add-menu-create')?.textContent).toBe('新しいレイヤー番号 4 に作る');
    expect(root.querySelector('.layer-tabs .add-menu-unused .add-menu-heading')?.textContent).toBe('未使用（3）');
  });
});

describe('未保存の番号を当てた並び', () => {
  it('入れ替えた番号の順にタブを並べ、選んでいるレイヤーはファイルを追う。MO(n) の名前も今の番号で引く', () => {
    const snapshot = fixtureSnapshot();
    receive(snapshot);
    app.selectLayer(1);
    receive(snapshot, [indexSet(symbols, 0), indexSet(base, 1)]);
    expect(tabs()).toEqual(['0 Symbols●', '1 Base●']);
    expect(app.currentLayer).toBe(0);
    expect(root.querySelector('.layer-tab.selected')?.textContent).toBe('0 Symbols●');
    expect(root.querySelector('.layer-tab.selected')?.getAttribute('title')).toContain('番号を 1 から変えています（未保存）');

    // Base は 1 になった: Base の MO(1) で出るのは Base 自身
    app.selectLayer(1);
    const mo1 = root.querySelector<HTMLElement>(`.board [data-slot='${CSS.escape(slotOf(base, 'right_hand', 'thumb_keys', 'middle'))}']`)!;
    expect(mo1.getAttribute('aria-label')).toContain('MO(1)（Base）');

    // 元に戻す（未保存の変更がなくなる）と保存済みの番号に戻る
    receive(snapshot, []);
    expect(tabs()).toEqual(['0 Base', '1 Symbols']);
    expect(app.currentLayer).toBe(0);
  });

  it('キー別の行も未保存の番号の順に並べる', () => {
    const snapshot = withUnused();
    receive(snapshot, [indexSet(nav, 2), indexSet(symbols, 3)]);
    app.receive({ type: 'features', unlocked: [BY_KEY_FEATURE] });
    app.setMode('key');
    const block = root.querySelector<HTMLElement>(`.layer-editor .field[data-slot='${CSS.escape(slotOf(base, 'left_hand', 'row0', 'Q'))}']`)!.closest('.position-block')!;
    expect([...block.querySelectorAll('.layer-row-title, .layer-row-label')].map((e) => e.textContent)).toEqual(['0 Base', '2 Nav', '3 Symbols']);
  });

  it('未保存で未使用にしたレイヤーはタブから消え、選んでいれば最初のレイヤーに移る', () => {
    const snapshot = fixtureSnapshot();
    receive(snapshot);
    app.selectLayer(1);
    receive(snapshot, [indexRemove(symbols)]);
    expect(tabs()).toEqual(['0 Base']);
    expect(app.currentLayer).toBe(0);
    expect(addButton().querySelector('.add-menu-badge')?.textContent).toBe('1');
  });
});

describe('見出しの「…」', () => {
  it('未使用にする / 名前を変える / 区切り / 削除… を出す（番号を変える… はない）', () => {
    receive(fixtureSnapshot());
    app.selectLayer(1);
    openMore();
    const list = root.querySelector<HTMLElement>('.layer-info .more-menu-list')!;
    expect([...list.children].map((e) => (e.getAttribute('role') === 'separator' ? '---' : e.textContent))).toEqual([
      '未使用にする',
      '名前を変える',
      '---',
      '削除…',
    ]);
  });

  it('未使用にする: unuse をファイルで渡す', () => {
    receive(fixtureSnapshot());
    app.selectLayer(1);
    moreAction('unuse');
    expect(host.itemEdits).toEqual([{ op: 'unuse', kind: 'layer', file: symbols }]);
  });

  it('名前を変える: 見出しの下の欄で名前を変え、rename をファイル付きで渡す（同じ名前なら渡さない）', () => {
    receive(fixtureSnapshot());
    app.selectLayer(1);
    moreAction('rename');
    const input = root.querySelector<HTMLInputElement>('.layer-rename-form .item-name-input')!;
    expect(input.value).toBe('Symbols');
    input.value = ' ';
    root.querySelector<HTMLButtonElement>('.layer-rename-form .primary')!.click();
    expect(root.querySelector('.layer-rename-form .message-line')).not.toBeNull();
    input.value = 'Symbols';
    input.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', cancelable: true }));
    expect(host.itemEdits).toEqual([]);
    expect(root.querySelector('.layer-rename-form')).toBeNull();
    moreAction('rename');
    const again = root.querySelector<HTMLInputElement>('.layer-rename-form .item-name-input')!;
    again.value = 'Sym';
    again.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', cancelable: true }));
    expect(host.itemEdits).toEqual([{ op: 'rename', kind: 'layer', name: 'Symbols', to: 'Sym', file: symbols }]);
  });

  it('ほかのレイヤーに移ると、開いていた名前の変更の欄を閉じる', () => {
    receive(fixtureSnapshot());
    app.selectLayer(1);
    moreAction('rename');
    expect(root.querySelector('.layer-rename-form')).not.toBeNull();
    app.selectLayer(0);
    expect(root.querySelector('.layer-rename-form')).toBeNull();
  });
});

describe('タブの右クリック（W2・ADR 025）', () => {
  function tab(file: string): HTMLButtonElement {
    return root.querySelector<HTMLButtonElement>(`.layer-tabs button.layer-tab[data-file='${file}']`)!;
  }

  function rightClick(target: HTMLElement, x = 30, y = 40): MouseEvent {
    const event = new MouseEvent('contextmenu', { bubbles: true, cancelable: true, clientX: x, clientY: y });
    target.dispatchEvent(event);
    return event;
  }

  function tabMenuList(): HTMLElement {
    return root.querySelector<HTMLElement>('.layer-tab-menu .more-menu-list')!;
  }

  it('そのレイヤーを選んで、見出しの「…」と同じ操作を押した位置に出す（既定のメニューは出さない）', () => {
    receive(fixtureSnapshot());
    expect(app.currentLayer).toBe(0);
    const event = rightClick(tab(symbols), 30, 40);
    expect(event.defaultPrevented).toBe(true);
    expect(app.currentLayer).toBe(1);
    const list = tabMenuList();
    expect(list.hidden).toBe(false);
    expect(list.style.left).toBe('30px');
    expect(list.style.top).toBe('40px');
    expect([...list.children].map((e) => (e.getAttribute('role') === 'separator' ? '---' : e.textContent))).toEqual(['未使用にする', '名前を変える', '---', '削除…']);
    // メニューのボタンは出さない
    expect(root.querySelector<HTMLElement>('.layer-tab-menu .more-menu-button')!.hidden).toBe(true);
    list.querySelector<HTMLButtonElement>("[data-action='unuse']")!.click();
    expect(host.itemEdits).toEqual([{ op: 'unuse', kind: 'layer', file: symbols }]);
    // 閉じたらそのタブにフォーカスを戻す
    expect(document.activeElement).toBe(tab(symbols));
  });

  it('キー別でも使え、名前を変える の欄を閉じたらタブにフォーカスを戻す', () => {
    receive(fixtureSnapshot());
    app.receive({ type: 'features', unlocked: [BY_KEY_FEATURE] });
    app.setMode('key');
    rightClick(tab(symbols));
    tabMenuList().querySelector<HTMLButtonElement>("[data-action='rename']")!.click();
    const input = root.querySelector<HTMLInputElement>('.layer-rename-form .item-name-input')!;
    expect(input.value).toBe('Symbols');
    input.value = 'Sym';
    input.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', cancelable: true }));
    expect(host.itemEdits).toEqual([{ op: 'rename', kind: 'layer', name: 'Symbols', to: 'Sym', file: symbols }]);
    expect(document.activeElement).toBe(tab(symbols));
  });
});

describe('タブの並びの「並び替え」と並び替えモード（W2・ADR 025。空きの枠も並べる）', () => {
  const three = (): ProfileSnapshot => {
    const snapshot = fixtureSnapshot();
    return { ...snapshot, layers: [...snapshot.layers, copyLayer(snapshot.layers[1]!, 4, 'Nav', nav)] };
  };

  function reorderButton(): HTMLButtonElement {
    return root.querySelector<HTMLButtonElement>(".layer-tabs [data-focus='layers-reorder']")!;
  }

  function startReorder(): void {
    reorderButton().click();
  }

  function slots(): string[] {
    return [...root.querySelectorAll('.layer-tabs .layer-slot-label')].map((e) => e.textContent ?? '');
  }

  function move(file: string, direction: 'left' | 'right'): void {
    root.querySelector<HTMLButtonElement>(`.layer-slot[data-file='${file}'] .reorder-${direction}`)!.click();
  }

  it('「＋」の隣に「並び替え」のボタン（使っているレイヤーが 1 つなら押せない）', () => {
    receive(fixtureSnapshot());
    const add = root.querySelector('.layer-tabs .layer-add-menu')!;
    expect(add.nextElementSibling).toBe(reorderButton());
    expect(reorderButton().disabled).toBe(false);
    receive(fixtureSnapshot(), [indexRemove(symbols)]);
    expect(reorderButton().disabled).toBe(true);
    reorderButton().click();
    expect(app.reorderingLayers).toBe(false);
  });

  it('並び替えモード: 0〜9 の枠を全部並べ（空きは点線）、名前の下に ◀▶（0 の ◀・9 の ▶ は押せない）。「＋」と「並び替え」は隠す', () => {
    receive(three());
    startReorder();
    expect(app.reorderingLayers).toBe(true);
    expect(slots()).toEqual(['0 Base', '1 Symbols', '2 空き', '3 空き', '4 Nav', '5 空き', '6 空き', '7 空き', '8 空き', '9 空き']);
    expect(root.querySelectorAll('.layer-slot.empty')).toHaveLength(7);
    expect([...root.querySelectorAll<HTMLButtonElement>('.reorder-left')].map((b) => b.disabled)).toEqual([true, false, false]);
    expect([...root.querySelectorAll<HTMLButtonElement>('.reorder-right')].map((b) => b.disabled)).toEqual([false, false, false]);
    expect(root.querySelector<HTMLElement>('.layer-reorder-bar')!.hidden).toBe(false);
    expect(root.querySelector<HTMLElement>('.layer-tabs .layer-add-menu')!.hidden).toBe(true);
    expect(reorderButton().hidden).toBe(true);
    expect(root.querySelector('button.layer-tab[data-file]')).toBeNull();
  });

  it('◀▶ は隣の枠へ（空きなら移し、使っていれば入れ替え）。確定で番号付きの reorder を 1 回送る', () => {
    receive(three());
    startReorder();
    move(nav, 'right');
    move(nav, 'right');
    expect(slots()).toEqual(['0 Base', '1 Symbols', '2 空き', '3 空き', '4 空き', '5 空き', '6 Nav', '7 空き', '8 空き', '9 空き']);
    expect((document.activeElement as HTMLElement).dataset.file).toBe(nav);
    move(base, 'right');
    expect(slots().slice(0, 2)).toEqual(['0 Symbols', '1 Base']);
    expect(host.itemEdits).toEqual([]);
    root.querySelector<HTMLButtonElement>("[data-focus='layer-reorder-confirm']")!.click();
    expect(host.itemEdits).toEqual([{ op: 'reorder', kind: 'layer', files: [base, symbols, nav], indexes: [1, 0, 6] }]);
    expect(app.reorderingLayers).toBe(false);
    expect(document.activeElement).toBe(reorderButton());
  });

  it('番号が今と同じなら送らない。やめる・Escape は捨てる', () => {
    receive(three());
    startReorder();
    move(nav, 'right');
    move(nav, 'left');
    root.querySelector<HTMLButtonElement>("[data-focus='layer-reorder-confirm']")!.click();
    expect(host.itemEdits).toEqual([]);
    startReorder();
    move(base, 'right');
    root.querySelector<HTMLButtonElement>("[data-focus='layer-reorder-cancel']")!.click();
    expect(tabs()).toEqual(['0 Base', '1 Symbols', '4 Nav']);
    startReorder();
    move(base, 'right');
    document.activeElement!.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true, cancelable: true }));
    expect(app.reorderingLayers).toBe(false);
    expect(tabs()).toEqual(['0 Base', '1 Symbols', '4 Nav']);
    expect(host.itemEdits).toEqual([]);
  });
});

