// 未保存の変更（並びへの insert / remove / move と set）を snapshot の並びに当てる純粋な関数
import { describe, expect, it } from 'vitest';
import type { AnyChange } from '../../../src/protocol';
import { comboView, effectivePending, macroView, nameProblem, shortcutView, tapDanceView } from '../../../src/webview/itemsModel';
import { at, COMBO, COMBO_FILE, MACRO, MACRO_FILE, PRESET_FILE, PRESET_MACRO, SHORTCUTS, SHORTCUTS_FILE, TAP_DANCE, TAP_DANCE_FILE } from './itemFixtures';

const keysOf = (view: ReturnType<typeof macroView>, i: number) => {
  const step = view.steps[i]!;
  if (step.action !== 'tap' && step.action !== 'down' && step.action !== 'up') throw new Error(`手順 ${i} はキーの手順でない`);
  return step.keys;
};

describe('macroView', () => {
  it('変更がなければ snapshot の並びのまま（1 つの値で書いた keys は要素の Address が並びの Address）', () => {
    const view = macroView(MACRO, []);
    expect(view.steps.map((s) => s.action)).toEqual(['tap', 'delay', 'text', 'tap']);
    expect(view.restructured).toBe(false);
    expect(keysOf(view, 0).keys.map((k) => [k.text, k.changed])).toEqual([
      ['A', false],
      ['B', false],
    ]);
    expect(keysOf(view, 3).scalar).toBe(true);
    expect(keysOf(view, 3).keys[0]!.address).toEqual(at(MACRO_FILE, 'sequence', 3, 'keys'));
    expect(view.steps.some((s) => s.changed)).toBe(false);
  });

  it('insert は index の前に足し、あとの手順の Address を振り直す。そのあとの位置での set が足した手順に当たる', () => {
    const pending: AnyChange[] = [
      { op: 'insert', address: at(MACRO_FILE, 'sequence'), index: 1, value: { action: 'down', keys: ['LShift'] } },
      { address: at(MACRO_FILE, 'sequence', 1, 'keys', 0), value: 'LCtrl' },
      { address: at(MACRO_FILE, 'sequence', 2, 'duration'), value: 300 },
    ];
    const view = macroView(MACRO, pending);
    expect(view.steps.map((s) => s.action)).toEqual(['tap', 'down', 'delay', 'text', 'tap']);
    expect(view.restructured).toBe(true);
    const inserted = keysOf(view, 1);
    expect(inserted.keys[0]).toMatchObject({ text: 'LCtrl', saved: null, changed: true, address: at(MACRO_FILE, 'sequence', 1, 'keys', 0) });
    expect(view.steps[1]).toMatchObject({ inserted: true, changed: true });
    const delay = view.steps[2]!;
    expect(delay.action === 'delay' && delay.duration).toMatchObject({ value: 300, saved: 100, changed: true, address: at(MACRO_FILE, 'sequence', 2, 'duration') });
    // 元の手順の Address は位置で振り直す（text は 2 → 3）
    expect(view.steps[3]!.address).toEqual(at(MACRO_FILE, 'sequence', 3));
    expect(view.steps[3]!.changed).toBe(false);
  });

  it('index が並びの長さなら末尾に足す。text・delay の手順も足せる', () => {
    const view = macroView(MACRO, [
      { op: 'insert', address: at(MACRO_FILE, 'sequence'), index: 4, value: { action: 'text', content: 'end' } },
      { op: 'insert', address: at(MACRO_FILE, 'sequence'), index: 0, value: { action: 'delay', duration: 50 } },
    ]);
    expect(view.steps.map((s) => s.action)).toEqual(['delay', 'tap', 'delay', 'text', 'tap', 'text']);
    const last = view.steps[5]!;
    expect(last.action === 'text' && last.content).toMatchObject({ value: 'end', saved: null, changed: true });
  });

  it('remove は手順を消し、あとの位置の set は詰めた位置で数える', () => {
    const view = macroView(MACRO, [
      { op: 'remove', address: at(MACRO_FILE, 'sequence', 0) },
      { address: at(MACRO_FILE, 'sequence', 1, 'content'), value: 'bye' },
    ]);
    expect(view.steps.map((s) => s.action)).toEqual(['delay', 'text', 'tap']);
    const text = view.steps[1]!;
    expect(text.action === 'text' && text.content).toMatchObject({ value: 'bye', saved: 'hi', changed: true, address: at(MACRO_FILE, 'sequence', 1, 'content') });
  });

  it('move は手順を動かして印を付け、そのあとの set は動かした先の位置で当たる', () => {
    const view = macroView(MACRO, [
      { op: 'move', address: at(MACRO_FILE, 'sequence'), from: 2, to: 0 },
      { address: at(MACRO_FILE, 'sequence', 0, 'content'), value: 'moved' },
      { address: at(MACRO_FILE, 'sequence', 1, 'keys', 1), value: 'C' },
    ]);
    expect(view.steps.map((s) => s.action)).toEqual(['text', 'tap', 'delay', 'tap']);
    expect(view.steps[0]).toMatchObject({ moved: true, changed: true });
    const text = view.steps[0]!;
    expect(text.action === 'text' && text.content.value).toBe('moved');
    expect(keysOf(view, 1).keys.map((k) => k.text)).toEqual(['A', 'C']);
    expect(keysOf(view, 1).keys[1]!.changed).toBe(true);
    // 範囲の外の from は何もしない
    expect(macroView(MACRO, [{ op: 'move', address: at(MACRO_FILE, 'sequence'), from: 9, to: 0 }]).restructured).toBe(false);
  });

  it('手順のキーの insert / remove / move と、そのあとの位置での set', () => {
    const view = macroView(MACRO, [
      { op: 'insert', address: at(MACRO_FILE, 'sequence', 0, 'keys'), index: 0, value: 'Z' },
      { op: 'remove', address: at(MACRO_FILE, 'sequence', 0, 'keys', 1) },
      { op: 'move', address: at(MACRO_FILE, 'sequence', 0, 'keys'), from: 1, to: 0 },
      { address: at(MACRO_FILE, 'sequence', 0, 'keys', 1), value: 'Y' },
    ]);
    const keys = keysOf(view, 0);
    // [A, B] → [Z, A, B] → [Z, B] → [B, Z] → [B, Y]
    expect(keys.keys.map((k) => [k.text, k.changed])).toEqual([
      ['B', false],
      ['Y', true],
    ]);
    expect(keys.restructured).toBe(true);
    expect(keys.keys.map((k) => k.address.path)).toEqual([
      ['sequence', 0, 'keys', 0],
      ['sequence', 0, 'keys', 1],
    ]);
    expect(view.steps[0]!.changed).toBe(true);
  });

  it('1 つの値で書いた keys: set は要素 1 つに当たり、insert のあとは並びの形（要素ごとの Address）になる', () => {
    const scalarSet = macroView(MACRO, [{ address: at(MACRO_FILE, 'sequence', 3, 'keys'), value: 'Enter' }]);
    expect(keysOf(scalarSet, 3).keys.map((k) => [k.text, k.changed])).toEqual([['Enter', true]]);
    expect(keysOf(scalarSet, 3).scalar).toBe(true);
    const view = macroView(MACRO, [{ op: 'insert', address: at(MACRO_FILE, 'sequence', 3, 'keys'), index: 1, value: 'Enter' }]);
    const keys = keysOf(view, 3);
    expect(keys.scalar).toBe(false);
    expect(keys.keys.map((k) => [k.text, k.address.path])).toEqual([
      ['Escape', ['sequence', 3, 'keys', 0]],
      ['Enter', ['sequence', 3, 'keys', 1]],
    ]);
  });

  it('説明の set と remove、ほかのファイルの変更・注記の変更は当てない', () => {
    const view = macroView(MACRO, [
      { address: at(MACRO_FILE, 'description'), value: '新しい説明' },
      { address: at('macros/01_other.yml', 'sequence', 0, 'keys', 0), value: 'Q' },
      { address: at(MACRO_FILE, 'sequence', 0, 'keys', 0), value: 'note', field: 'note' },
    ]);
    expect(view.description).toMatchObject({ value: '新しい説明', saved: '角括弧ペア', changed: true });
    expect(keysOf(view, 0).keys[0]!.text).toBe('A');
    expect(macroView(MACRO, [{ op: 'remove', address: at(MACRO_FILE, 'description') }]).description).toMatchObject({ value: null, changed: true });
  });

  it('preset: のマクロは preset の値に set を当てる', () => {
    const view = macroView(PRESET_MACRO, [{ address: at(PRESET_FILE, 'preset'), value: 'VS Code:編集:行をコピー' }]);
    expect(view.preset).toMatchObject({ value: 'VS Code:編集:行をコピー', saved: 'VS Code:編集:選択をコピー', changed: true });
    expect(macroView(MACRO, []).preset).toBeNull();
  });
});

