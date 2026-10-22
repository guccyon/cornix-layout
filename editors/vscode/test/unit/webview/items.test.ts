// @vitest-environment happy-dom
// マクロ・タップダンス・コンボ・ショートカットの節（一覧と編集欄、並びの操作、項目の操作、検証の表示）
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import type { AnyChange, Change, Diagnostic, ProfileSnapshot } from '../../../src/protocol';
import { App } from '../../../src/webview/app';
import { ComboEditor } from '../../../src/webview/comboEditor';
import { MacroEditor } from '../../../src/webview/macroEditor';
import { ShortcutEditor } from '../../../src/webview/shortcutEditor';
import { TapDanceEditor } from '../../../src/webview/tapDanceEditor';
import { hideTooltip } from '../../../src/webview/tooltip';
import { FakeHost, fixtureSnapshot, settle } from './fakeHost';
import { at, COMBO, COMBO_FILE, MACRO, MACRO_FILE, PRESET_FILE, PRESET_MACRO, SHORTCUTS, SHORTCUTS_FILE, TAP_DANCE, TAP_DANCE_FILE } from './itemFixtures';

let host: FakeHost;

function snapshot(overrides: Partial<ProfileSnapshot> = {}): ProfileSnapshot {
  return fixtureSnapshot({ macros: [MACRO, PRESET_MACRO], tapDances: [TAP_DANCE], combos: [COMBO], shortcuts: SHORTCUTS, ...overrides });
}

function mount<T extends { element: HTMLElement }>(section: T): T {
  document.body.append(section.element);
  return section;
}

function input(root: HTMLElement, focus: string): HTMLInputElement {
  const element = root.querySelector<HTMLElement>(`[data-focus='${focus}']`);
  if (!(element instanceof HTMLInputElement)) throw new Error(`${focus} の入力欄がない`);
  return element;
}

function button(root: HTMLElement, focus: string): HTMLButtonElement {
  const element = root.querySelector<HTMLElement>(`[data-focus='${focus}']`);
  if (!(element instanceof HTMLButtonElement)) throw new Error(`${focus} のボタンがない`);
  return element;
}

/** キー入力欄に打って Enter で決める */
function commitKey(root: HTMLElement, focus: string, text: string): void {
  const field = input(root, focus);
  field.value = text;
  field.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true, cancelable: true }));
}

/** 数値・文字の欄に打って change */
function commitValue(root: HTMLElement, focus: string, text: string): void {
  const field = input(root, focus);
  field.value = text;
  field.dispatchEvent(new Event('input'));
  field.dispatchEvent(new Event('change'));
}

function stepActions(root: HTMLElement): string[] {
  return [...root.querySelectorAll('.macro-step .step-action')].map((e) => e.textContent ?? '');
}

beforeEach(() => {
  host = new FakeHost();
  document.body.replaceChildren();
});

afterEach(() => {
  hideTooltip();
  document.body.replaceChildren();
});

describe('節の出し方', () => {
  it('v0.1 のサーバー（snapshot に macros などがない）と読めないプロファイルでは出さない。0 件なら「追加」だけの節を出す', () => {
    const sections = [new MacroEditor({ host }), new TapDanceEditor({ host }), new ComboEditor({ host }), new ShortcutEditor({ host })];
    for (const section of sections) {
      section.update(fixtureSnapshot(), []);
      expect(section.element.hidden).toBe(true);
      section.update(snapshot({ status: 'invalid' }), []);
      expect(section.element.hidden).toBe(true);
    }
    const macros = mount(new MacroEditor({ host }));
    macros.update(snapshot({ macros: [] }), []);
    expect(macros.element.hidden).toBe(false);
    expect(macros.element.querySelector('.item-detail')?.textContent).toContain('まだありません');
    expect(button(macros.element, 'add')).toBeDefined();
  });

  it('App の下のペインで、QMK 設定より前に置ける', () => {
    const root = document.createElement('div');
    document.body.append(root);
    const macros = new MacroEditor({ host });
    const app = new App(root, { host, sections: [macros.element] });
    app.receive({ type: 'snapshot', snapshot: snapshot(), changes: [] });
    macros.update(snapshot(), []);
    // v0.4: 一番下は節「デバイス転送」（App が置く）。渡した節はその前
    expect(root.querySelector('.bottom-pane > .device-transfer')?.previousElementSibling).toBe(macros.element);
  });
});

