import { describe, expect, it } from 'vitest';
import { PendingChanges, snapshotValueAt } from '../../src/editor/pendingChanges';
import type { Address, ProfileSnapshot } from '../../src/protocol';

const tab: Address = { file: 'layers/0_base.yml', path: ['mapping', 'left_hand', 'row0', 'tab'] };
const q: Address = { file: 'layers/0_base.yml', path: ['mapping', 'left_hand', 'row0', 'Q'] };
const term: Address = { file: 'settings/qmk_settings.yaml', path: ['keyboard', 'tapping_term'] };

describe('PendingChanges', () => {
  it('同じ Address は最後の値だけを持つ', () => {
    const changes = new PendingChanges();
    changes.set({ address: tab, value: 'Escape' });
    changes.set({ address: q, value: 'A' });
    changes.set({ address: { ...tab, path: [...tab.path] }, value: 'NoKey' });
    expect(changes.list()).toEqual([
      { address: q, value: 'A' },
      { address: tab, value: 'NoKey' },
    ]);
  });

  it('assign は保存済みの値と同じか null なら変更から外す', () => {
    const changes = new PendingChanges();
    changes.assign(tab, 'Escape', 'Tab');
    expect(changes.get(tab)?.value).toBe('Escape');
    changes.assign(tab, 'Tab', 'Tab');
    expect(changes.size).toBe(0);
    changes.assign(term, 200, 180);
    changes.assign(term, null, 180);
    expect(changes.size).toBe(0);
  });

  it('前の値と新しい値で戻すと、保存（snapshot が変わる）のあとに戻しても食い違わない', () => {
    // profileDocument.ts の applyChange と同じ手順: before = 未保存の値 ?? 保存済みの値
    const changes = new PendingChanges();
    let saved: string = 'Tab';
    const before = changes.get(tab)?.value ?? saved;
    changes.assign(tab, 'Escape', saved);
    const undo = () => changes.assign(tab, before, saved);
    // 保存した: 保存済みの値が Escape になり、未保存の変更は空
    saved = 'Escape';
    changes.clear();
    undo();
    expect(changes.list()).toEqual([{ address: tab, value: 'Tab' }]); // ディスクの Escape に対する変更として残る
  });

  it('baseVersions は変更のあるファイルだけ（版がなければ null）', () => {
    const changes = new PendingChanges();
    changes.set({ address: tab, value: 'Escape' });
    changes.set({ address: term, value: 200 });
    expect(changes.baseVersions({ 'layers/0_base.yml': 'sha256:aa', 'metadata.yaml': 'sha256:bb' })).toEqual({
      'layers/0_base.yml': 'sha256:aa',
      'settings/qmk_settings.yaml': null,
    });
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
});
