// KeyboardSpec（ADR 026）: Webview は spec のデータ（keyboard/cornix.ts・keyboard/index.ts）を import せず、ホストから受け取る
import * as fs from 'node:fs';
import * as path from 'node:path';
import { describe, expect, it } from 'vitest';
import { CORNIX } from '../../src/keyboard/cornix';
import { keyboardSpecFor } from '../../src/keyboard';
import { boardSize, indexLimit, rotationOrigin, type KeyRect } from '../../src/keyboard/spec';
import { LEGACY_BOARD, LEGACY_ENCODERS, LEGACY_KEYS } from './legacyCornixLayout';

const SRC = path.resolve(__dirname, '../../src');

function sourceFiles(dir: string): string[] {
  return fs.readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    const file = path.join(dir, entry.name);
    if (entry.isDirectory()) return sourceFiles(file);
    return file.endsWith('.ts') ? [file] : [];
  });
}

/** Webview から読まれるファイル（webview/ と、そこから import される共有のファイルを含む） */
function webviewReachable(): string[] {
  const seen = new Set<string>();
  const visit = (file: string) => {
    if (seen.has(file)) return;
    seen.add(file);
    const text = fs.readFileSync(file, 'utf8');
    for (const match of text.matchAll(/^import\s+(type\s+)?[^;]*?from\s+'(\.[^']+)';/gms)) {
      if (match[1]) continue; // 型だけの import は束ねたものに入らない
      const target = path.resolve(path.dirname(file), match[2]!);
      const resolved = [`${target}.ts`, path.join(target, 'index.ts')].find((candidate) => fs.existsSync(candidate));
      if (resolved) visit(resolved);
    }
  };
  visit(path.join(SRC, 'webview/main.ts'));
  for (const file of sourceFiles(path.join(SRC, 'webview'))) visit(file);
  return [...seen];
}

describe('KeyboardSpec', () => {
  it('Webview のコードは spec のデータを import しない（型と spec.ts の純粋な関数だけ）', () => {
    const reachable = webviewReachable().map((file) => path.relative(SRC, file));
    expect(reachable).toContain('webview/main.ts');
    expect(reachable).toContain('keyboard/spec.ts');
    expect(reachable).not.toContain('keyboard/cornix.ts');
    expect(reachable).not.toContain('keyboard/index.ts');
  });

  it('ホストが選ぶ spec は今は常に Cornix', () => {
    expect(keyboardSpecFor('/any/profile')).toBe(CORNIX);
  });

  it('Cornix の個数の上限は Domain::Capabilities::CORNIX と同じ', () => {
    expect(CORNIX.limits).toEqual({ layers: 10, macros: 32, tapDances: 32, combos: 32, comboKeys: 4 });
    expect(indexLimit(CORNIX.limits, 'layer')).toBe(10);
    expect(indexLimit(CORNIX.limits, 'tapDance')).toBe(32);
  });

  it('spec はデータだけ（postMessage で送れる）', () => {
    expect(JSON.parse(JSON.stringify(CORNIX))).toEqual(CORNIX);
  });

  it('Cornix のキーの矩形と回転は v0.4 までの式の値と完全に一致する（浮動小数点も）', () => {
    expect(CORNIX.keys.map((key) => [key.match.hand, key.match.row, key.match.col, key.rect.x, key.rect.y, key.rect.w, key.rect.h, key.rect.r ?? 0])).toStrictEqual(
      LEGACY_KEYS,
    );
    for (const key of CORNIX.keys) {
      expect(key.rect.rx).toBeUndefined();
      expect(key.rect.ry).toBeUndefined();
      expect(key.section).toBe(key.match.hand);
      expect(key.id).toBe(`${key.match.hand === 'left' ? 'L' : 'R'}-r${key.match.row}c${key.match.col}`);
    }
  });

  it('Cornix のエンコーダは左右の 2 つで、外枠は v0.4 までの式の値と完全に一致する', () => {
    expect(CORNIX.encoders.map((encoder) => [encoder.id, encoder.section, encoder.label, encoder.match.side])).toEqual([
      ['L-encoder', 'left', '左手のエンコーダ', 'left'],
      ['R-encoder', 'right', '右手のエンコーダ', 'right'],
    ]);
    for (const encoder of CORNIX.encoders) expect(encoder.place).toStrictEqual(LEGACY_ENCODERS[encoder.match.side]);
  });

  it('図の大きさは spec のキーとエンコーダの範囲と余白から決まり、Cornix は v0.4 までと同じ 16.4 × 4.75', () => {
    expect(boardSize(CORNIX)).toStrictEqual(LEGACY_BOARD);
    const key = (rect: KeyRect) => ({ id: 'k', section: 's', rect, match: { hand: 'left' as const, row: 0, col: 0 } });
    // 回した角も範囲に入る（中心まわりに 45 度回した 1 u 角は、中心から対角線の半分まで伸びる）
    expect(boardSize({ keys: [key({ x: 0, y: 0, w: 1, h: 1, r: 45 })], encoders: [] })).toEqual({ width: 1.207107, height: 1.207107 });
    // rx / ry は回転の中心（左上の角まわりに 90 度回すと、横長の矩形は左上の角から下へ伸びる）。余白は右と下に足す
    expect(boardSize({ keys: [key({ x: 1, y: 0, w: 2, h: 1, r: 90, rx: 1, ry: 0 })], encoders: [], padding: { right: 0.5 } })).toEqual({ width: 1.5, height: 2 });
  });

  it('回転の中心は rx / ry、なければ矩形の中心（片方だけなら、ないほうは中心）', () => {
    expect(rotationOrigin({ x: 1, y: 2, w: 1, h: 0.5 })).toEqual({ x: 1.5, y: 2.25 });
    expect(rotationOrigin({ x: 1, y: 2, w: 1, h: 0.5, r: 10, rx: 0, ry: 0 })).toEqual({ x: 0, y: 0 });
    expect(rotationOrigin({ x: 1, y: 2, w: 1, h: 0.5, r: 10, ry: 3 })).toEqual({ x: 1.5, y: 3 });
  });
});
