// Cornix の KeyboardSpec（spec.ts）。値は cornix 本体の Domain::Capabilities::CORNIX と docs/domain-model.md の position_map に合わせる。
// Webview はこのファイルを import しない（ホストが選んで送る。ADR 026）
import type { KeyboardSpec } from './spec';

export const CORNIX: KeyboardSpec = {
  id: 'cornix',
  displayName: 'Cornix',
  limits: { layers: 10, macros: 32, tapDances: 32, combos: 32, comboKeys: 4 },
  sections: [
    { id: 'left', label: '左手' },
    { id: 'right', label: '右手' },
  ],
  groups: [
    { id: 'row0', label: '1 段目' },
    { id: 'row1', label: '2 段目' },
    { id: 'row2', label: '3 段目' },
    { id: 'row3', label: '4 段目' },
    { id: 'thumb', label: '親指' },
    // 前の版のサーバーが返す旧名
    { id: 'thumb_keys', label: '親指' },
  ],
  // 図の配置（単位は 1 キーの幅 u。左手の左上が (0, 0)）。値は v0.4 までの webview/cornixLayout.ts の式の結果をそのまま写したもの
  // （3.5700000000000003 などの端数も式と同じ。図を 1px も変えないため）。
  // - 各手 row0〜row2 は 6 キー（列ごとに少し上下にずらす: 中指がいちばん上）。キーは 0.94 u 角で、1 u ごとに並べる
  // - 論理位置の列は左右とも「物理的に左から右」なので、右手は row3（col 0〜2）が外側（右）、親指（col 3〜5）が内側（左）になる
  // - 親指は内側へ向かって少し下げ、扇形に傾ける（矩形の中心まわり）
  // - position_map にない位置（row3 の col 6 など）はキーを持たない（図に描かない）
  keys: [
    // 左手 row0
    { id: 'L-r0c0', section: 'left', rect: { x: 0, y: 0.45, w: 0.94, h: 0.94 }, match: { hand: 'left', row: 0, col: 0 } },
    { id: 'L-r0c1', section: 'left', rect: { x: 1, y: 0.45, w: 0.94, h: 0.94 }, match: { hand: 'left', row: 0, col: 1 } },
    { id: 'L-r0c2', section: 'left', rect: { x: 2, y: 0.15, w: 0.94, h: 0.94 }, match: { hand: 'left', row: 0, col: 2 } },
    { id: 'L-r0c3', section: 'left', rect: { x: 3, y: 0, w: 0.94, h: 0.94 }, match: { hand: 'left', row: 0, col: 3 } },
    { id: 'L-r0c4', section: 'left', rect: { x: 4, y: 0.15, w: 0.94, h: 0.94 }, match: { hand: 'left', row: 0, col: 4 } },
    { id: 'L-r0c5', section: 'left', rect: { x: 5, y: 0.3, w: 0.94, h: 0.94 }, match: { hand: 'left', row: 0, col: 5 } },
    // 左手 row1
    { id: 'L-r1c0', section: 'left', rect: { x: 0, y: 1.45, w: 0.94, h: 0.94 }, match: { hand: 'left', row: 1, col: 0 } },
    { id: 'L-r1c1', section: 'left', rect: { x: 1, y: 1.45, w: 0.94, h: 0.94 }, match: { hand: 'left', row: 1, col: 1 } },
    { id: 'L-r1c2', section: 'left', rect: { x: 2, y: 1.15, w: 0.94, h: 0.94 }, match: { hand: 'left', row: 1, col: 2 } },
    { id: 'L-r1c3', section: 'left', rect: { x: 3, y: 1, w: 0.94, h: 0.94 }, match: { hand: 'left', row: 1, col: 3 } },
    { id: 'L-r1c4', section: 'left', rect: { x: 4, y: 1.15, w: 0.94, h: 0.94 }, match: { hand: 'left', row: 1, col: 4 } },
    { id: 'L-r1c5', section: 'left', rect: { x: 5, y: 1.3, w: 0.94, h: 0.94 }, match: { hand: 'left', row: 1, col: 5 } },
    // 左手 row2
    { id: 'L-r2c0', section: 'left', rect: { x: 0, y: 2.45, w: 0.94, h: 0.94 }, match: { hand: 'left', row: 2, col: 0 } },
    { id: 'L-r2c1', section: 'left', rect: { x: 1, y: 2.45, w: 0.94, h: 0.94 }, match: { hand: 'left', row: 2, col: 1 } },
    { id: 'L-r2c2', section: 'left', rect: { x: 2, y: 2.15, w: 0.94, h: 0.94 }, match: { hand: 'left', row: 2, col: 2 } },
    { id: 'L-r2c3', section: 'left', rect: { x: 3, y: 2, w: 0.94, h: 0.94 }, match: { hand: 'left', row: 2, col: 3 } },
    { id: 'L-r2c4', section: 'left', rect: { x: 4, y: 2.15, w: 0.94, h: 0.94 }, match: { hand: 'left', row: 2, col: 4 } },
    { id: 'L-r2c5', section: 'left', rect: { x: 5, y: 2.3, w: 0.94, h: 0.94 }, match: { hand: 'left', row: 2, col: 5 } },
    // 左手 row3（col 0〜2 が外側の 3 キー、col 3〜5 が親指）
    { id: 'L-r3c0', section: 'left', rect: { x: 0, y: 3.45, w: 0.94, h: 0.94 }, match: { hand: 'left', row: 3, col: 0 } },
    { id: 'L-r3c1', section: 'left', rect: { x: 1, y: 3.45, w: 0.94, h: 0.94 }, match: { hand: 'left', row: 3, col: 1 } },
    { id: 'L-r3c2', section: 'left', rect: { x: 2, y: 3.15, w: 0.94, h: 0.94 }, match: { hand: 'left', row: 3, col: 2 } },
    { id: 'L-r3c3', section: 'left', rect: { x: 3.35, y: 3.45, w: 0.94, h: 0.94 }, match: { hand: 'left', row: 3, col: 3 } },
    { id: 'L-r3c4', section: 'left', rect: { x: 4.4, y: 3.5700000000000003, w: 0.94, h: 0.94, r: 6 }, match: { hand: 'left', row: 3, col: 4 } },
    { id: 'L-r3c5', section: 'left', rect: { x: 5.45, y: 3.6900000000000004, w: 0.94, h: 0.94, r: 12 }, match: { hand: 'left', row: 3, col: 5 } },
    // 右手 row0
    { id: 'R-r0c0', section: 'right', rect: { x: 10.46, y: 0.3, w: 0.94, h: 0.94 }, match: { hand: 'right', row: 0, col: 0 } },
    { id: 'R-r0c1', section: 'right', rect: { x: 11.46, y: 0.15, w: 0.94, h: 0.94 }, match: { hand: 'right', row: 0, col: 1 } },
    { id: 'R-r0c2', section: 'right', rect: { x: 12.46, y: 0, w: 0.94, h: 0.94 }, match: { hand: 'right', row: 0, col: 2 } },
    { id: 'R-r0c3', section: 'right', rect: { x: 13.46, y: 0.15, w: 0.94, h: 0.94 }, match: { hand: 'right', row: 0, col: 3 } },
    { id: 'R-r0c4', section: 'right', rect: { x: 14.46, y: 0.45, w: 0.94, h: 0.94 }, match: { hand: 'right', row: 0, col: 4 } },
    { id: 'R-r0c5', section: 'right', rect: { x: 15.46, y: 0.45, w: 0.94, h: 0.94 }, match: { hand: 'right', row: 0, col: 5 } },
    // 右手 row1
    { id: 'R-r1c0', section: 'right', rect: { x: 10.46, y: 1.3, w: 0.94, h: 0.94 }, match: { hand: 'right', row: 1, col: 0 } },
    { id: 'R-r1c1', section: 'right', rect: { x: 11.46, y: 1.15, w: 0.94, h: 0.94 }, match: { hand: 'right', row: 1, col: 1 } },
    { id: 'R-r1c2', section: 'right', rect: { x: 12.46, y: 1, w: 0.94, h: 0.94 }, match: { hand: 'right', row: 1, col: 2 } },
    { id: 'R-r1c3', section: 'right', rect: { x: 13.46, y: 1.15, w: 0.94, h: 0.94 }, match: { hand: 'right', row: 1, col: 3 } },
    { id: 'R-r1c4', section: 'right', rect: { x: 14.46, y: 1.45, w: 0.94, h: 0.94 }, match: { hand: 'right', row: 1, col: 4 } },
    { id: 'R-r1c5', section: 'right', rect: { x: 15.46, y: 1.45, w: 0.94, h: 0.94 }, match: { hand: 'right', row: 1, col: 5 } },
    // 右手 row2
    { id: 'R-r2c0', section: 'right', rect: { x: 10.46, y: 2.3, w: 0.94, h: 0.94 }, match: { hand: 'right', row: 2, col: 0 } },
    { id: 'R-r2c1', section: 'right', rect: { x: 11.46, y: 2.15, w: 0.94, h: 0.94 }, match: { hand: 'right', row: 2, col: 1 } },
    { id: 'R-r2c2', section: 'right', rect: { x: 12.46, y: 2, w: 0.94, h: 0.94 }, match: { hand: 'right', row: 2, col: 2 } },
    { id: 'R-r2c3', section: 'right', rect: { x: 13.46, y: 2.15, w: 0.94, h: 0.94 }, match: { hand: 'right', row: 2, col: 3 } },
    { id: 'R-r2c4', section: 'right', rect: { x: 14.46, y: 2.45, w: 0.94, h: 0.94 }, match: { hand: 'right', row: 2, col: 4 } },
    { id: 'R-r2c5', section: 'right', rect: { x: 15.46, y: 2.45, w: 0.94, h: 0.94 }, match: { hand: 'right', row: 2, col: 5 } },
    // 右手 row3（col 0〜2 が外側（右）の 3 キー、col 3〜5 が親指（内側 = 左））
    { id: 'R-r3c0', section: 'right', rect: { x: 13.46, y: 3.15, w: 0.94, h: 0.94 }, match: { hand: 'right', row: 3, col: 0 } },
    { id: 'R-r3c1', section: 'right', rect: { x: 14.46, y: 3.45, w: 0.94, h: 0.94 }, match: { hand: 'right', row: 3, col: 1 } },
    { id: 'R-r3c2', section: 'right', rect: { x: 15.46, y: 3.45, w: 0.94, h: 0.94 }, match: { hand: 'right', row: 3, col: 2 } },
    { id: 'R-r3c3', section: 'right', rect: { x: 10.01, y: 3.6900000000000004, w: 0.94, h: 0.94, r: -12 }, match: { hand: 'right', row: 3, col: 3 } },
    { id: 'R-r3c4', section: 'right', rect: { x: 11.06, y: 3.5700000000000003, w: 0.94, h: 0.94, r: -6 }, match: { hand: 'right', row: 3, col: 4 } },
    { id: 'R-r3c5', section: 'right', rect: { x: 12.11, y: 3.45, w: 0.94, h: 0.94 }, match: { hand: 'right', row: 3, col: 5 } },
  ],
  // エンコーダは両手の間に、丸いつまみとして描く（w = h）。row0〜row2 の高さの中ほど、親指のキーより上。
  // 円を上・中・下の 3 つの帯に分け、左回し・押し込み・右回しの欄にする。位置は実機と少しずれてよく、割り当てたキーの文字が
  // 普通のキーと同じ大きさで読めることを優先する（基板は描かない）。layout.vil のマトリクスで押し込みが row2 / row5 の col 6 に
  // あるのは配線の位置で、図の位置を決めない。label は図の読み上げの名前
  encoders: [
    { id: 'L-encoder', section: 'left', label: '左手のエンコーダ', place: { x: 6.13, y: 0.5, w: 2.0050000000000003, h: 2.0050000000000003 }, match: { side: 'left' } },
    { id: 'R-encoder', section: 'right', label: '右手のエンコーダ', place: { x: 8.264999999999999, y: 0.5, w: 2.0050000000000003, h: 2.0050000000000003 }, match: { side: 'right' } },
  ],
  // 図の大きさは 16.4 × 4.75 u（boardSize）。下の余白は、回した親指の角（4.717448）から v0.4 までの図の高さ 4.75 までの空き
  padding: { bottom: 0.032552 },
};
