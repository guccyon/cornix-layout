// 画面に描くものを snapshot から組み立てる（DOM に依存しない）。
// 1 つのレイヤーの「欄」（キー 1 つ、エンコーダの操作 1 つ）を Slot として並べ、未保存の変更と検証の結果を重ねる。
import type {
  Address,
  CandidateContext,
  Change,
  Diagnostic,
  Hand,
  KeyValue,
  LayerSnapshot,
  PositionMapEntry,
  ProfileSnapshot,
} from '../protocol';
import { addressKey } from '../editor/pendingChanges';

export type EncoderOp = 'push' | 'ccw' | 'cw';

export type Slot = {
  /** addressKey(address) */
  id: string;
  address: Address;
  context: CandidateContext;
  /** 欄の名前（position_map の記号、エンコーダは「押し込み」など） */
  label: string;
  hand: Hand;
  /** キーのときの論理位置とグループ */
  key?: { row: number; col: number; group: string };
  encoder?: EncoderOp;
  /** 保存済みの値（割り当てがなければ null） */
  saved: KeyValue | null;
};

export const ENCODER_OPS: { op: EncoderOp; label: string }[] = [
  { op: 'push', label: '押し込み' },
  { op: 'ccw', label: '左回し' },
  { op: 'cw', label: '右回し' },
];

export const HAND_LABEL: Record<Hand, string> = { left: '左手', right: '右手' };

/** position_map のグループの見出し */
export function groupLabel(group: string): string {
  const row = /^row(\d)$/.exec(group);
  if (row?.[1]) return `${Number(row[1]) + 1} 段目`;
  if (group === 'thumb_keys') return '親指';
  return group;
}

/** Address を Map のキーにする（未保存の変更と同じ形） */
export { addressKey };

/** レイヤー 1 つの欄。キーは position_map の順（手 → グループ → 列）、そのあとにエンコーダ（左 → 右） */
export function layerSlots(layer: LayerSnapshot, positionMap: PositionMapEntry[]): Slot[] {
  const slots: Slot[] = [];
  const keyAt = new Map(layer.keys.map((key) => [`${key.hand}/${key.row}/${key.col}`, key]));
  for (const entry of positionMap) {
    const key = keyAt.get(`${entry.hand}/${entry.row}/${entry.col}`);
    if (!key) continue;
    slots.push({
      id: addressKey(key.address),
      address: key.address,
      context: 'layerKey',
      label: entry.symbol,
      hand: entry.hand,
      key: { row: entry.row, col: entry.col, group: entry.group },
      saved: key.value,
    });
  }
  for (const hand of ['left', 'right'] as const) {
    const binding = layer.encoders[hand];
    for (const { op, label } of ENCODER_OPS) {
      const action = binding[op];
      slots.push({
        id: addressKey(action.address),
        address: action.address,
        context: 'encoder',
        label,
        hand,
        encoder: op,
        saved: action.value,
      });
    }
  }
  return slots;
}

/** 欄の今の表記（未保存の変更があればその値、なければ保存済みの表記、どちらもなければ空） */
export function currentText(slot: Slot, changes: ReadonlyMap<string, Change>): string {
  const change = changes.get(slot.id);
  if (change) return String(change.value);
  return slot.saved?.text ?? '';
}

export function changeMap(changes: Change[]): Map<string, Change> {
  return new Map(changes.map((change) => [addressKey(change.address), change]));
}

/** snapshot の検証の結果を Address ごとに分ける（address のないものは files に） */
export function diagnosticsByAddress(snapshot: ProfileSnapshot): { byAddress: Map<string, Diagnostic[]>; general: Diagnostic[] } {
  const byAddress = new Map<string, Diagnostic[]>();
  const general: Diagnostic[] = [];
  for (const diagnostic of snapshot.diagnostics) {
    if (!diagnostic.address) {
      general.push(diagnostic);
      continue;
    }
    const key = addressKey(diagnostic.address);
    byAddress.set(key, [...(byAddress.get(key) ?? []), diagnostic]);
  }
  return { byAddress, general };
}

/** いちばん重いもの（error があれば error） */
export function severityOf(diagnostics: readonly Diagnostic[]): 'error' | 'warning' | null {
  if (diagnostics.some((d) => d.severity === 'error')) return 'error';
  if (diagnostics.length > 0) return 'warning';
  return null;
}

/** レイヤーの見出し（"0 Base"） */
export function layerTitle(layer: { index: number; name: string }): string {
  return `${layer.index} ${layer.name}`;
}
