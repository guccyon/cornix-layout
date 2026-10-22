// @vitest-environment happy-dom
// v0.5（issue #114）: マクロ・タップダンス・コンボ・ショートカットの節の「追加」（追加の一覧）と見出しの「…」、
// 未保存の変更を当てた番号の並び、未使用の項目の取り出し、未保存のショートカットの追加
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import type { AnyChange, ComboSnapshot, MacroSnapshot, ProfileSnapshot, Unused } from '../../../src/protocol';
import { ComboEditor } from '../../../src/webview/comboEditor';
import { UNUSED_BLOCKED_REASON } from '../../../src/webview/itemList';
import { MacroEditor } from '../../../src/webview/macroEditor';
import { ShortcutEditor } from '../../../src/webview/shortcutEditor';
import { TapDanceEditor } from '../../../src/webview/tapDanceEditor';
import { hideTooltip } from '../../../src/webview/tooltip';
import { FakeHost, fixtureSnapshot, settle } from './fakeHost';
import { at, COMBO, COMBO_FILE, MACRO, MACRO_FILE, PRESET_FILE, PRESET_MACRO, SHORTCUTS, SHORTCUTS_FILE, TAP_DANCE } from './itemFixtures';

let host: FakeHost;

const OLD_FILE = 'macros/old_paste.yml';

/** 項目を別のファイルに写す（Address のファイルも書き換える） */
function moved<T>(item: T, from: string, to: string): T {
  return JSON.parse(JSON.stringify(item).split(JSON.stringify(from)).join(JSON.stringify(to))) as T;
}

const OLD_MACRO: Unused<MacroSnapshot> = { ...moved(MACRO, MACRO_FILE, OLD_FILE), name: 'Old Paste', description: '古い貼り付け', index: null };

function snapshot(overrides: Partial<ProfileSnapshot> = {}): ProfileSnapshot {
  return fixtureSnapshot({
    macros: [MACRO, PRESET_MACRO],
    tapDances: [TAP_DANCE],
    combos: [COMBO],
    shortcuts: SHORTCUTS,
    unused: { layers: [], macros: [OLD_MACRO], tapDances: [], combos: [] },
    ...overrides,
  });
}

function mount<T extends { element: HTMLElement }>(section: T): T {
  document.body.append(section.element);
  return section;
}

function byFocus<T extends HTMLElement>(root: HTMLElement, focus: string): T {
  const element = root.querySelector<T>(`[data-focus='${focus}']`);
  if (!element) throw new Error(`${focus} がない`);
  return element;
}

function rows(root: HTMLElement): string[] {
  return [...root.querySelectorAll<HTMLElement>('.item-row')].map((r) => `${r.querySelector('.item-index')?.textContent ?? '-'} ${r.dataset.item}`);
}

async function openAdd(root: HTMLElement): Promise<HTMLElement> {
  byFocus<HTMLButtonElement>(root, 'add-menu').click();
  await settle(0);
  return root.querySelector<HTMLElement>('.add-menu-panel')!;
}

function openMore(root: HTMLElement): HTMLElement[] {
  byFocus<HTMLButtonElement>(root, 'more-menu').click();
  return [...root.querySelectorAll<HTMLElement>('.more-menu-list > *')];
}

function menuLabels(root: HTMLElement): string[] {
  return openMore(root).map((e) => (e.classList.contains('more-menu-separator') ? '---' : (e.querySelector('.more-menu-label')?.textContent ?? '')));
}

function choose(root: HTMLElement, action: string): void {
  if (!root.querySelector('.more-menu-list:not([hidden])')) openMore(root);
  root.querySelector<HTMLButtonElement>(`.more-menu-item[data-action='${action}']`)!.click();
}

beforeEach(() => {
  host = new FakeHost();
  document.body.replaceChildren();
});

afterEach(() => {
  hideTooltip();
  document.body.replaceChildren();
});

