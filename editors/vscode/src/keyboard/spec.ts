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
 * rx / ry がないときは矩形の中心まわりに回す
 */
export type KeyRect = { x: number; y: number; w: number; h: number; r?: number; rx?: number; ry?: number };

/** エンコーダの外枠（u）。円なので w = h */
export type EncoderPlace = { x: number; y: number; w: number; h: number };

/** 図のキー 1 つ。match は約束（protocol.md）の論理位置との対応 */
export type KeyboardKey = { id: string; section: string; rect: KeyRect; match: { hand: Hand; row: number; col: number } };

/** エンコーダ 1 つ。match は約束の layer.encoders の left / right との対応 */
export type KeyboardEncoder = { id: string; section: string; label: string; place: EncoderPlace; match: { side: Hand } };

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
};

const LIMIT_OF: Record<IndexedKind, keyof KeyboardLimits> = { layer: 'layers', macro: 'macros', tapDance: 'tapDances', combo: 'combos' };

/** その種類の番号の数（0〜上限 - 1） */
export function indexLimit(limits: KeyboardLimits, kind: IndexedKind): number {
  return limits[LIMIT_OF[kind]];
}