describe('マクロの節', () => {
  it('一覧（番号・名前・説明）と、選んだマクロの手順を描く', () => {
    const macros = mount(new MacroEditor({ host }));
    macros.update(snapshot(), []);
    const rows = [...macros.element.querySelectorAll<HTMLElement>('.item-row')];
    expect(rows.map((r) => r.dataset.item)).toEqual(['Bracket Pair', 'Copy Selected']);
    expect(rows[0]?.textContent).toContain('角括弧ペア');
    expect(rows[1]?.textContent).toContain('preset: VS Code:編集:選択をコピー');
    expect(macros.selected).toBe('Bracket Pair');
    expect(stepActions(macros.element)).toEqual(['タップ（tap）', '待つ（delay）', '文字（text）', 'タップ（tap）']);
    expect(input(macros.element, 'step:0:key:0').value).toBe('A');
    expect(input(macros.element, 'step:0:key:1').value).toBe('B');
    expect(input(macros.element, 'step:1:duration').value).toBe('100');
    expect(input(macros.element, 'step:2:content').value).toBe('hi');
    expect(input(macros.element, 'step:3:key:0').value).toBe('Escape');
    expect(input(macros.element, 'description').value).toBe('角括弧ペア');
    // 一番上は上へ、一番下は下へ動かせない
    expect(button(macros.element, 'step:0:up').disabled).toBe(true);
    expect(button(macros.element, 'step:3:down').disabled).toBe(true);
  });

  it('キー・ミリ秒・文字の値を決めると Change を渡し、変えた印を付ける', async () => {
    const macros = mount(new MacroEditor({ host }));
    macros.update(snapshot(), []);
    commitKey(macros.element, 'step:0:key:1', 'C');
    commitValue(macros.element, 'step:1:duration', '250');
    commitValue(macros.element, 'step:2:content', 'hello');
    // 1 つの値で書いた keys は並びの Address に書く
    commitKey(macros.element, 'step:3:key:0', 'Enter');
    expect(host.changes).toEqual<Change[]>([
      { address: at(MACRO_FILE, 'sequence', 0, 'keys', 1), value: 'C' },
      { address: at(MACRO_FILE, 'sequence', 1, 'duration'), value: 250 },
      { address: at(MACRO_FILE, 'sequence', 2, 'content'), value: 'hello' },
      { address: at(MACRO_FILE, 'sequence', 3, 'keys'), value: 'Enter' },
    ]);
    expect(macros.element.querySelector('[data-step="0"]')?.classList.contains('changed')).toBe(true);
    expect(macros.element.querySelector('.item-row.selected')?.classList.contains('changed')).toBe(true);
    // 変えた値は keycode/inspect で確かめる
    await settle(0);
    expect(host.requests.filter((r) => r.method === 'keycode/inspect').map((r) => r.params)).toContainEqual({ context: 'macroKey', text: 'C' });
  });

  it('ミリ秒が整数でない・文字が ASCII でない・空のミリ秒は渡さずに欄をエラーにする', () => {
    const macros = mount(new MacroEditor({ host }));
    macros.update(snapshot(), []);
    commitValue(macros.element, 'step:1:duration', '1.5');
    commitValue(macros.element, 'step:2:content', 'こんにちは');
    commitValue(macros.element, 'step:1:duration', '');
    expect(host.changes).toEqual([]);
    expect(host.edits).toEqual([]);
    const fields = [...macros.element.querySelectorAll('.macro-step .item-field.error')];
    expect(fields).toHaveLength(2);
    expect(macros.element.textContent).toContain('ASCII の文字だけを書けます');
    expect(macros.element.textContent).toContain('空にはできません');
  });

  it('手順を上下に動かす・消す・足すと AnyChange を渡し、その場で並びを描き直す', () => {
    const macros = mount(new MacroEditor({ host }));
    macros.update(snapshot(), []);
    button(macros.element, 'step:2:up').click();
    expect(stepActions(macros.element)).toEqual(['タップ（tap）', '文字（text）', '待つ（delay）', 'タップ（tap）']);
    // フォーカスは動かした手順についていく
    expect(document.activeElement).toBe(button(macros.element, 'step:1:up'));
    button(macros.element, 'step:0:down').click();
    button(macros.element, 'step:3:remove').click();
    const select = macros.element.querySelector<HTMLSelectElement>('[data-focus="add-step-kind"]')!;
    select.value = 'delay';
    select.dispatchEvent(new Event('change'));
    button(macros.element, 'add-step').click();
    const sequence = at(MACRO_FILE, 'sequence');
    expect(host.edits).toEqual<AnyChange[]>([
      { op: 'move', address: sequence, from: 2, to: 1 },
      { op: 'move', address: sequence, from: 0, to: 1 },
      { op: 'remove', address: at(MACRO_FILE, 'sequence', 3) },
      { op: 'insert', address: sequence, index: 3, value: { action: 'delay', duration: 100 } },
    ]);
    expect(stepActions(macros.element)).toEqual(['文字（text）', 'タップ（tap）', '待つ（delay）', '待つ（delay）']);
    expect(input(macros.element, 'step:3:duration').value).toBe('100');
    expect(document.activeElement).toBe(input(macros.element, 'step:3:duration'));
    expect(macros.element.querySelector('.macro-steps-title')?.classList.contains('changed')).toBe(true);
  });

  it('手順のキーを足す・消す', () => {
    const macros = mount(new MacroEditor({ host }));
    macros.update(snapshot(), []);
    button(macros.element, 'step:0:add-key').click();
    expect(input(macros.element, 'step:0:key:2').value).toBe('NoKey');
    button(macros.element, 'step:0:key:0:remove').click();
    expect(host.edits).toEqual<AnyChange[]>([
      { op: 'insert', address: at(MACRO_FILE, 'sequence', 0, 'keys'), index: 2, value: 'NoKey' },
      { op: 'remove', address: at(MACRO_FILE, 'sequence', 0, 'keys', 0) },
    ]);
    expect([0, 1].map((j) => input(macros.element, `step:0:key:${j}`).value)).toEqual(['B', 'NoKey']);
  });

  it('ホストの pending（未保存の変更の全部）を当てて描き、打っている欄は作り直さない', () => {
    const macros = mount(new MacroEditor({ host }));
    const pending: AnyChange[] = [
      { op: 'insert', address: at(MACRO_FILE, 'sequence'), index: 0, value: { action: 'text', content: 'first' } },
      { address: at(MACRO_FILE, 'sequence', 1, 'keys', 0), value: 'Z' },
    ];
    macros.update(snapshot(), [], pending);
    expect(stepActions(macros.element)[0]).toBe('文字（text）');
    expect(input(macros.element, 'step:0:content').value).toBe('first');
    expect(input(macros.element, 'step:1:key:0').value).toBe('Z');
    expect(macros.element.querySelector('[data-step="0"]')?.classList.contains('changed')).toBe(true);
    // 形が同じなら欄は同じもの（値だけ描き直す）
    const before = input(macros.element, 'step:1:key:1');
    macros.update(snapshot(), [], [...pending, { address: at(MACRO_FILE, 'sequence', 1, 'keys', 1), value: 'Y' }]);
    expect(input(macros.element, 'step:1:key:1')).toBe(before);
    expect(before.value).toBe('Y');
    // 保存して pending が空になれば snapshot のまま
    macros.update(snapshot(), [], []);
    expect(stepActions(macros.element)).toHaveLength(4);
  });

  it('「キーの候補をすべて出す」で keycode/candidates に all: true を足す', async () => {
    const macros = mount(new MacroEditor({ host }));
    macros.update(snapshot(), []);
    const field = input(macros.element, 'step:0:key:0');
    field.focus();
    field.value = 'a';
    field.dispatchEvent(new Event('input'));
    await settle();
    const toggle = input(macros.element, 'all');
    toggle.checked = true;
    toggle.dispatchEvent(new Event('change'));
    field.focus();
    field.value = 'b';
    field.dispatchEvent(new Event('input'));
    await settle();
    const params = host.requests.filter((r) => r.method === 'keycode/candidates').map((r) => r.params);
    expect(params[0]).toEqual({ context: 'macroKey', query: 'a', limit: 50 });
    expect(params[1]).toEqual({ context: 'macroKey', query: 'b', limit: 50, all: true });
  });

  it('説明を変える・消す（空にすると行を消す remove）', () => {
    const macros = mount(new MacroEditor({ host }));
    macros.update(snapshot(), []);
    commitValue(macros.element, 'description', '新しい説明');
    commitValue(macros.element, 'description', '');
    expect(host.changes).toEqual([{ address: at(MACRO_FILE, 'description'), value: '新しい説明' }]);
    expect(host.edits).toEqual([{ op: 'remove', address: at(MACRO_FILE, 'description') }]);
  });

  it('preset: のマクロは手順を summary で読むだけにし、preset の名前を直せる', () => {
    const macros = mount(new MacroEditor({ host }));
    macros.update(snapshot(), []);
    macros.element.querySelector<HTMLElement>('.item-row[data-item="Copy Selected"]')!.click();
    expect(macros.selected).toBe('Copy Selected');
    expect([...macros.element.querySelectorAll('.macro-summary li')].map((e) => e.textContent)).toEqual(['tap: ⌘C', 'delay: 50ms']);
    expect(macros.element.querySelector('.macro-step')).toBeNull();
    expect(input(macros.element, 'preset').value).toBe('VS Code:編集:選択をコピー');
    commitValue(macros.element, 'preset', 'VS Code:編集:行をコピー');
    expect(host.changes).toEqual([{ address: at(PRESET_FILE, 'preset'), value: 'VS Code:編集:行をコピー' }]);
  });

  it('preset は同梱のショートカットの木（手順の定義だけ）から「アプリ → カテゴリ → ラベル」で選び直せる。木は 1 回だけ取る', async () => {
    const macros = mount(new MacroEditor({ host }));
    macros.update(snapshot(), []);
    macros.select('Copy Selected');
    const pick = button(macros.element, 'preset-pick');
    pick.click();
    await settle(0);
    expect(pick.getAttribute('aria-expanded')).toBe('true');
    // 1 シーケンスの定義（コマンドパレット・フレーム）は出さず、それしかないアプリ（Figma）も出さない
    const apps = [...macros.element.querySelectorAll('.preset-app > summary')].map((e) => e.textContent);
    expect(apps).toEqual(['VS Code1']);
    expect(macros.element.querySelector('.preset-app .icon')).not.toBeNull();
    const items = [...macros.element.querySelectorAll<HTMLButtonElement>('.preset-item')];
    expect(items.map((e) => [e.textContent, e.dataset.preset])).toEqual([['キーボードショートカット', 'VS Code:基本操作:キーボードショートカット']]);
    // 絞り込み
    const search = input(macros.element, 'preset-search');
    search.value = 'figma';
    search.dispatchEvent(new Event('input'));
    expect(macros.element.querySelector('.preset-tree')?.textContent).toBe('合うものがありません');
    search.value = '基本';
    search.dispatchEvent(new Event('input'));
    macros.element.querySelector<HTMLButtonElement>('.preset-item')!.click();
    expect(host.changes).toEqual([{ address: at(PRESET_FILE, 'preset'), value: 'VS Code:基本操作:キーボードショートカット' }]);
    expect(input(macros.element, 'preset').value).toBe('VS Code:基本操作:キーボードショートカット');
    expect(pick.getAttribute('aria-expanded')).toBe('false');
    // 開き直すと今の preset に印が付き、木は取り直さない
    pick.click();
    await settle(0);
    expect(macros.element.querySelector('.preset-item.selected')?.getAttribute('aria-current')).toBe('true');
    expect(host.requests.filter((r) => r.method === 'keycode/shortcutTree')).toHaveLength(1);
    // Escape で閉じる
    input(macros.element, 'preset-search').dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true, cancelable: true }));
    expect(pick.getAttribute('aria-expanded')).toBe('false');
  });

  it('検証の結果: 欄の Address のものは欄に、そのほかのそのファイルのものは項目の上に出し、一覧の行に印を付ける', () => {
    const diagnostics: Diagnostic[] = [
      { severity: 'warning', source: 'semantic', message: 'Cornix は対応していません', address: at(MACRO_FILE, 'sequence', 0, 'keys', 0) },
      { severity: 'error', source: 'structure', message: '手順の形が違います', address: at(MACRO_FILE, 'sequence', 9) },
      { severity: 'error', source: 'structure', message: 'preset の名前がありません', address: at(PRESET_FILE, 'preset') },
    ];
    const macros = mount(new MacroEditor({ host }));
    macros.update(snapshot({ diagnostics }), []);
    const key = input(macros.element, 'step:0:key:0').closest('.key-input')!;
    expect(key.classList.contains('warning')).toBe(true);
    expect(key.textContent).toContain('Cornix は対応していません');
    expect(macros.element.querySelector('.item-problems')?.textContent).toBe('手順の形が違います');
    const rows = [...macros.element.querySelectorAll<HTMLElement>('.item-row')];
    expect(rows.map((r) => r.classList.contains('error'))).toEqual([true, true]);
  });

  it('変えた値は keycode/inspect の結果で検証を出す（読めない表記はエラー）', async () => {
    const macros = mount(new MacroEditor({ host }));
    macros.update(snapshot(), []);
    commitKey(macros.element, 'step:0:key:0', 'Nope');
    await settle(0);
    const key = input(macros.element, 'step:0:key:0').closest('.key-input')!;
    expect(key.classList.contains('error')).toBe(true);
    expect(key.textContent).toContain('「Nope」は読めない表記です');
  });
});

