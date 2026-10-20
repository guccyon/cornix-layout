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
  TapDanceAction,
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

/** エンコーダの操作。図（上から）と下のレイヤーの欄の並びもこの順（回す向きを上下に分け、押し込みをまん中に） */
export const ENCODER_OPS: { op: EncoderOp; label: string }[] = [
  { op: 'ccw', label: '左回し' },
  { op: 'push', label: '押し込み' },
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

/** 欄の名前（読み上げ・入力欄の名前・図のキーで同じもの。「左手 tab」「左手 エンコーダの押し込み」） */
export function slotLabel(slot: Slot): string {
  return `${HAND_LABEL[slot.hand]} ${slot.encoder ? `エンコーダの${slot.label}` : slot.label}`;
}

/** 図のキーの右上の印。マクロ・タップダンス・自分のショートカットを、ほかのキーと見分けるため */
export type KeyMark = { kind: 'macro' | 'tapDance' | 'shortcut'; text: string; meaning: string };

const MARKS: Record<KeyMark['kind'], KeyMark> = {
  macro: { kind: 'macro', text: 'M', meaning: 'マクロ' },
  tapDance: { kind: 'tapDance', text: 'TD', meaning: 'タップダンス' },
  shortcut: { kind: 'shortcut', text: '★', meaning: '自分のショートカット' },
};

export const TAP_DANCE_ACTION_LABEL: Record<TapDanceAction['action'], string> = {
  tap: 'タップ',
  hold: 'ホールド',
  doubleTap: 'ダブルタップ',
  tapHold: 'タップホールド',
};

/** タップダンスを窓に分けて描くときの動作（割り当てのある動作が 1 つ以上のとき。サーバーが actions を返さなければ null） */
export function tapDanceWindows(value: KeyValue | null | undefined): TapDanceAction[] | null {
  if (value?.kind !== 'tapDance') return null;
  const actions = value.display.actions ?? [];
  return actions.length >= 1 ? actions : null;
}

/**
 * 窓に描く文字。ほかの窓と同じ語（空白区切り）で始まる文字は、ほかの窓といちばん長く重なる先頭の語を落とす
 * （「⌘V」「Copy Selected」「Copy Current Word」「Copy Current Line」→「⌘V」「Selected」「Word」「Line」）。
 * 落とすと空になるときと、ほかの窓と重ならないときは元のまま。説明と読み上げは元の文字を使う
 */
export function windowLabels(actions: readonly TapDanceAction[]): string[] {
  const words = actions.map((a) => a.label.split(' '));
  return words.map((own, i) => {
    let shared = 0;
    words.forEach((other, j) => {
      if (i === j) return;
      let n = 0;
      while (n < own.length && n < other.length && own[n] === other[n]) n++;
      shared = Math.max(shared, n);
    });
    return shared > 0 && shared < own.length ? own.slice(shared).join(' ') : actions[i]!.label;
  });
}

/**
 * 値に付ける印（なければ null）。自分のショートカット（Shortcut(...)）は中身の種類より先に ★。
 * アイコンのあるもの（同梱のショートカット・preset: のマクロ）はアイコンで、窓に分けて描くタップダンスは窓で分かるので印を付けない
 * （TD の印は、定義が見つからず動作の分からないタップダンスだけ）
 */
export function keyMark(value: KeyValue | null | undefined): KeyMark | null {
  if (!value || value.icon) return null;
  if (value.origin === 'shortcut') return MARKS.shortcut;
  if (value.kind === 'macro') return MARKS.macro;
  if (value.kind === 'tapDance' && !tapDanceWindows(value)) return MARKS.tapDance;
  return null;
}

/**
 * 図の印の説明（説明の吹き出しに出す 1 行。なければ undefined）。窓に分けたタップダンスは、吹き出しの「タップ: Tab」などの行と
 * 重なるので出さない（窓の中身は読み上げの keyAccessibleName が伝える）
 */
export function keyFaceNote(value: KeyValue | null | undefined): string | undefined {
  const mark = keyMark(value);
  return mark ? `印「${mark.text}」: ${mark.meaning}` : undefined;
}

/** 図のキーの読み上げ（「左手 tab: タップ Space、ホールド L1」。未割り当て・エラー・警告も入れる） */
export function keyAccessibleName(
  slot: Slot,
  text: string,
  value: KeyValue | null | undefined,
  diagnostics: readonly Diagnostic[],
  layerNames: ReadonlyMap<number, string> = new Map(),
): string {
  let content: string;
  if (text === '') content = '割り当てなし';
  else if (value?.display.tap && value.display.hold && (value.kind === 'layerTap' || value.kind === 'modTap'))
    content = `タップ ${value.display.tap}、ホールド ${value.display.hold}`;
  // レイヤー操作は図では帯に番号だけなので、読み上げは表記の形とレイヤーの名前で（MO(3)（Function Keys））
  else if (value?.kind === 'layerAction' || value?.kind === 'layerMod') {
    const index = /^L(\d+)$/.exec(value.display.hold ?? '')?.[1];
    const name = index === undefined ? undefined : layerNames.get(Number(index));
    content = name ? `${value.canonical}（${name}）` : value.canonical;
  }
  else content = value?.display.label || text;
  const mark = keyMark(value);
  if (mark) content = `${mark.meaning} ${content}`;
  const windows = tapDanceWindows(value);
  if (windows) content = `タップダンス ${content}（${windows.map((a) => `${TAP_DANCE_ACTION_LABEL[a.action]} ${a.label}`).join('、')}）`;
  const problems = diagnostics.map((d) => `${d.severity === 'error' ? 'エラー' : '警告'} ${d.message}`);
  return [`${slotLabel(slot)}: ${content}`, ...problems].join('。');
}

/**
 * 図と欄を作り直すかを決める形。position_map とレイヤーの並び・ファイル・各欄の Address が同じなら作り直さず、値だけ描き直す
 * （保存や外での変更で files の版・diagnostics・値が変わっても、打っている欄のフォーカスと文字を残すため）
 */
export function structureKey(snapshot: ProfileSnapshot): string {
  return JSON.stringify({
    status: snapshot.status,
    positionMap: snapshot.positionMap,
    layers: snapshot.layers.map((layer) => ({
      index: layer.index,
      file: layer.file,
      keys: layer.keys.map((key) => [key.hand, key.row, key.col, addressKey(key.address)]),
      encoders: (['left', 'right'] as const).map((hand) => ENCODER_OPS.map(({ op }) => addressKey(layer.encoders[hand][op].address))),
    })),
  });
}
