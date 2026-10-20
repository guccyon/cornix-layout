import { describe, expect, it } from 'vitest';
import { PendingChanges, isAnyChange, isSequential, snapshotValueAt, type SavedValue } from '../../src/editor/pendingChanges';
import type { Address, AnyChange, ProfileSnapshot } from '../../src/protocol';

const tab: Address = { file: 'layers/0_base.yml', path: ['mapping', 'left_hand', 'row0', 'tab'] };
const q: Address = { file: 'layers/0_base.yml', path: ['mapping', 'left_hand', 'row0', 'Q'] };
const term: Address = { file: 'settings/qmk_settings.yaml', path: ['keyboard', 'tapping_term'] };
const macro = 'macros/00_bracket_pair.yml';
const sequence: Address = { file: macro, path: ['sequence'] };
const step0Key0: Address = { file: macro, path: ['sequence', 0, 'keys', 0] };
const description: Address = { file: macro, path: ['description'] };

/** 保存済みの値の表（Address の最後の名前と欄 → 値） */
function savedFrom(values: Record<string, string | number | null>): SavedValue {
  return (address, field) => {
    const key = `${String(address.path.at(-1))}${field === 'note' ? '#note' : ''}`;
    return key in values ? values[key]! : null;
  };
}

describe('PendingChanges', () => {
  const saved = savedFrom({ tab: "TapDance('Tab Escape')", Q: 'Q', tapping_term: 180, 'tab#note': null, description: '角括弧ペア' });

  it('並びの外の set は同じ Address の最後の値だけを、前の変更の位置に持つ', () => {
    const changes = new PendingChanges();
    changes.add({ address: tab, value: 'Escape' }, saved);
    changes.add({ address: q, value: 'A' }, saved);
    changes.add({ address: { ...tab, path: [...tab.path] }, value: 'NoKey' }, saved);
    expect(changes.list()).toEqual([
      { address: tab, value: 'NoKey' },
      { address: q, value: 'A' },
    ]);
  });

  it('書いていない位置の set のあとに同じ位置の remove が来たら、打ち消して持たない', () => {
    const empty: Address = { file: 'layers/1_symbols.yml', path: ['mapping', 'left_hand', 'row0', 'W'] };
    const changes = new PendingChanges();
    changes.add({ address: empty, value: 'A' }, saved);
    changes.add({ address: empty, value: 'メモ', field: 'note' }, saved);
    changes.add({ op: 'remove', address: empty }, saved);
    expect(changes.size).toBe(0);
  });

  it('書いていない位置の注記は割り当ての set のあとに並べ、割り当てを変え直しても順を崩さない', () => {
    const empty: Address = { file: 'layers/1_symbols.yml', path: ['mapping', 'left_hand', 'row0', 'W'] };
    const changes = new PendingChanges();
    changes.add({ address: empty, value: 'A' }, saved);
    changes.add({ address: empty, value: 'メモ', field: 'note' }, saved);
    changes.add({ address: empty, value: 'B' }, saved);
    expect(changes.list()).toEqual([
      { address: empty, value: 'B' },
      { address: empty, value: 'メモ', field: 'note' },
    ]);
    // 注記を先に書いても、割り当ては注記より前に入れる
    const other = new PendingChanges();
    other.add({ address: empty, value: 'メモ', field: 'note' }, saved);
    other.add({ address: empty, value: 'A' }, saved);
    expect(other.list().map((c) => ('field' in c ? c.field : undefined))).toEqual([undefined, 'note']);
  });

  it('保存済みの値と同じになったら持たない（書いていないものを消すのも同じ）', () => {
    const changes = new PendingChanges();
    changes.add({ address: q, value: 'A' }, saved);
    changes.add({ address: q, value: 'Q' }, saved);
    expect(changes.size).toBe(0);
    changes.add({ op: 'remove', address: tab, field: 'note' }, saved); // 注記を書いていない
    expect(changes.size).toBe(0);
  });

  it('注記（field: "note"）は割り当てと別の場所として畳む', () => {
    const changes = new PendingChanges();
    changes.add({ address: tab, value: 'Escape' }, saved);
    changes.add({ address: tab, value: 'メモ', field: 'note' }, saved);
    changes.add({ address: tab, value: 'メモ 2', field: 'note' }, saved);
    expect(changes.list()).toEqual([
      { address: tab, value: 'Escape' },
      { address: tab, value: 'メモ 2', field: 'note' },
    ]);
    expect(changes.pendingValue(tab, 'note')).toBe('メモ 2');
    expect(changes.plainSets()).toEqual([{ address: tab, value: 'Escape' }]);
  });

  it('行を消す remove は同じ行の変更を外し、そのあとの set は消したあとに書く変更として残す', () => {
    const changes = new PendingChanges();
    changes.add({ address: tab, value: 'Escape' }, saved);
    changes.add({ address: tab, value: 'メモ', field: 'note' }, saved);
    changes.add({ op: 'remove', address: tab }, saved);
    expect(changes.list()).toEqual([{ op: 'remove', address: tab }]);
    expect(changes.pendingValue(tab)).toBeNull();
    expect(changes.pendingValue(tab, 'note')).toBeNull();
    // 保存済みと同じ値を書き直しても、消した注記を戻さないように remove を残す
    changes.add({ address: tab, value: "TapDance('Tab Escape')" }, saved);
    expect(changes.list()).toEqual([
      { op: 'remove', address: tab },
      { address: tab, value: "TapDance('Tab Escape')" },
    ]);
    // もう一度消せば set は外れ、remove 1 つになる
    changes.add({ op: 'remove', address: tab }, saved);
    expect(changes.list()).toEqual([{ op: 'remove', address: tab }]);
  });

  it('並びを指す Change は畳まずに足した順のまま持つ', () => {
    const changes = new PendingChanges();
    const ops: AnyChange[] = [
      { op: 'insert', address: sequence, index: 0, value: { action: 'tap', keys: ['A'] } },
      { address: step0Key0, value: 'B' },
      { address: description, value: '新しい説明' },
      { address: step0Key0, value: 'C' },
      { op: 'move', address: sequence, from: 0, to: 1 },
      { op: 'remove', address: { file: macro, path: ['sequence', 1] } },
    ];
    for (const op of ops) changes.add(op, saved);
    expect(changes.list()).toEqual(ops);
    // v0.1 の changes には並びの外の set だけ
    expect(changes.plainSets()).toEqual([{ address: description, value: '新しい説明' }]);
    // 並びの外の set は、並びの変更をまたいで畳む（並びの位置とは関係しないため）
    changes.add({ address: description, value: '角括弧ペア' }, saved);
    expect(changes.list()).toEqual(ops.filter((op) => op.address !== description));
  });

  it('assign・discard・remove で元に戻す・当て直す', () => {
    const changes = new PendingChanges();
    changes.assign(term, 200, 180);
    expect(changes.get(term)?.value).toBe(200);
    changes.assign(term, 180, 180);
    expect(changes.size).toBe(0);
    changes.add({ address: tab, value: 'x', field: 'note' }, saved);
    changes.add({ address: tab, value: 'Escape' }, saved);
    changes.discard(tab, 'note');
    expect(changes.list()).toEqual([{ address: tab, value: 'Escape' }]);
    const insert: AnyChange = { op: 'insert', address: sequence, index: 1, value: { action: 'delay', duration: 100 } };
    changes.add(insert, saved);
    changes.remove(insert);
    expect(changes.list()).toEqual([{ address: tab, value: 'Escape' }]);
  });

  it('並びは変えるたびに新しい配列になる（元に戻すが配列そのもので見分ける）', () => {
    const changes = new PendingChanges();
    const empty = changes.current();
    changes.add({ address: q, value: 'A' }, saved);
    const after = changes.current();
    expect(after).not.toBe(empty);
    changes.restore(empty);
    expect(changes.size).toBe(0);
    changes.restore(after);
    expect(changes.current()).toBe(after);
  });

  it('baseVersions は変更のあるファイルだけ（版がなければ null）', () => {
    const changes = new PendingChanges();
    changes.add({ address: tab, value: 'Escape' }, saved);
    changes.add({ address: term, value: 200 }, saved);
    changes.add({ op: 'move', address: sequence, from: 0, to: 1 }, saved);
    expect(changes.baseVersions({ 'layers/0_base.yml': 'sha256:aa', 'metadata.yaml': 'sha256:bb', [macro]: 'sha256:cc' })).toEqual({
      'layers/0_base.yml': 'sha256:aa',
      'settings/qmk_settings.yaml': null,
      [macro]: 'sha256:cc',
    });
  });
});