describe('一覧の並びと番号', () => {
  it('使っている項目だけを、未保存の変更を当てた番号の順に並べる（見出しの番号も描き直す）', () => {
    const macros = mount(new MacroEditor({ host }));
    macros.update(snapshot(), []);
    expect(rows(macros.element)).toEqual(['0 Bracket Pair', '2 Copy Selected']);
    expect(macros.element.querySelector('.item-count')?.textContent).toBe('2 件');
    const pending: AnyChange[] = [{ address: at(MACRO_FILE, 'index'), value: 5 }];
    macros.update(snapshot(), [], pending);
    expect(rows(macros.element)).toEqual(['2 Copy Selected', '5 Bracket Pair']);
    expect(macros.selected).toBe('Bracket Pair');
    expect(macros.element.querySelector('.item-header .item-index')?.textContent).toBe('5');
    // 番号を変えた項目の行には変えた印
    expect(macros.element.querySelector("[data-item='Bracket Pair']")?.classList.contains('changed')).toBe(true);
  });

  it('未保存の変更で未使用にした項目は並べず、取り出した項目は並べて編集できる', () => {
    const macros = mount(new MacroEditor({ host }));
    const pending: AnyChange[] = [
      { op: 'remove', address: at(PRESET_FILE, 'index') },
      { address: at(OLD_FILE, 'index'), value: 3 },
    ];
    macros.update(snapshot(), [], pending);
    expect(rows(macros.element)).toEqual(['0 Bracket Pair', '3 Old Paste']);
    macros.select('Old Paste');
    expect(byFocus<HTMLInputElement>(macros.element, 'description').value).toBe('古い貼り付け');
    const field = byFocus<HTMLInputElement>(macros.element, 'step:0:key:0');
    field.value = 'Z';
    field.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true, cancelable: true }));
    expect(host.changes).toEqual([{ address: at(OLD_FILE, 'sequence', 0, 'keys', 0), value: 'Z' }]);
  });
});

describe('節の「追加」', () => {
  it('「＋ 新しいマクロ」・未使用（N）・同梱から（マクロの preset）を並べ、ボタンに未使用の数を出す', async () => {
    const macros = mount(new MacroEditor({ host }));
    macros.update(snapshot(), []);
    expect(macros.element.querySelector('.add-menu-badge')?.textContent).toBe('1');
    const panel = await openAdd(macros.element);
    expect(panel.querySelector('.add-menu-create')?.textContent).toBe('＋ 新しいマクロ');
    expect(panel.querySelector('.add-menu-unused .add-menu-heading')?.textContent).toBe('未使用（1）');
    const unused = panel.querySelector<HTMLElement>(`[data-unused='${OLD_FILE}']`)!;
    expect(unused.textContent).toContain('Old Paste');
    expect(unused.textContent).toContain(OLD_FILE);
    // 同梱からは手順の定義（macro: true）だけ
    expect([...panel.querySelectorAll('.add-menu-bundled .preset-item')].map((e) => e.textContent)).toEqual(['キーボードショートカット']);
  });

  it('未使用の行を選ぶと use を渡し、未保存の変更で一覧に現れたらその項目を選ぶ', async () => {
    const macros = mount(new MacroEditor({ host }));
    macros.update(snapshot(), []);
    const panel = await openAdd(macros.element);
    panel.querySelector<HTMLButtonElement>(`[data-unused='${OLD_FILE}']`)!.click();
    expect(host.itemEdits).toEqual([{ op: 'use', kind: 'macro', file: OLD_FILE }]);
    expect(macros.selected).toBe('Bracket Pair');
    macros.update(snapshot(), [], [{ address: at(OLD_FILE, 'index'), value: 3 }]);
    expect(macros.selected).toBe('Old Paste');
    // 取り出した項目は追加の一覧の未使用から消える
    expect(macros.element.querySelector<HTMLElement>('.add-menu-badge')?.hidden).toBe(true);
  });

  it('番号が埋まっていれば「新しく作る」と未使用の行は選べず、理由を出す', async () => {
    const many: MacroSnapshot[] = Array.from({ length: 32 }, (_, i) => ({ ...moved(MACRO, MACRO_FILE, `macros/${i}.yml`), name: `M${i}`, index: i }));
    const macros = mount(new MacroEditor({ host }));
    macros.update(snapshot({ macros: many }), []);
    const panel = await openAdd(macros.element);
    expect(panel.querySelector<HTMLButtonElement>('.add-menu-create')?.disabled).toBe(true);
    expect(panel.querySelector<HTMLButtonElement>(`[data-unused='${OLD_FILE}']`)?.disabled).toBe(true);
    expect(panel.querySelector('.add-menu-unused .add-menu-reason')?.textContent).toBe(UNUSED_BLOCKED_REASON);
  });

  it('「＋ 新しい〇〇」は検索の文字を名前に入れて名前の欄を開く', async () => {
    const tapDances = mount(new TapDanceEditor({ host }));
    tapDances.update(snapshot(), []);
    const panel = await openAdd(tapDances.element);
    // タップダンスには同梱からも未使用もない
    expect(panel.querySelector('.add-menu-bundled')).toBeNull();
    expect(panel.querySelector('.add-menu-unused')).toBeNull();
    const search = panel.querySelector<HTMLInputElement>('.add-menu-search')!;
    search.value = 'Space Fn';
    search.dispatchEvent(new Event('input'));
    panel.querySelector<HTMLButtonElement>('.add-menu-create')!.click();
    expect(tapDances.formOpen).toBe(true);
    expect(byFocus<HTMLInputElement>(tapDances.element, 'form-name').value).toBe('Space Fn');
  });

  it('マクロの同梱からは preset: のマクロを作る。同じ名前があれば名前の欄を開き、preset を付けて送る', async () => {
    const macros = mount(new MacroEditor({ host }));
    macros.update(snapshot(), []);
    let panel = await openAdd(macros.element);
    panel.querySelector<HTMLButtonElement>('.add-menu-bundled .preset-item')!.click();
    expect(host.itemEdits).toEqual([{ op: 'create', kind: 'macro', name: 'キーボードショートカット', preset: 'VS Code:基本操作:キーボードショートカット' }]);
    host.itemEdits.length = 0;
    // 未使用の項目の名前とも重ねない
    const taken = { ...OLD_MACRO, name: 'キーボードショートカット' };
    macros.update(snapshot({ unused: { layers: [], macros: [taken], tapDances: [], combos: [] } }), []);
    panel = await openAdd(macros.element);
    panel.querySelector<HTMLButtonElement>('.add-menu-bundled .preset-item')!.click();
    expect(host.itemEdits).toEqual([]);
    expect(macros.element.querySelector('.item-name-form')?.textContent).toContain('マクロ「キーボードショートカット」はすでにあります');
    const name = byFocus<HTMLInputElement>(macros.element, 'form-name');
    name.value = 'ショートカット一覧';
    name.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', cancelable: true }));
    expect(host.itemEdits).toEqual([{ op: 'create', kind: 'macro', name: 'ショートカット一覧', preset: 'VS Code:基本操作:キーボードショートカット' }]);
  });
});

