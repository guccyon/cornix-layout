// v0.5: 番号（index:）の決まり（protocol.md の 15）。取り出す・未使用にする・番号の変更は未保存の変更（`["index"]` の set / remove）に積むので、
// 今どの項目がどの番号かは snapshot（保存済み）に未保存の変更を当てて決める。ホスト・画面・偽のサーバーが同じ規則で使う。vscode に依存しない。
import type { Address, AnyChange, ComboSnapshot, IndexedKind, ItemEdit, LayerSnapshot, MacroSnapshot, ProfileSnapshot, TapDanceSnapshot, Unused } from './protocol';

/** 番号の数（0〜上限 - 1）。Cornix の大きさ（Domain::Capabilities::CORNIX） */
export const INDEX_LIMITS: Record<IndexedKind, number> = { layer: 10, macro: 32, tapDance: 32, combo: 32 };

/** 番号を書く場所 */
export function indexAddress(file: string): Address {
  return { file, path: ['index'] };
}

function isIndexChange(change: AnyChange, file: string): boolean {
  return change.address.file === file && change.address.path.length === 1 && change.address.path[0] === 'index';
}

/** 未保存の変更を当てたあとの番号（null は未使用）。そのファイルの `["index"]` を指す最後の set / remove が効く */
export function effectiveIndex(file: string, saved: number | null, pending: readonly AnyChange[]): number | null {
  let index = saved;
  for (const change of pending) {
    if (!isIndexChange(change, file)) continue;
    if (change.op === 'remove') index = null;
    else if ((change.op === undefined || change.op === 'set') && typeof change.value === 'number') index = change.value;
  }
  return index;
}

/** そのファイルの番号を未保存の変更で変えているか（保存済みと同じ番号に戻したものは変えていない） */
export function indexChanged(file: string, saved: number | null, pending: readonly AnyChange[]): boolean {
  return effectiveIndex(file, saved, pending) !== saved;
}

type Indexed = { file: string; index: number | null };

/** 使っている項目と未使用の項目を、未保存の変更を当てた番号で分け直す。使っているものは番号の順、未使用は渡した順（ファイルの順） */
export function arrangeItems<T extends Indexed>(items: readonly T[], pending: readonly AnyChange[]): { used: (T & { index: number })[]; unused: (T & { index: null })[] } {
  const used: (T & { index: number })[] = [];
  const unused: (T & { index: null })[] = [];
  for (const item of items) {
    const index = effectiveIndex(item.file, item.index, pending);
    if (index === null) unused.push({ ...item, index });
    else used.push({ ...item, index });
  }
  used.sort((a, b) => a.index - b.index);
  return { used, unused };
}

/** 種類ごとの項目（使っているものと未使用のもの） */
export type IndexedItemOf = {
  layer: LayerSnapshot | Unused<LayerSnapshot>;
  macro: MacroSnapshot | Unused<MacroSnapshot>;
  tapDance: TapDanceSnapshot | Unused<TapDanceSnapshot>;
  combo: ComboSnapshot | Unused<ComboSnapshot>;
};

/** snapshot のその種類の項目（使っているもの・未使用のものの順。保存済みの番号のまま。arrangeItems に渡す） */
export function snapshotItems<K extends IndexedKind>(snapshot: ProfileSnapshot, kind: K): IndexedItemOf[K][] {
  const unused = snapshot.unused;
  const lists: { [P in IndexedKind]: IndexedItemOf[P][] } = {
    layer: [...snapshot.layers, ...(unused?.layers ?? [])],
    macro: [...(snapshot.macros ?? []), ...(unused?.macros ?? [])],
    tapDance: [...(snapshot.tapDances ?? []), ...(unused?.tapDances ?? [])],
    combo: [...(snapshot.combos ?? []), ...(unused?.combos ?? [])],
  };
  return lists[kind];
}

/**
 * 取り出したときの番号（protocol.md の 15.3 の use）: 使っているいちばん大きい番号の次。それが上限なら空いているいちばん小さい番号。
 * 何も使っていなければ 0、空きがなければ null
 */
export function nextIndex(kind: IndexedKind, usedIndexes: readonly number[]): number | null {
  const limit = INDEX_LIMITS[kind];
  if (usedIndexes.length === 0) return 0;
  const last = Math.max(...usedIndexes);
  if (last + 1 < limit) return last + 1;
  for (let index = 0; index < limit; index++) if (!usedIndexes.includes(index)) return index;
  return null;
}

/** 未保存の変更に積む項目の操作か（ホストはすぐ書かずに planItemEdit の changes を積む。protocol.md の 15.3） */
export function isPendingItemEdit(edit: ItemEdit): boolean {
  return edit.op === 'use' || edit.op === 'unuse' || edit.op === 'setIndex' || edit.op === 'reorder' || (edit.op === 'create' && edit.kind === 'shortcut');
}
