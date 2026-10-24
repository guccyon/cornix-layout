// @vitest-environment happy-dom
// 修飾キー式・LT・Mod-Tap の組み立て欄（E2）と、未保存の変更を欄ごとに畳む model.ts の関数
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import type { AnyChange, KeyValue } from '../../../src/protocol';
import { KeyInput } from '../../../src/webview/keyInput';
import { addPending, slotEdits } from '../../../src/webview/model';
import { buildNotation, emptyState, parseNotation, type BuildState } from '../../../src/webview/modifierBuilder';
import { FakeHost, settle } from './fakeHost';

const state = (patch: Partial<BuildState>): BuildState => ({ ...emptyState(), ...patch });

describe('buildNotation（docs/notation.md の形）', () => {
  it('修飾キー式は Ctrl, Option, Shift, Command の順（右は RCtrl など）', () => {
    expect(buildNotation(state({ mods: ['gui', 'shift'], key: 'P' }))).toBe('Shift + Command + P');
    expect(buildNotation(state({ mods: ['ctrl', 'alt', 'shift', 'gui'], key: 'A' }))).toBe('Ctrl + Option + Shift + Command + A');
    expect(buildNotation(state({ side: 'right', mods: ['shift', 'gui'], key: 'P' }))).toBe('RShift + RCommand + P');
  });

  it('LT はレイヤーとキー、Mod-Tap は正規名_T（正規名がなければ MT(MOD_...)）', () => {
    expect(buildNotation(state({ kind: 'layerTap', layer: 2, key: 'Escape' }))).toBe('LT(2, Escape)');
    expect(buildNotation(state({ kind: 'modTap', side: 'right', mods: ['shift'], key: 'Up' }))).toBe('RSFT_T(Up)');
    expect(buildNotation(state({ kind: 'modTap', mods: ['gui'], key: 'Lang2' }))).toBe('LGUI_T(Lang2)');
    expect(buildNotation(state({ kind: 'modTap', mods: ['ctrl', 'alt', 'shift', 'gui'], key: 'A' }))).toBe('HYPR_T(A)');
    expect(buildNotation(state({ kind: 'modTap', mods: ['ctrl', 'shift'], key: 'A' }))).toBe('C_S_T(A)');
    expect(buildNotation(state({ kind: 'modTap', side: 'right', mods: ['ctrl', 'alt', 'shift'], key: 'A' }))).toBe('MT(MOD_RCTL|MOD_RSFT|MOD_RALT, A)');
  });

  it('修飾キーかキーが足りなければ組み立てない', () => {
    expect(buildNotation(state({ key: 'P' }))).toBeNull();
    expect(buildNotation(state({ mods: ['shift'], key: ' ' }))).toBeNull();
    expect(buildNotation(state({ kind: 'layerTap', layer: 16, key: 'A' }))).toBeNull();
    // LT には修飾キーは要らない
    expect(buildNotation(state({ kind: 'layerTap', layer: 0, key: 'A' }))).toBe('LT(0, A)');
  });
});

describe('parseNotation（組み立て欄の初めの値）', () => {
  it('組み立てた形と、そのよくある書き方を読み戻す', () => {
    expect(parseNotation('Shift + Command + P')).toMatchObject({ kind: 'modifiers', side: 'left', mods: ['shift', 'gui'], key: 'P' });
    expect(parseNotation('Cmd + Shift + [')).toMatchObject({ kind: 'modifiers', side: 'left', mods: ['shift', 'gui'], key: '[' });
    expect(parseNotation('RShift + RCommand + P')).toMatchObject({ kind: 'modifiers', side: 'right', mods: ['shift', 'gui'], key: 'P' });
    expect(parseNotation('LT(2, Escape)')).toMatchObject({ kind: 'layerTap', layer: 2, key: 'Escape' });
    expect(parseNotation('LT1(Space)')).toMatchObject({ kind: 'layerTap', layer: 1, key: 'Space' });
    expect(parseNotation('RSFT_T(Up)')).toMatchObject({ kind: 'modTap', side: 'right', mods: ['shift'], key: 'Up' });
    expect(parseNotation('LGUI_T(KC_LANG2)')).toMatchObject({ kind: 'modTap', side: 'left', mods: ['gui'], key: 'KC_LANG2' });
    expect(parseNotation('CMD_T(A)')).toMatchObject({ kind: 'modTap', mods: ['gui'], key: 'A' });
    expect(parseNotation('MT(MOD_RCTL|MOD_RSFT|MOD_RALT, A)')).toMatchObject({ kind: 'modTap', side: 'right', mods: ['ctrl', 'alt', 'shift'], key: 'A' });
  });

  it('左右の混ざった式・読めない形は空から、ただのキーはキーとして入れる', () => {
    expect(parseNotation('Shift + RCommand + A')).toEqual(emptyState());
    expect(parseNotation("Macro('Bracket Pair')")).toEqual(emptyState());
    expect(parseNotation('Escape')).toEqual({ ...emptyState(), key: 'Escape' });
    expect(parseNotation('')).toEqual(emptyState());
  });
});

