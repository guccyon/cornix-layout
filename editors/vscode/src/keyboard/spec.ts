// キーボード固有の情報（KeyboardSpec。ADR 026）。拡張の各処理はキーの数・配置・個数の上限などをこの型の値から取る。
// 値（Cornix の spec など）はホストが選んで Webview に送る（webviewMessages.ts の keyboard）。Webview はこのファイルの型と
// 純粋な関数だけを import し、spec のデータ（cornix.ts など）は import しない（test/unit/keyboardSpec.test.ts が確かめる）。
// postMessage で送れるよう、spec はデータだけで関数を持たない。vscode に依存しない。
import type { Hand, IndexedKind } from '../protocol';

/** 番号を持つ項目の数とコンボのキーの数の上限 */
export type KeyboardLimits = {
  /** レイヤーの数（番号は 0〜layers - 1） */
  layers: number;
  macros: number;
  tapDances: number;
  combos: number;
  /** コンボで同時に押すキーの数 */
  comboKeys: number;
};

/** 区画（左右の手を一般化したもの。一体型のキーボードは 1 つ） */
export type KeyboardSection = { id: string; label: string };

/** position_map のグループ（row0・thumb など）とその見出し */
export type KeyboardGroup = { id: string; label: string };

/**
 * キーの矩形。単位は 1 キーの幅（u）。項目は Vial の KLE に寄せる（x, y, w, h, 回転の角度 r と中心 rx, ry）。
 * x, y は回す前の矩形の左上で、図の左上を (0, 0) とする（負にしない）。r は度で時計回り（CSS の rotate と同じ）。
 * rx / ry は回転の中心で、x, y と同じく図の座標。rx / ry がないときは矩形の中心まわりに回す（片方だけなら、ないほうは中心）
 */
export type KeyRect = { x: number; y: number; w: number; h: number; r?: number; rx?: number; ry?: number };

/** エンコーダの外枠（u）。円なので w = h */
export type EncoderPlace = { x: number; y: number; w: number; h: number };

/** 図のキー 1 つ。match は約束（protocol.md）の論理位置との対応 */
export type KeyboardKey = { id: string; section: string; rect: KeyRect; match: { hand: Hand; row: number; col: number } };

/** エンコーダ 1 つ。match は約束の layer.encoders の left / right との対応 */
export type KeyboardEncoder = { id: string; section: string; label: string; place: EncoderPlace; match: { side: Hand } };

/** 図の余白（u）。キーとエンコーダの範囲の外に足す（図の大きさは boardSize） */
export type BoardPadding = { right?: number; bottom?: number };

export type KeyboardSpec = {
  /** 'cornix' */
  id: string;
  /** 'Cornix'（「接続中の Cornix」などの文言に使う） */
  displayName: string;
  limits: KeyboardLimits;
  sections: KeyboardSection[];
  groups: KeyboardGroup[];
  keys: KeyboardKey[];
  encoders: KeyboardEncoder[];
  /** 図の右と下の余白（なければ 0） */
  padding?: BoardPadding;
};

const LIMIT_OF: Record<IndexedKind, keyof KeyboardLimits> = { layer: 'layers', macro: 'macros', tapDance: 'tapDances', combo: 'combos' };

/** その種類の番号の数（0〜上限 - 1） */
export function indexLimit(limits: KeyboardLimits, kind: IndexedKind): number {
  return limits[LIMIT_OF[kind]];
}

/** 回転の中心（rx / ry がなければ矩形の中心） */
export function rotationOrigin(rect: KeyRect): { x: number; y: number } {
  return { x: rect.rx ?? rect.x + rect.w / 2, y: rect.ry ?? rect.y + rect.h / 2 };
}

/** 回した矩形の 4 つの角 */
function corners(rect: KeyRect): { x: number; y: number }[] {
  const points = [
    { x: rect.x, y: rect.y },
    { x: rect.x + rect.w, y: rect.y },
    { x: rect.x + rect.w, y: rect.y + rect.h },
    { x: rect.x, y: rect.y + rect.h },
  ];
  if (!rect.r) return points;
  const origin = rotationOrigin(rect);
  const angle = (rect.r * Math.PI) / 180;
  const cos = Math.cos(angle);
  const sin = Math.sin(angle);
  return points.map(({ x, y }) => ({
    x: origin.x + (x - origin.x) * cos - (y - origin.y) * sin,
    y: origin.y + (x - origin.x) * sin + (y - origin.y) * cos,
  }));
}

/** 小数の誤差（15.46 + 0.94 = 16.400000000000002 など）を落とす */
const roundSize = (value: number) => Math.round(value * 1e6) / 1e6;

/**
 * 図全体の大きさ（u）。左上を (0, 0) とし、キー（回したあとの角）とエンコーダの外枠のいちばん右・下に余白（spec.padding）を足す。
 * 小数第 6 位で丸める
 */
export function boardSize(spec: Pick<KeyboardSpec, 'keys' | 'encoders' | 'padding'>): { width: number; height: number } {
  let right = 0;
  let bottom = 0;
  const points = [
    ...spec.keys.flatMap((key) => corners(key.rect)),
    ...spec.encoders.flatMap((encoder) => corners(encoder.place)),
  ];
  for (const point of points) {
    right = Math.max(right, point.x);
    bottom = Math.max(bottom, point.y);
  }
  return { width: roundSize(right + (spec.padding?.right ?? 0)), height: roundSize(bottom + (spec.padding?.bottom ?? 0)) };
}
