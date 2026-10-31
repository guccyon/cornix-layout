// v0.5 の番号の決まり（src/itemIndex.ts。protocol.md の 15）
import { describe, expect, it } from 'vitest';
import { arrangeItems, effectiveIndex, indexAddress, indexChanged, isPendingItemEdit, nextIndex } from '../../src/itemIndex';
import type { AnyChange } from '../../src/protocol';

const set = (file: string, value: number): AnyChange => ({ address: indexAddress(file), value });
const remove = (file: string): AnyChange => ({ op: 'remove', address: indexAddress(file) });

describe('effectiveIndex', () => {
  it('そのファイルの ["index"] を指す最後の set / remove が効く', () => {
    expect(effectiveIndex('a.yml', 1, [])).toBe(1);
    expect(effectiveIndex('a.yml', null, [set('a.yml', 3)])).toBe(3);
    expect(effectiveIndex('a.yml', 1, [set('a.yml', 3), remove('a.yml')])).toBeNull();
    expect(effectiveIndex('a.yml', null, [remove('a.yml'), set('a.yml', 2)])).toBe(2);
    expect(effectiveIndex('a.yml', 1, [set('b.yml', 3), { address: { file: 'a.yml', path: ['description'] }, value: 'x' }])).toBe(1);
  });

  it('保存済みと同じ番号に戻したら変えていない', () => {
    expect(indexChanged('a.yml', 1, [set('a.yml', 3)])).toBe(true);
    expect(indexChanged('a.yml', 1, [set('a.yml', 3), set('a.yml', 1)])).toBe(false);
  });
});

describe('arrangeItems', () => {
  it('未保存の番号で分け直し、使っているものは番号の順、未使用は渡した順', () => {
    const items = [
      { file: 'l/0.yml', index: 0 },
      { file: 'l/1.yml', index: 1 },
      { file: 'l/ipad.yml', index: null },
      { file: 'l/old.yml', index: null },
    ];
    const { used, unused } = arrangeItems(items, [set('l/ipad.yml', 2), set('l/0.yml', 1), set('l/1.yml', 0), remove('l/1.yml')]);
    expect(used.map((i) => [i.file, i.index])).toEqual([
      ['l/0.yml', 1],
      ['l/ipad.yml', 2],
    ]);
    expect(unused.map((i) => i.file)).toEqual(['l/1.yml', 'l/old.yml']);
  });
});

describe('nextIndex', () => {
  it('使っているいちばん大きい番号の次。上限なら空いている最小、空きがなければ null', () => {
    expect(nextIndex(10, [])).toBe(0);
    expect(nextIndex(10, [0, 1, 2])).toBe(3);
    expect(nextIndex(10, [0, 5])).toBe(6);
    expect(nextIndex(10, [0, 1, 9])).toBe(2);
    expect(nextIndex(10, [0, 1, 2, 3, 4, 5, 6, 7, 8, 9])).toBeNull();
    expect(nextIndex(32, [9])).toBe(10);
  });
});

describe('isPendingItemEdit', () => {
  it('番号の操作とショートカットの追加だけが未保存に積む操作', () => {
    expect(isPendingItemEdit({ op: 'use', kind: 'layer', file: 'l.yml' })).toBe(true);
    expect(isPendingItemEdit({ op: 'unuse', kind: 'macro', file: 'm.yml' })).toBe(true);
    expect(isPendingItemEdit({ op: 'setIndex', kind: 'combo', file: 'c.yml', index: 2 })).toBe(true);
    expect(isPendingItemEdit({ op: 'reorder', kind: 'macro', files: ['a.yml', 'b.yml'] })).toBe(true);
    expect(isPendingItemEdit({ op: 'create', kind: 'shortcut', name: 'a', value: 'KC_A' })).toBe(true);
    expect(isPendingItemEdit({ op: 'create', kind: 'macro', name: 'a' })).toBe(false);
    expect(isPendingItemEdit({ op: 'delete', kind: 'layer', name: 'a', file: 'l.yml' })).toBe(false);
  });
});