describe('キー入力欄の組み立て欄', () => {
  let host: FakeHost;
  let commits: string[];
  let input: KeyInput;

  beforeEach(() => {
    host = new FakeHost();
    commits = [];
    input = new KeyInput({
      context: 'layerKey',
      host,
      label: 'テスト',
      onCommit: (text) => commits.push(text),
      debounceMs: 20,
      builder: { layers: () => [{ index: 0, name: 'Base' }, { index: 2, name: 'Nav' }] },
    });
    document.body.replaceChildren(input.element);
    input.setValue('Q');
  });

  afterEach(() => {
    document.body.replaceChildren();
  });

  it('ボタンで今の値から開き、組み立てた表記を keycode/inspect で確かめてから入れる', async () => {
    const button = input.element.querySelector<HTMLButtonElement>('.key-input-build')!;
    expect(button.getAttribute('aria-label')).toBe('テストを組み立てる');
    button.click();
    const builder = input.builder!;
    expect(builder.isOpen).toBe(true);
    expect(button.getAttribute('aria-expanded')).toBe('true');
    expect(builder.current.key).toBe('Q');
    expect(builder.element.querySelector<HTMLInputElement>('.key-input-field')?.value).toBe('Q');

    builder.set({ mods: ['shift', 'gui'], key: 'P' });
    expect(builder.element.querySelector('.builder-text')?.textContent).toBe('Shift + Command + P');
    await settle(0);
    expect(host.requests).toContainEqual({ method: 'keycode/inspect', params: { context: 'layerKey', text: 'Shift + Command + P' } });
    expect(builder.element.querySelector('.builder-meaning')?.textContent).toBe('→ Shift + Command + P（⇧⌘P）');
    expect(builder.element.querySelector<HTMLButtonElement>('.builder-apply')?.disabled).toBe(false);

    builder.element.querySelector<HTMLButtonElement>('.builder-apply')!.click();
    await settle(0);
    expect(commits).toEqual(['Shift + Command + P']);
    expect(input.input.value).toBe('Shift + Command + P');
    expect(builder.isOpen).toBe(false);
    expect(button.getAttribute('aria-expanded')).toBe('false');
  });

  it('読めない表記は入れずに理由を出し、読めるようになれば入れる', async () => {
    input.openBuilder();
    const builder = input.builder!;
    builder.set({ kind: 'layerTap', layer: 2, key: 'Escape' });
    await settle(0);
    expect(builder.element.querySelector('.builder-text')?.textContent).toBe('LT(2, Escape)');
    expect(builder.element.querySelector('.builder-message.error')?.textContent).toBe('「LT(2, Escape)」は読めない表記です');
    expect(await builder.apply()).toBe(false);
    expect(commits).toEqual([]);

    const lt: KeyValue = { text: 'LT(2, Escape)', canonical: 'LT2(Escape)', code: 0x4229, kind: 'layerTap', display: { label: 'Esc', tap: 'Esc', hold: 'L2' } };
    host.values.set('LT(2, Escape)', lt);
    expect(await builder.apply()).toBe(true);
    expect(commits).toEqual(['LT(2, Escape)']);
  });

  it('レイヤーの選び先は渡したレイヤー、修飾キーは左右を 1 つだけ選ぶ（混在を作らない）', () => {
    input.openBuilder();
    const builder = input.builder!;
    builder.set({ kind: 'layerTap' });
    const options = [...builder.element.querySelectorAll<HTMLOptionElement>('.builder-layer option')].map((o) => o.textContent);
    expect(options).toEqual(['0 Base', '1', '2 Nav']);
    builder.set({ kind: 'modTap' });
    const sides = builder.element.querySelectorAll<HTMLInputElement>('.builder-sides input[type="radio"]');
    expect(sides).toHaveLength(2);
    sides[1]!.checked = true;
    sides[1]!.dispatchEvent(new Event('change'));
    const shift = builder.element.querySelector<HTMLInputElement>('.builder-mods input[value="shift"]')!;
    shift.checked = true;
    shift.dispatchEvent(new Event('change'));
    builder.set({ key: 'Up' });
    expect(builder.element.querySelector('.builder-text')?.textContent).toBe('RSFT_T(Up)');
  });

  it('修飾キーがないうちは足りないものを出し、Escape で閉じる', () => {
    input.openBuilder();
    const builder = input.builder!;
    expect(builder.element.querySelector('.builder-missing')?.textContent).toBe('修飾キーを 1 つ以上選んでください');
    expect(builder.element.querySelector<HTMLButtonElement>('.builder-apply')?.disabled).toBe(true);
    builder.element.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true, cancelable: true }));
    expect(builder.isOpen).toBe(false);
    expect(commits).toEqual([]);
  });

  it('欄の外を押すと閉じ（フォーカスは戻さない）、中を押しても閉じない', () => {
    const outside = document.createElement('button');
    document.body.append(outside);
    input.openBuilder();
    const builder = input.builder!;
    builder.element.querySelector('.builder-preview')!.dispatchEvent(new MouseEvent('mousedown', { bubbles: true }));
    expect(builder.isOpen).toBe(true);
    outside.dispatchEvent(new MouseEvent('mousedown', { bubbles: true }));
    expect(builder.isOpen).toBe(false);
    expect(document.activeElement).not.toBe(input.input);
  });

  it('candidateParams を keycode/candidates の params に足す', async () => {
    const own = new KeyInput({ context: 'tapDanceAction', host, label: 'x', onCommit: () => undefined, debounceMs: 0, candidateParams: { exclude: "TapDance('Tab Escape')" } });
    document.body.append(own.element);
    own.input.focus();
    own.open();
    await settle(10);
    expect(host.requests.at(-1)?.params).toMatchObject({ context: 'tapDanceAction', exclude: "TapDance('Tab Escape')" });
  });
});