describe('項目の追加・削除・名前の変更', () => {
  it('追加は名前を入れて ItemEdit の create を渡す（決まりに合わない名前は渡さない）', () => {
    const macros = mount(new MacroEditor({ host }));
    macros.update(snapshot(), []);
    button(macros.element, 'add').click();
    expect(macros.formOpen).toBe(true);
    const name = input(macros.element, 'form-name');
    expect(document.activeElement).toBe(name);
    name.value = 'Bracket Pair';
    name.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', cancelable: true }));
    expect(macros.element.querySelector('.item-form-message')?.textContent).toBe('「Bracket Pair」はもうあります');
    expect(host.itemEdits).toEqual([]);
    name.value = 'Paren Pair';
    name.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', cancelable: true }));
    expect(host.itemEdits).toEqual([{ op: 'create', kind: 'macro', name: 'Paren Pair' }]);
    expect(macros.formOpen).toBe(false);
    // 新しい snapshot で現れたら選ぶ
    macros.update(snapshot({ macros: [MACRO, PRESET_MACRO, { ...MACRO, index: 3, name: 'Paren Pair', file: 'macros/03_paren_pair.yml' }] }), []);
    expect(macros.selected).toBe('Paren Pair');
  });

  it('Escape・「やめる」で閉じる', () => {
    const macros = mount(new MacroEditor({ host }));
    macros.update(snapshot(), []);
    button(macros.element, 'add').click();
    input(macros.element, 'form-name').dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', cancelable: true }));
    expect(macros.formOpen).toBe(false);
    expect(document.activeElement).toBe(button(macros.element, 'add'));
  });

  it('名前の変更と削除は ItemEdit を渡すだけ（確認はホスト）', () => {
    const tapDances = mount(new TapDanceEditor({ host }));
    tapDances.update(snapshot(), []);
    button(tapDances.element, 'rename').click();
    const name = input(tapDances.element, 'form-name');
    expect(name.value).toBe('Tab Escape');
    name.value = 'Tab Esc';
    name.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', cancelable: true }));
    // ホストの確認でやめたら（新しい名前が現れない）選んでいる項目はそのまま
    tapDances.update(snapshot({ tapDances: [TAP_DANCE, { ...TAP_DANCE, index: 5, name: 'Another', file: 'tap_dance/05_another.yml' }] }), []);
    expect(tapDances.selected).toBe('Tab Escape');
    button(tapDances.element, 'delete').click();
    expect(host.itemEdits).toEqual([
      { op: 'rename', kind: 'tapDance', name: 'Tab Escape', to: 'Tab Esc' },
      { op: 'delete', kind: 'tapDance', name: 'Tab Escape' },
    ]);
  });

  it('ショートカットの追加は値も入れる', () => {
    const shortcuts = mount(new ShortcutEditor({ host }));
    shortcuts.update(snapshot(), []);
    button(shortcuts.element, 'add').click();
    const name = input(shortcuts.element, 'form-name');
    name.value = '保存';
    name.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', cancelable: true }));
    expect(shortcuts.element.querySelector('.item-form-message')?.textContent).toBe('値を入れてください');
    shortcuts.element.querySelector<HTMLInputElement>('.item-name-form .key-input-field')!.value = 'Command + S';
    name.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', cancelable: true }));
    expect(host.itemEdits).toEqual([{ op: 'create', kind: 'shortcut', name: '保存', value: 'Command + S' }]);
  });
});

