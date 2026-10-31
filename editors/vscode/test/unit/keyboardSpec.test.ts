// KeyboardSpec（ADR 026）: Webview は spec のデータ（keyboard/cornix.ts・keyboard/index.ts）を import せず、ホストから受け取る
import * as fs from 'node:fs';
import * as path from 'node:path';
import { describe, expect, it } from 'vitest';
import { CORNIX } from '../../src/keyboard/cornix';
import { keyboardSpecFor } from '../../src/keyboard';
import { indexLimit } from '../../src/keyboard/spec';

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
});