describe('見出しの「…」', () => {
  it('状態に合う操作だけを出す（ショートカットには番号も未使用もない）', () => {
    const macros = mount(new MacroEditor({ host }));
    macros.update(snapshot(), []);
    expect(menuLabels(macros.element)).toEqual(['名前を変える', '番号を変える…', '未使用にする', 'ファイルを開く', '---', '削除…']);
    const shortcuts = mount(new ShortcutEditor({ host }));
    shortcuts.update(snapshot(), []);
    expect(menuLabels(shortcuts.element)).toEqual(['名前を変える', 'ファイルを開く', '---', '削除…']);
    // 名前を変える・削除のボタンとファイルのリンクは見出しに置かない
    expect(macros.element.querySelector("[data-focus='rename'], [data-focus='delete'], [data-focus='open']")).toBeNull();
  });

  it('未使用にする・ファイルを開く・削除…', () => {
    const macros = mount(new MacroEditor({ host }));
    macros.update(snapshot(), []);
    choose(macros.element, 'unuse');
    choose(macros.element, 'open');
    choose(macros.element, 'delete');
    expect(host.itemEdits).toEqual([
      { op: 'unuse', kind: 'macro', file: MACRO_FILE },
      { op: 'delete', kind: 'macro', name: 'Bracket Pair' },
    ]);
    expect(host.opened).toEqual([{ file: MACRO_FILE }]);
    // 未使用にしたものが未保存の変更で届けば一覧から外れる
    macros.update(snapshot(), [], [{ op: 'remove', address: at(MACRO_FILE, 'index') }]);
    expect(rows(macros.element)).toEqual(['2 Copy Selected']);
    expect(macros.selected).toBe('Copy Selected');
  });

  it('番号を変える…: 番号の選択（今・使っている・空き）で入れ替えると setIndex を渡す。マクロは参照の書き換えを書き添える', () => {
    const macros = mount(new MacroEditor({ host }));
    macros.update(snapshot(), []);
    choose(macros.element, 'setIndex');
    expect(macros.indexPickerOpen).toBe(true);
    const slots = [...macros.element.querySelectorAll<HTMLButtonElement>('.index-picker-slot')];
    expect(slots).toHaveLength(32);
    expect(slots[0]?.textContent).toBe('0今');
    expect(slots[2]?.textContent).toBe('2使っている（Copy Selected）');
    slots[2]!.click();
    expect(macros.element.querySelector('.index-picker-note')?.textContent).toBe('番号の参照（Macro(3) / M3 など）も新しい番号に書き換えます');
    const confirm = macros.element.querySelector<HTMLButtonElement>("[data-focus='index-confirm']")!;
    expect(confirm.textContent).toBe('入れ替える');
    confirm.click();
    expect(host.itemEdits).toEqual([{ op: 'setIndex', kind: 'macro', file: MACRO_FILE, index: 2 }]);
    expect(macros.indexPickerOpen).toBe(false);
    expect(document.activeElement).toBe(byFocus(macros.element, 'more-menu'));
  });

  it('コンボの番号の選択には書き添えがない', () => {
    const other: ComboSnapshot = { ...moved(COMBO, COMBO_FILE, 'combos/01_x.yml'), name: 'X', index: 1 };
    const combos = mount(new ComboEditor({ host }));
    combos.update(snapshot({ combos: [COMBO, other] }), []);
    choose(combos.element, 'setIndex');
    [...combos.element.querySelectorAll<HTMLButtonElement>('.index-picker-slot')][7]!.click();
    expect(combos.element.querySelector<HTMLElement>('.index-picker-note')?.hidden).toBe(true);
    combos.element.querySelector<HTMLButtonElement>("[data-focus='index-confirm']")!.click();
    expect(host.itemEdits).toEqual([{ op: 'setIndex', kind: 'combo', file: COMBO_FILE, index: 7 }]);
  });
});