describe('タップダンスの節', () => {
  it('4 つの動作の欄。候補はそのタップダンス自身を除き、割り当てを消せる', async () => {
    const tapDances = mount(new TapDanceEditor({ host }));
    tapDances.update(snapshot(), []);
    expect(['tap', 'hold', 'doubleTap', 'tapHold'].map((a) => input(tapDances.element, `action:${a}`).value)).toEqual(['Tab', 'Escape', '', '']);
    const field = input(tapDances.element, 'action:doubleTap');
    field.focus();
    field.value = 'm';
    field.dispatchEvent(new Event('input'));
    await settle();
    expect(host.requests.find((r) => r.method === 'keycode/candidates')?.params).toEqual({
      context: 'tapDanceAction',
      query: 'm',
      limit: 50,
      exclude: "TapDance('Tab Escape')",
    });
    field.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true, cancelable: true }));
    commitKey(tapDances.element, 'action:doubleTap', 'MO(1)');
    button(tapDances.element, 'action:hold:remove').click();
    // 書いていない動作を消しても何もしない
    button(tapDances.element, 'action:tapHold:remove').click();
    expect(host.changes).toEqual([{ address: at(TAP_DANCE_FILE, 'actions', 'on_double_tap'), value: 'MO(1)' }]);
    expect(host.edits).toEqual([{ op: 'remove', address: at(TAP_DANCE_FILE, 'actions', 'on_hold') }]);
    expect(input(tapDances.element, 'action:hold').value).toBe('');
  });

  it('動作ごとに注記の欄を置く（field: "note"。空にすると注記だけを消す。書いていない動作には書けない）', () => {
    const noted = structuredClone(TAP_DANCE);
    noted.actions.hold.value = { ...noted.actions.hold.value!, note: '押しっぱなしで Esc' };
    const tapDances = mount(new TapDanceEditor({ host }));
    tapDances.update(snapshot({ tapDances: [noted] }), []);
    expect(input(tapDances.element, 'action:hold:note').value).toBe('押しっぱなしで Esc');
    expect(input(tapDances.element, 'action:hold:note').closest('.item-field')?.classList.contains('has-note')).toBe(true);
    expect(input(tapDances.element, 'action:doubleTap:note').disabled).toBe(true);
    const tap = input(tapDances.element, 'action:tap:note');
    tap.value = ' タブ ';
    tap.dispatchEvent(new Event('input'));
    tap.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true, cancelable: true }));
    const hold = input(tapDances.element, 'action:hold:note');
    hold.value = '';
    hold.dispatchEvent(new Event('input'));
    hold.dispatchEvent(new FocusEvent('blur'));
    expect(host.changes).toEqual([{ address: at(TAP_DANCE_FILE, 'actions', 'on_tap'), value: 'タブ', field: 'note' }]);
    expect(host.edits).toEqual([{ op: 'remove', address: at(TAP_DANCE_FILE, 'actions', 'on_hold'), field: 'note' }]);
    expect(input(tapDances.element, 'action:tap:note').value).toBe('タブ');
    expect(input(tapDances.element, 'action:tap').closest('.item-field')?.classList.contains('changed')).toBe(true);
    // Escape は打つ前の注記に戻す（渡さない）
    const again = input(tapDances.element, 'action:tap:note');
    again.value = '別の注記';
    again.dispatchEvent(new Event('input'));
    again.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true, cancelable: true }));
    again.dispatchEvent(new FocusEvent('blur'));
    expect(again.value).toBe('タブ');
    expect(host.changes).toHaveLength(1);
  });

  it('キーの欄にフォーカスすると、レイヤーの欄と同じ説明（題・説明の行・注記）を出す', async () => {
    const noted = structuredClone(TAP_DANCE);
    noted.actions.hold.value = { ...noted.actions.hold.value!, note: '押しっぱなしで Esc' };
    const tapDances = mount(new TapDanceEditor({ host }));
    tapDances.update(snapshot({ tapDances: [noted] }), []);
    const field = input(tapDances.element, 'action:hold');
    field.focus();
    field.dispatchEvent(new FocusEvent('focus'));
    await settle(10);
    const tooltip = document.querySelector<HTMLElement>('.tooltip');
    expect(tooltip?.hidden).toBe(false);
    expect(field.getAttribute('aria-describedby')).toBe(tooltip?.id);
    expect(tooltip?.querySelector('.tooltip-title')?.textContent).toBeTruthy();
    expect(tooltip?.querySelector('.tooltip-note')?.textContent).toBe('注記: 押しっぱなしで Esc');
    field.dispatchEvent(new FocusEvent('blur'));
    expect(tooltip?.hidden).toBe(true);
    // 書いていない欄には出さない
    const empty = input(tapDances.element, 'action:doubleTap');
    empty.focus();
    empty.dispatchEvent(new FocusEvent('focus'));
    await settle(10);
    expect(tooltip?.hidden).toBe(true);
  });

  it('tapping_term は数値の欄で、QMK 設定の値を添え、空にすると消す', () => {
    const tapDances = mount(new TapDanceEditor({ host }));
    tapDances.update(snapshot(), []);
    const term = input(tapDances.element, 'tapping-term');
    expect(term.value).toBe('200');
    expect(term.placeholder).toBe('既定 250');
    expect(term.closest('.item-field')?.textContent).toContain('QMK 設定の tapping_term: 180');
    commitValue(tapDances.element, 'tapping-term', '180');
    commitValue(tapDances.element, 'tapping-term', '');
    expect(host.changes).toEqual([{ address: at(TAP_DANCE_FILE, 'tapping_term'), value: 180 }]);
    expect(host.edits).toEqual([{ op: 'remove', address: at(TAP_DANCE_FILE, 'tapping_term') }]);
  });
});

