// v0.3: コンボを図で見せる（tasks-v0.3.md の決めたことの 1）。DOM に依存しない。
// トリガーは位置ではなくキーコードなので、今のレイヤーでそのキーコードを割り当てた位置を探す。KC_TRNS の位置はレイヤー 0 の値で見る
// （サーバーの reachable の判定と同じ。protocol.md の 13.2）。値は KeyValue で比べる（16bit 値があればそれ、なければ正規形）。
import type { KeyValue } from '../protocol';

/** 2 つの値が同じキーか（16bit 値が両方にあればそれで、なければ正規形で比べる） */
export function sameKey(a: KeyValue, b: KeyValue): boolean {
  if (a.code !== null && b.code !== null) return a.code === b.code;
  return a.canonical === b.canonical;
}

/** トリガーとして探す値（書いていない・NoKey・まだ解釈のないもの・読めないものは探さない） */
export function triggerKeys(values: readonly (KeyValue | null | undefined)[]): KeyValue[] {
  return values.filter((value): value is KeyValue => !!value && value.kind !== 'noKey' && value.kind !== 'transparent');
}

/** 図で比べる値: KC_TRNS ならレイヤー 0 の同じ位置の値（base。なければ null） */
export function effectiveKey(value: KeyValue | null | undefined, base: KeyValue | null | undefined): KeyValue | null {
  if (!value) return null;
  if (value.kind === 'transparent') return base && base.kind !== 'transparent' && base.kind !== 'noKey' ? base : null;
  return value;
}

/** トリガーのキーを割り当てた欄の id（keys は欄の id と、比べる値。effectiveKey を通したもの） */
export function comboTargets(keys: Iterable<readonly [string, KeyValue | null]>, triggers: readonly KeyValue[]): Set<string> {
  const targets = new Set<string>();
  if (triggers.length === 0) return targets;
  for (const [id, value] of keys) {
    if (value && triggers.some((trigger) => sameKey(value, trigger))) targets.add(id);
  }
  return targets;
}