describe('ショートカットの未保存の追加', () => {
  it('未保存で足したショートカットも一覧に出し、値を直せる', () => {
    const shortcuts = mount(new ShortcutEditor({ host }));
    const pending: AnyChange[] = [{ address: at(SHORTCUTS_FILE, 'shortcuts', '保存'), value: 'Command + S' }];
    shortcuts.update(snapshot(), [], pending);
    expect(rows(shortcuts.element)).toEqual(['- 前のタブへ', '- 次のタブへ', '- 保存']);
    expect(shortcuts.element.querySelector("[data-item='保存']")?.classList.contains('changed')).toBe(true);
    shortcuts.select('保存');
    const value = byFocus<HTMLInputElement>(shortcuts.element, 'value');
    expect(value.value).toBe('Command + S');
    value.value = 'Command + Shift + S';
    value.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true, cancelable: true }));
    expect(host.changes).toEqual([{ address: at(SHORTCUTS_FILE, 'shortcuts', '保存'), value: 'Command + Shift + S' }]);
  });

  it('同梱からコピーしたものは、未保存の変更で一覧に現れたら選ぶ。未保存で足した名前とは重ねない', async () => {
    const shortcuts = mount(new ShortcutEditor({ host }));
    shortcuts.update(snapshot(), []);
    const panel = await openAdd(shortcuts.element);
    // ショートカットには未使用のまとまりを出さない
    expect(panel.querySelector('.add-menu-unused')).toBeNull();
    panel.querySelector<HTMLButtonElement>('.add-menu-bundled .preset-item')!.click();
    expect(host.itemEdits).toEqual([{ op: 'create', kind: 'shortcut', name: 'コマンドパレット', value: 'Shift + Command + P' }]);
    shortcuts.update(snapshot(), [], [{ address: at(SHORTCUTS_FILE, 'shortcuts', 'コマンドパレット'), value: 'Shift + Command + P' }]);
    expect(shortcuts.selected).toBe('コマンドパレット');
    // もう一度選ぶと、同じ名前があるので名前の欄を開く
    (await openAdd(shortcuts.element)).querySelector<HTMLButtonElement>('.add-menu-bundled .preset-item')!.click();
    expect(host.itemEdits).toHaveLength(1);
    expect(shortcuts.formOpen).toBe(true);
  });
});