describe('tapDanceView・comboView・shortcutView', () => {
  it('タップダンスの動作と tapping_term は同じ Address の最後の変更が効き、remove で空になる', () => {
    const view = tapDanceView(TAP_DANCE, [
      { address: at(TAP_DANCE_FILE, 'actions', 'on_double_tap'), value: 'Q' },
      { address: at(TAP_DANCE_FILE, 'actions', 'on_double_tap'), value: 'W' },
      { op: 'remove', address: at(TAP_DANCE_FILE, 'actions', 'on_hold') },
      { op: 'remove', address: at(TAP_DANCE_FILE, 'tapping_term') },
    ]);
    expect(view.actions.tap).toMatchObject({ text: 'Tab', changed: false });
    expect(view.actions.doubleTap).toMatchObject({ text: 'W', changed: true, saved: null });
    expect(view.actions.hold).toMatchObject({ text: '', changed: true });
    expect(view.tappingTerm).toMatchObject({ value: null, saved: 200, changed: true });
    // 保存済みと同じ値に戻せば印は消える
    expect(tapDanceView(TAP_DANCE, [{ address: at(TAP_DANCE_FILE, 'tapping_term'), value: 200 }]).tappingTerm.changed).toBe(false);
  });

  it('コンボの同時に押すキーの insert / remove と、そのあとの位置での set。出すキーは並びの外', () => {
    const view = comboView(COMBO, [
      { op: 'insert', address: at(COMBO_FILE, 'trigger_keys'), index: 2, value: 'E' },
      { op: 'remove', address: at(COMBO_FILE, 'trigger_keys', 0) },
      { address: at(COMBO_FILE, 'trigger_keys', 1), value: 'R' },
      { address: at(COMBO_FILE, 'output_key'), value: 'Escape' },
    ]);
    expect(view.triggers.keys.map((k) => [k.text, k.changed, k.address.path])).toEqual([
      ['W', false, ['trigger_keys', 0]],
      ['R', true, ['trigger_keys', 1]],
    ]);
    expect(view.triggers.restructured).toBe(true);
    expect(view.output).toMatchObject({ text: 'Escape', changed: true });
  });

  it('ショートカットは名前の行の値', () => {
    const view = shortcutView(SHORTCUTS[0]!, [
      { address: at(SHORTCUTS_FILE, 'shortcuts', '次のタブへ'), value: 'X' },
      { address: at(SHORTCUTS_FILE, 'shortcuts', '前のタブへ'), value: 'Command + [' },
    ]);
    expect(view.value).toMatchObject({ text: 'Command + [', changed: true });
  });

  it('effectivePending は pending がなければ（v0.1 のホスト）changes を使う', () => {
    const change = { address: at(COMBO_FILE, 'output_key'), value: 'A' };
    expect(effectivePending([change], undefined)).toEqual([change]);
    expect(effectivePending([change], [])).toEqual([]);
  });
});