describe('isSequential と isAnyChange', () => {
  it('insert・move と、道筋に番号のある set・remove が並びを指す', () => {
    expect(isSequential({ op: 'insert', address: sequence, index: 0, value: 'A' })).toBe(true);
    expect(isSequential({ op: 'move', address: sequence, from: 0, to: 1 })).toBe(true);
    expect(isSequential({ address: step0Key0, value: 'A' })).toBe(true);
    expect(isSequential({ op: 'remove', address: { file: 'combos/00_x.yml', path: ['trigger_keys', 1] } })).toBe(true);
    expect(isSequential({ op: 'remove', address: tab })).toBe(false);
    expect(isSequential({ address: description, value: 'x' })).toBe(false);
  });

  it('形の違うメッセージは受け付けない', () => {
    expect(isAnyChange({ address: tab, value: 'A' })).toBe(true);
    expect(isAnyChange({ op: 'remove', address: tab, field: 'note' })).toBe(true);
    expect(isAnyChange({ op: 'insert', address: sequence, index: 0, value: { action: 'tap', keys: ['A'] } })).toBe(true);
    expect(isAnyChange({ op: 'move', address: sequence, from: 0, to: 1 })).toBe(true);
    expect(isAnyChange({ op: 'insert', address: sequence, index: 0.5, value: 'A' })).toBe(false);
    expect(isAnyChange({ op: 'rename', address: tab })).toBe(false);
    expect(isAnyChange({ address: { file: 1, path: [] }, value: 'A' })).toBe(false);
    expect(isAnyChange({ address: tab, value: null })).toBe(false);
    expect(isAnyChange({ address: tab, value: 'A', field: 'other' })).toBe(false);
  });
});

