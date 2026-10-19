import { describe, expect, it } from 'vitest';
import { PendingChanges } from '../../src/editor/pendingChanges';
import type { Address } from '../../src/protocol';

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

  it('set が返す前の値で元に戻せる', () => {
    const changes = new PendingChanges();
    const first = changes.set({ address: tab, value: 'Escape' });
    const second = changes.set({ address: tab, value: 'NoKey' });
    changes.restore(tab, second);
    expect(changes.get(tab)?.value).toBe('Escape');
    changes.restore(tab, first);
    expect(changes.size).toBe(0);
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