describe('nameProblem', () => {
  it('空・前後の空白・重なる名前を断る（名前の変更で同じ名前は通す）', () => {
    expect(nameProblem('', [])).toBe('名前を入れてください');
    expect(nameProblem(' A', [])).toBe('名前の前後に空白は入れられません');
    expect(nameProblem('Tab Escape', ['Tab Escape'])).toBe('「Tab Escape」はもうあります');
    expect(nameProblem('Tab Escape', ['Tab Escape'], 'Tab Escape')).toBeUndefined();
    expect(nameProblem('新しい', ['Tab Escape'])).toBeUndefined();
  });
});

describe('注記（field: "note"）', () => {
  const tap = at(TAP_DANCE_FILE, 'actions', 'on_tap');
  const output = at(COMBO_FILE, 'output_key');

  it('注記は割り当てと別に畳む。行を消すと注記も消え、そのあとの割り当ての set では戻らない', () => {
    const noted = structuredClone(TAP_DANCE);
    noted.actions.tap.value = { ...noted.actions.tap.value!, note: '元の注記' };
    expect(tapDanceView(noted, []).actions.tap).toMatchObject({ text: 'Tab', note: '元の注記', changed: false, noteChanged: false });
    expect(tapDanceView(noted, [{ address: tap, value: '新しい注記', field: 'note' }]).actions.tap).toMatchObject({ text: 'Tab', changed: false, note: '新しい注記', noteChanged: true });
    expect(tapDanceView(noted, [{ op: 'remove', address: tap, field: 'note' }]).actions.tap).toMatchObject({ text: 'Tab', note: '', noteChanged: true });
    expect(tapDanceView(noted, [{ address: tap, value: 'Escape' }]).actions.tap).toMatchObject({ text: 'Escape', note: '元の注記', noteChanged: false });
    const removed: AnyChange[] = [{ op: 'remove', address: tap }, { address: tap, value: 'Escape' }];
    expect(tapDanceView(noted, removed).actions.tap).toMatchObject({ text: 'Escape', changed: true, note: '', noteChanged: true });
  });

  it('コンボの出すキーの注記。同時に押すキー（並びの要素）は注記を持たない', () => {
    const view = comboView(COMBO, [{ address: output, value: 'メモ', field: 'note' }]);
    expect(view.output).toMatchObject({ note: 'メモ', noteChanged: true });
    expect(view.triggers.keys.map((k) => k.note)).toEqual(['', '']);
  });
});