describe('コンボの節', () => {
  it('同時に押すキーを足す（4 つまで）・消す、出すキーを変える', () => {
    const combos = mount(new ComboEditor({ host }));
    combos.update(snapshot(), []);
    expect([0, 1].map((i) => input(combos.element, `trigger:${i}`).value)).toEqual(['Q', 'W']);
    expect(input(combos.element, 'output').value).toBe("Macro('Bracket Pair')");
    button(combos.element, 'add-trigger').click();
    button(combos.element, 'add-trigger').click();
    expect(button(combos.element, 'add-trigger').disabled).toBe(true);
    button(combos.element, 'trigger:0:remove').click();
    commitKey(combos.element, 'output', 'Escape');
    const list = at(COMBO_FILE, 'trigger_keys');
    expect(host.edits).toEqual<AnyChange[]>([
      { op: 'insert', address: list, index: 2, value: 'NoKey' },
      { op: 'insert', address: list, index: 3, value: 'NoKey' },
      { op: 'remove', address: at(COMBO_FILE, 'trigger_keys', 0) },
    ]);
    expect(host.changes).toEqual([{ address: at(COMBO_FILE, 'output_key'), value: 'Escape' }]);
    expect([0, 1, 2].map((i) => input(combos.element, `trigger:${i}`).value)).toEqual(['W', 'NoKey', 'NoKey']);
    expect(combos.element.querySelector('.combo-triggers-part .item-subheading')?.classList.contains('changed')).toBe(true);
  });

  it('出すキーには注記の欄を置き、同時に押すキーには置かない', () => {
    const combos = mount(new ComboEditor({ host }));
    combos.update(snapshot(), []);
    expect(combos.element.querySelector("[data-focus='trigger:0:note']")).toBeNull();
    const note = input(combos.element, 'output:note');
    note.value = '[ と ]';
    note.dispatchEvent(new Event('input'));
    note.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true, cancelable: true }));
    expect(host.changes).toEqual([{ address: at(COMBO_FILE, 'output_key'), value: '[ と ]', field: 'note' }]);
  });

  it('同時に押すキーは comboTrigger、出すキーは comboOutput の候補', async () => {
    const combos = mount(new ComboEditor({ host }));
    combos.update(snapshot(), []);
    for (const focus of ['trigger:0', 'output']) {
      const field = input(combos.element, focus);
      field.focus();
      field.value = 'e';
      field.dispatchEvent(new Event('input'));
      await settle();
    }
    expect(host.requests.filter((r) => r.method === 'keycode/candidates').map((r) => (r.params as { context: string }).context)).toEqual([
      'comboTrigger',
      'comboOutput',
    ]);
  });
});

describe('ショートカットの節', () => {
  it('名前ごとの値を shortcutValue の欄で直し、変えた行と検証の印はその名前の行だけに付ける', () => {
    const shortcuts = mount(new ShortcutEditor({ host }));
    const diagnostics: Diagnostic[] = [{ severity: 'error', source: 'structure', message: '読めない表記です', address: at(SHORTCUTS_FILE, 'shortcuts', '次のタブへ') }];
    shortcuts.update(snapshot({ diagnostics }), []);
    expect(input(shortcuts.element, 'value').value).toBe('Command + Shift + [');
    commitKey(shortcuts.element, 'value', 'Command + [');
    expect(host.changes).toEqual([{ address: at(SHORTCUTS_FILE, 'shortcuts', '前のタブへ'), value: 'Command + [' }]);
    const rows = [...shortcuts.element.querySelectorAll<HTMLElement>('.item-row')];
    expect(rows.map((r) => [r.dataset.item, r.classList.contains('changed'), r.classList.contains('error')])).toEqual([
      ['前のタブへ', true, false],
      ['次のタブへ', false, true],
    ]);
  });
});
