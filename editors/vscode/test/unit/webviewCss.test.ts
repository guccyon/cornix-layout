// media/webview.css の括弧の釣り合い。vitest は CSS を当てないので、マージで閉じ括弧が落ちても気づけない
// （v0.3 で E1 と E2 の末尾の追加を手で合わせたとき、後ろの規則がすべて入れ子として読まれた）。
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';

describe('webview.css', () => {
  it('波括弧が釣り合っていて、途中で閉じすぎない', () => {
    const css = readFileSync(join(__dirname, '../../media/webview.css'), 'utf8').replace(/\/\*[\s\S]*?\*\//g, '');
    let depth = 0;
    for (const c of css) {
      if (c === '{') depth++;
      if (c === '}') depth--;
      expect(depth).toBeGreaterThanOrEqual(0);
    }
    expect(depth).toBe(0);
  });
});
