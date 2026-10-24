// 画面に描くものを snapshot から組み立てる（DOM に依存しない）。
// 1 つのレイヤーの「欄」（キー 1 つ、エンコーダの操作 1 つ）を Slot として並べ、未保存の変更と検証の結果を重ねる。
import type {
  Address,
  AnyChange,
  CandidateContext,
  Change,
  Diagnostic,
  Hand,
  KeyValue,
  LayerKey,
  LayerSnapshot,
  TapDanceAction,
  PositionMapEntry,
  ProfileSnapshot,
  RemoveChange,
  Unused,
} from '../protocol';
import { addressKey } from '../editor/pendingChanges';
import { arrangeItems, indexChanged, nextIndex, snapshotItems } from '../itemIndex';

export type EncoderOp = 'push' | 'ccw' | 'cw';

export type Slot = {
  /** addressKey(address) */
  id: string;
  address: Address;
  context: CandidateContext;
  /** 欄の名前（position_map の記号、エンコーダは「押し込み」など） */
  label: string;
  hand: Hand;
  /** キーのときの論理位置とグループ。positionAddress は位置の名前を書いている場所（v0.2 のサーバーだけ。なければ名前を変えられない） */
  key?: { row: number; col: number; group: string; positionAddress?: Address };
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
      key: { row: entry.row, col: entry.col, group: entry.group, ...(entry.address ? { positionAddress: entry.address } : {}) },
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

/**
 * 未保存の変更を欄ごとに畳んだもの。values は割り当て（null は消した）、notes は注記（null は消した）。
 * 並び（insert / move）の変更はレイヤーの欄には来ないので無視する
 */
export type SlotEdits = { values: Map<string, string | null>; notes: Map<string, string | null> };

/** 未保存の変更（当てる順）を欄ごとに畳む。行を消す remove は注記も消す */
export function slotEdits(list: readonly AnyChange[]): SlotEdits {
  const values = new Map<string, string | null>();
  const notes = new Map<string, string | null>();
  for (const change of list) {
    const id = addressKey(change.address);
    if (change.op === undefined || change.op === 'set') {
      if (change.field === 'note') notes.set(id, String(change.value));
      else values.set(id, String(change.value));
    } else if (change.op === 'remove') {
      if (change.field === 'note') notes.set(id, null);
      else {
        values.set(id, null);
        notes.set(id, null);
      }
    }
  }
  return { values, notes };
}

/** 欄の今の表記（未保存の変更があればその値、消したなら空、なければ保存済みの表記、どれもなければ空） */
export function currentText(slot: Pick<Slot, 'id' | 'saved'>, edits: SlotEdits): string {
  if (edits.values.has(slot.id)) return edits.values.get(slot.id) ?? '';
  return slot.saved?.text ?? '';
}

/** 欄の今の注記（なければ空） */
export function currentNote(slot: Slot, edits: SlotEdits): string {
  if (edits.notes.has(slot.id)) return edits.notes.get(slot.id) ?? '';
  return slot.saved?.note ?? '';
}

/** 割り当てか注記に未保存の変更がある */
export function slotChanged(slot: Slot, edits: SlotEdits): boolean {
  return edits.values.has(slot.id) || edits.notes.has(slot.id);
}

/** 割り当てに未保存の変更がある（解釈を聞き直すのはこちらだけ） */
export function valueChanged(slot: Pick<Slot, 'id'>, edits: SlotEdits): boolean {
  return edits.values.has(slot.id);
}

/**
 * 未保存の変更の並びに 1 つ足す（ホストからの snapshot を待たずに描くため。ホストの pending が来たら置き換わる）。
 * - set: 同じ Address・同じ field の前の set は外す。保存済みと同じ値で、前に行を消していなければ足さない
 * - remove: 同じ Address の前の set（field が同じもの。行を消すなら割り当ても注記も）を外す。保存済みに何もなければ足さない
 */
export function addPending(list: readonly AnyChange[], change: Change | RemoveChange, saved: KeyValue | null): AnyChange[] {
  const id = addressKey(change.address);
  const field = change.field ?? 'key';
  const removingLine = change.op === 'remove' && field === 'key';
  const at = (c: AnyChange) => addressKey(c.address) === id;
  const isSet = (c: AnyChange) => c.op === undefined || c.op === 'set';
  const fieldOf = (c: AnyChange) => (c.op === undefined || c.op === 'set' || c.op === 'remove' ? (c.field ?? 'key') : 'key');
  const result = list.filter((c) => !(at(c) && isSet(c) && (removingLine || fieldOf(c) === field)));
  const lineRemoved = result.some((c) => at(c) && c.op === 'remove' && fieldOf(c) === 'key');
  if (change.op === 'remove') {
    const savedValue = field === 'note' ? saved?.note : saved?.text;
    if (savedValue === undefined || lineRemoved) return result;
    if (result.some((c) => at(c) && c.op === 'remove' && fieldOf(c) === field)) return result;
    return [...result, change];
  }
  const savedValue = field === 'note' ? (saved?.note ?? '') : (saved?.text ?? '');
  if (!lineRemoved && String(change.value) === savedValue) return result;
  return [...result, change];
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

/** v0.4: そのレイヤーのファイルの検証の問題（保存済みの中身。レイヤーのタブの点に使う） */
export function layerProblems(snapshot: ProfileSnapshot, file: string): Diagnostic[] {
  return snapshot.diagnostics.filter((d) => (d.address?.file ?? d.file) === file);
}

/** タブのツールチップの文（「警告 1 件: レイヤー 8 が定義されていません」。3 件を超えたら「ほか N 件」） */
export function problemSummary(problems: readonly Diagnostic[], max = 3): string {
  const errors = problems.filter((d) => d.severity === 'error').length;
  const warnings = problems.length - errors;
  const head = [errors > 0 && `エラー ${errors} 件`, warnings > 0 && `警告 ${warnings} 件`].filter(Boolean).join('・');
  const lines = problems.slice(0, max).map((d) => `・${d.message}`);
  if (problems.length > max) lines.push(`ほか ${problems.length - max} 件`);
  return [head, ...lines].join('\n');
}

/** いちばん重いもの（error があれば error） */
export function severityOf(diagnostics: readonly Diagnostic[]): 'error' | 'warning' | null {
  if (diagnostics.some((d) => d.severity === 'error')) return 'error';
  if (diagnostics.length > 0) return 'warning';
  return null;
}

/**
 * レイヤー 0（ベースレイヤー）の同じ位置の値。KC_TRNS のキーに薄く出す（protocol.md の 12.7）。
 * レイヤー 0 そのもの・レイヤー 0 がない・値がない・何もしない（NoKey）か同じく下へ落とす（Trans）ときは null
 */
export function baseLayerValue(snapshot: ProfileSnapshot, layerIndex: number | undefined, slot: Slot): KeyValue | null {
  if (layerIndex === 0) return null;
  const base = snapshot.layers.find((layer) => layer.index === 0);
  if (!base) return null;
  let value: KeyValue | null = null;
  if (slot.key) {
    const { row, col } = slot.key;
    value = base.keys.find((key) => key.hand === slot.hand && key.row === row && key.col === col)?.value ?? null;
  } else if (slot.encoder) {
    value = base.encoders[slot.hand][slot.encoder].value;
  }
  if (!value || value.kind === 'transparent' || value.kind === 'noKey' || !value.display.label) return null;
  return value;
}

/** レイヤーの同じ位置（手・行・列）のキー（なければ undefined） */
export function keyAt(layer: LayerSnapshot, slot: Pick<Slot, 'hand' | 'key'>): LayerKey | undefined {
  const key = slot.key;
  if (!key) return undefined;
  return layer.keys.find((k) => k.hand === slot.hand && k.row === key.row && k.col === key.col);
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
  base?: KeyValue | null,
): string {
  let content: string;
  if (text === '') content = '割り当てなし';
  else if (value?.kind === 'transparent' && base) content = `${value.display.label || text}（レイヤー 0 の値 ${base.display.label}）`;
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

/**
 * v0.5（issue #113）: 未保存の変更を当てた番号で分け直したレイヤー（protocol.md の 15.4）。
 * used は番号の順（タブ・図・キー別に並べる。未使用から取り出したものも同じ形で描く）、unused は未使用のまま（「＋」の一覧だけに出す）
 */
export type ArrangedLayers = {
  used: LayerSnapshot[];
  unused: Unused<LayerSnapshot>[];
  /** 番号を未保存の変更で変えた（取り出したものを含む）レイヤーのファイル */
  changed: Set<string>;
  /** 取り出したときの番号（埋まっていれば null） */
  next: number | null;
};

export function arrangeLayers(snapshot: ProfileSnapshot, pending: readonly AnyChange[]): ArrangedLayers {
  const items = snapshotItems(snapshot, 'layer');
  const { used, unused } = arrangeItems(items, pending);
  const changed = new Set(items.filter((item) => indexChanged(item.file, item.index, pending)).map((item) => item.file));
  return {
    used: used as LayerSnapshot[],
    unused,
    changed,
    next: nextIndex(
      'layer',
      used.map((layer) => layer.index),
    ),
  };
}

/** レイヤーの並び（番号とファイル）が変わったかを比べる形 */
export function arrangementKey(layers: readonly { index: number; file: string }[]): string {
  return JSON.stringify(layers.map((layer) => [layer.index, layer.file]));
}

/** 番号が埋まっていて未使用のレイヤーを取り出せないときの文 */
export const LAYER_INDEXES_FULL = '番号が 10 個とも使われています。使っているレイヤーのどれかを「未使用にする」と、ここから選べます。';
