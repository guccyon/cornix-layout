// Cornix の物理配置（キーボード図のキーの座標）。Cornix 専用として拡張に固定で持ち、
// サーバーの返す論理位置（hand / row / col。docs/domain-model.md の 5 節）と組み合わせる（ADR 009）。
//
// 単位は 1 キーの幅（u）。左手の左上が (0, 0)。
// - 各手 row0〜row2 は 6 キー（列ごとに少し上下にずらす: 中指がいちばん上）、row3 は外側に 3 キー、親指は内側に 3 キー
// - 論理位置の列は左右とも「物理的に左から右」なので、右手は row3（col 0〜2）が外側（右）、親指（col 3〜5）が内側（左）になる
// - エンコーダは両手の間の row2 の高さに置く。**仮の位置**: 実機の写真や寸法で確かめたものではない
//   （layout.vil のマトリクスで押し込みが row2 / row5 の col 6 にあるのは配線の位置で、物理の位置を決めない）。
//   実機とずれていれば ENCODERS の数字だけを直す
import type { Hand } from '../protocol';

export type KeyRect = { x: number; y: number; w: number; h: number; rotate: number };
export type EncoderPlace = { x: number; y: number; r: number };

/** 片手の列ごとの縦のずらし（u）。左手の col 0（外側）から col 5（内側）の順 */
const COLUMN_STAGGER = [0.45, 0.45, 0.15, 0, 0.15, 0.3];
const HALF_WIDTH = 6;
/** 両手の間（エンコーダを置く） */
const GAP = 3.6;
const RIGHT_ORIGIN = HALF_WIDTH + GAP;
const KEY = 0.94;

/** 左手の (row, col) の左上。右手はこれを左右に写す */
function leftHand(row: number, col: number): KeyRect {
  if (row <= 2) return { x: col, y: row + (COLUMN_STAGGER[col] ?? 0), w: KEY, h: KEY, rotate: 0 };
  if (col <= 2) {
    // row3 の外側の 3 キー（row2 の下）
    return { x: col, y: 3 + (COLUMN_STAGGER[col] ?? 0), w: KEY, h: KEY, rotate: 0 };
  }
  // 親指（col 3〜5）。内側へ向かって少し下げ、扇形に傾ける
  const i = col - 3;
  return { x: 3.35 + i * 1.05, y: 3.45 + i * 0.12, w: KEY, h: KEY, rotate: i * 6 };
}

/** 論理位置 → 物理の矩形。position_map にない位置（row3 の col 6 など）は undefined */
export function keyRect(hand: Hand, row: number, col: number): KeyRect | undefined {
  if (row < 0 || row > 3 || col < 0 || col > 5) return undefined;
  if (hand === 'left') return leftHand(row, col);
  // 右手: 物理の左から右に col が並ぶ。row0〜2 と row3（外側 = 右）と親指（内側 = 左）を左手の鏡にする
  let mirrorCol: number;
  if (row <= 2) mirrorCol = 5 - col;
  else if (col <= 2) mirrorCol = 2 - col; // row3: 右手の col 0 は左手の col 2 の鏡
  else mirrorCol = 3 + (5 - col); // 親指: 右手の col 3（左端 = 内側）は左手の col 5 の鏡
  const left = leftHand(row, mirrorCol);
  return { x: RIGHT_ORIGIN + (HALF_WIDTH - left.x - left.w), y: left.y, w: left.w, h: left.h, rotate: -left.rotate };
}

/** エンコーダの中心と半径（u）。仮の位置（ファイルの先頭のコメント） */
export const ENCODERS: Record<Hand, EncoderPlace> = {
  left: { x: HALF_WIDTH + 0.95, y: 2.2, r: 0.75 },
  right: { x: RIGHT_ORIGIN - 0.95, y: 2.2, r: 0.75 },
};

/** 図全体の大きさ（u） */
export const BOARD = { width: RIGHT_ORIGIN + HALF_WIDTH, height: 4.75 };