describe('snapshotValueAt', () => {
  it('キーは表記、QMK 設定は値、割り当てのない位置は null、ない Address は undefined', async () => {
    const { LAYERS, SETTINGS } = await import('../fake-server/fixtures');
    const snapshot = { layers: LAYERS, settings: SETTINGS } as unknown as ProfileSnapshot;
    expect(snapshotValueAt(snapshot, { file: 'layers/0_base.yml', path: ['mapping', 'left_hand', 'thumb_keys', 'middle'] })).toBe('LT1(Space)');
    expect(snapshotValueAt(snapshot, { file: 'layers/0_base.yml', path: ['mapping', 'encoders', 'left', 'push'] })).toBe('Mute');
    expect(snapshotValueAt(snapshot, { file: 'layers/1_symbols.yml', path: ['mapping', 'left_hand', 'row0', 'W'] })).toBeNull();
    expect(snapshotValueAt(snapshot, term)).toBe(180);
    expect(snapshotValueAt(snapshot, { file: 'layers/9.yml', path: ['x'] })).toBeUndefined();
  });

  it('注記と、マクロ・タップダンス・コンボ・ショートカットの中身', async () => {
    const data = await import('../fake-server/fixtures');
    const snapshot = {
      layers: data.LAYERS,
      settings: data.SETTINGS,
      macros: data.MACROS,
      tapDances: data.TAP_DANCES,
      combos: data.COMBOS,
      shortcuts: data.SHORTCUTS,
    } as unknown as ProfileSnapshot;
    const thumb: Address = { file: 'layers/0_base.yml', path: ['mapping', 'left_hand', 'thumb_keys', 'left'] };
    expect(snapshotValueAt(snapshot, thumb, 'note')).toBe('タップで英数、押している間は Command');
    expect(snapshotValueAt(snapshot, tab, 'note')).toBeNull();
    expect(snapshotValueAt(snapshot, description)).toBe('角括弧ペア');
    expect(snapshotValueAt(snapshot, step0Key0)).toBe('LBracket');
    expect(snapshotValueAt(snapshot, { file: 'tap_dance/04_tab_escape.yml', path: ['actions', 'on_hold'] })).toBe('Escape');
    expect(snapshotValueAt(snapshot, { file: 'tap_dance/04_tab_escape.yml', path: ['tapping_term'] })).toBe(200);
    expect(snapshotValueAt(snapshot, { file: 'combos/00_left_bracket.yml', path: ['output_key'] })).toBe('LBracket');
    expect(snapshotValueAt(snapshot, { file: 'shortcuts.yaml', path: ['shortcuts', '前のタブへ'] })).toBe('Command + Shift + [');
  });
});