describe('未保存の変更を欄ごとに畳む', () => {
  const a = { file: 'layers/0_base.yml', path: ['mapping', 'left_hand', 'row0', 'Q'] };
  const id = JSON.stringify([a.file, ...a.path]);
  const saved: KeyValue = { text: 'Q', canonical: 'Q', code: 20, kind: 'basic', display: { label: 'Q' }, note: '元の注記' };

  it('slotEdits: 行の remove は割り当てと注記を消し、注記の remove は注記だけ', () => {
    const edits = slotEdits([
      { address: a, value: 'Escape' },
      { address: a, value: 'メモ', field: 'note' },
      { op: 'remove', address: a },
    ]);
    expect(edits.values.get(id)).toBeNull();
    expect(edits.notes.get(id)).toBeNull();
    const notes = slotEdits([{ op: 'remove', address: a, field: 'note' }]);
    expect(notes.values.has(id)).toBe(false);
    expect(notes.notes.get(id)).toBeNull();
  });

  it('addPending: 同じ Address・同じ field の set は最後のものだけ。保存済みと同じ値なら足さない', () => {
    let list: AnyChange[] = [];
    list = addPending(list, { address: a, value: 'Escape' }, saved);
    list = addPending(list, { address: a, value: 'Tab' }, saved);
    expect(list).toEqual([{ address: a, value: 'Tab' }]);
    list = addPending(list, { address: a, value: 'メモ', field: 'note' }, saved);
    expect(list).toHaveLength(2);
    list = addPending(list, { address: a, value: 'Q' }, saved);
    expect(list).toEqual([{ address: a, value: 'メモ', field: 'note' }]);
  });

  it('addPending: 行を消すと前の set を外し、そのあとの set は保存済みと同じ値でも残す', () => {
    let list: AnyChange[] = [{ address: a, value: 'Tab' }, { address: a, value: 'メモ', field: 'note' }];
    list = addPending(list, { op: 'remove', address: a }, saved);
    expect(list).toEqual([{ op: 'remove', address: a }]);
    list = addPending(list, { op: 'remove', address: a }, saved);
    expect(list).toHaveLength(1);
    list = addPending(list, { address: a, value: 'Q' }, saved);
    expect(list).toEqual([{ op: 'remove', address: a }, { address: a, value: 'Q' }]);
  });

  it('addPending: 保存済みに何もなければ remove は足さず、前の set を外すだけ', () => {
    const empty: AnyChange[] = [{ address: a, value: 'Tab' }];
    expect(addPending(empty, { op: 'remove', address: a }, null)).toEqual([]);
    expect(addPending([{ address: a, value: 'x', field: 'note' }], { op: 'remove', address: a, field: 'note' }, { ...saved, note: undefined } as KeyValue)).toEqual([]);
    expect(addPending([], { op: 'remove', address: a, field: 'note' }, saved)).toEqual([{ op: 'remove', address: a, field: 'note' }]);
  });
});
