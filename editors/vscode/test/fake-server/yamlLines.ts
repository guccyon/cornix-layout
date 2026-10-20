// 偽のサーバーが v0.2 の Change（protocol.md の 12.3）を当てるための、YAML の行の素朴な書き換え。
// ブロック形式の `キー: 値`、ブロックの並び（`- 値`。キーと同じ字下げでもよい）、1 行のフロー表記の並び（`[A, B]`）だけを扱う。
// Ruby のサーバーの書き換え（Storage::YamlDocument）の代わりではなく、拡張の保存と当て直しの流れを試すためのもの。
import type { AnyChange, MacroStepValue } from '../../src/protocol';

type Region = { start: number; end: number };
type Node =
  | { kind: 'key'; line: number; region: Region }
  | { kind: 'item'; line: number; region: Region }
  | { kind: 'flowItem'; line: number; index: number };

/** 書き換えられないとき（偽のサーバーは -32061 にする） */
export class NotLocal extends Error {}

export function quote(value: string): string {
  return /^[\p{L}\p{N}_()' +\-]+$/u.test(value) && !/^[-?:,]/.test(value) ? value : JSON.stringify(value);
}

function indentOf(line: string): number {
  return line.length - line.trimStart().length;
}

/** 行の中身の始まりの列と中身（`- ` の付いた行は `- ` のあと） */
function content(line: string): { col: number; text: string; dash: boolean } {
  const indent = indentOf(line);
  const trimmed = line.trimStart();
  if (trimmed.startsWith('- ')) return { col: indent + 2, text: trimmed.slice(2), dash: true };
  return { col: indent, text: trimmed, dash: false };
}

const blank = (line: string | undefined) => line === undefined || !line.trim() || line.trim().startsWith('#') || line.trim() === '---';

function keyPattern(key: string): RegExp {
  return new RegExp(`^(["']?)${key.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\1\\s*:(\\s|$)`);
}

/** region の中の、いちばん浅い列にある key の行 */
function keyLine(lines: string[], region: Region, key: string): number {
  let min = Infinity;
  for (let i = region.start; i < region.end; i++) if (!blank(lines[i])) min = Math.min(min, content(lines[i]!).col);
  const pattern = keyPattern(key);
  for (let i = region.start; i < region.end; i++) {
    const line = lines[i]!;
    if (blank(line)) continue;
    const c = content(line);
    if (c.col === min && pattern.test(c.text)) return i;
  }
  return -1;
}

/** キーの行の値の範囲（列）。値がなければ undefined */
function inlineRange(line: string): { start: number; end: number } | undefined {
  const c = content(line);
  const colon = line.indexOf(':', c.col);
  if (colon < 0) return undefined;
  const after = line.slice(colon + 1);
  const offset = after.search(/\S/);
  if (offset < 0 || after.trim().startsWith('#')) return undefined;
  const start = colon + 1 + offset;
  const comment = line.indexOf(' #', start);
  const raw = line.slice(start, comment < 0 ? undefined : comment);
  return { start, end: start + raw.trimEnd().length };
}

/** キーの行の値の下の行（字下げの深い行と、同じ字下げの `- ` の行） */
function childRegion(lines: string[], line: number): Region {
  const col = content(lines[line]!).col;
  let end = line + 1;
  for (let i = line + 1; i < lines.length; i++) {
    const text = lines[i]!;
    if (blank(text)) continue;
    const indent = indentOf(text);
    if (indent > col || (indent === col && text.trimStart().startsWith('- '))) end = i + 1;
    else break;
  }
  return { start: line + 1, end };
}

/** region の中のブロックの並びの要素 */
function items(lines: string[], region: Region): Region[] {
  let min = Infinity;
  for (let i = region.start; i < region.end; i++) if (!blank(lines[i])) min = Math.min(min, indentOf(lines[i]!));
  const starts: number[] = [];
  for (let i = region.start; i < region.end; i++) {
    const line = lines[i]!;
    if (!blank(line) && indentOf(line) === min && line.trimStart().startsWith('- ')) starts.push(i);
  }
  return starts.map((start, i) => ({ start, end: starts[i + 1] ?? region.end }));
}

function resolve(lines: string[], path: (string | number)[]): Node | undefined {
  let region: Region = { start: 0, end: lines.length };
  let node: Node | undefined;
  for (const segment of path) {
    if (typeof segment === 'string') {
      const line = keyLine(lines, region, segment);
      if (line < 0) return undefined;
      region = childRegion(lines, line);
      node = { kind: 'key', line, region };
      continue;
    }
    if (!node || node.kind === 'flowItem') return undefined;
    const value = node.kind === 'key' ? inlineRange(lines[node.line]!) : undefined;
    if (value) {
      const text = lines[node.line]!.slice(value.start, value.end);
      if (text.startsWith('[')) return { kind: 'flowItem', line: node.line, index: segment };
      // 1 つの値で書いた並び（keys: A）の要素 0 は、その値
      if (segment === 0) return node;
      return undefined;
    }
    const item = items(lines, region)[segment];
    if (!item) return undefined;
    region = item;
    node = { kind: 'item', line: item.start, region: item };
  }
  return node;
}

function flowItems(text: string): string[] {
  const inner = text.trim().slice(1, -1).trim();
  return inner ? inner.split(',').map((s) => s.trim()) : [];
}

function replaceInline(lines: string[], line: number, text: string): void {
  const range = inlineRange(lines[line]!);
  if (!range) throw new NotLocal('値のない行です');
  const current = lines[line]!;
  lines[line] = current.slice(0, range.start) + text + current.slice(range.end);
}

/** `- 値` の行の値を置き換える */
function replaceItemScalar(lines: string[], line: number, text: string): void {
  const current = lines[line]!;
  const c = content(current);
  lines[line] = current.slice(0, c.col) + text;
}

function stepLines(step: MacroStepValue, indent: string): string[] {
  const head = `${indent}- action: ${step.action}`;
  const inner = `${indent}  `;
  if (step.action === 'delay') return [head, `${inner}duration: ${step.duration}`];
  if (step.action === 'text') return [head, `${inner}content: ${quote(step.content)}`];
  return [head, `${inner}keys: [${step.keys.map(quote).join(', ')}]`];
}

/** 注記付きの形（{ key: v, note: n }）から key と note を取る */
function parseNoted(text: string): { key: string; note: string | undefined } {
  const match = /^\{\s*key:\s*(.*?)\s*(?:,\s*note:\s*(.*?)\s*)?\}$/.exec(text);
  if (!match) return { key: text, note: undefined };
  return { key: match[1] ?? '', note: match[2] };
}

/** Change を 1 つ当てる（lines を書き換える）。当てられなければ NotLocal */
export function applyChange(lines: string[], change: AnyChange): void {
  const op = change.op ?? 'set';
  const node = resolve(lines, change.address.path);
  if (!node) throw new NotLocal(`${change.address.path.join('.')} が見つかりません`);
  const note = (op === 'set' || op === 'remove') && 'field' in change && change.field === 'note';

  if (op === 'set') {
    const value = (change as { value: string | number | boolean }).value;
    const text = typeof value === 'string' ? quote(value) : String(value);
    if (node.kind === 'flowItem') {
      const range = inlineRange(lines[node.line]!)!;
      const list = flowItems(lines[node.line]!.slice(range.start, range.end));
      if (node.index >= list.length) throw new NotLocal('並びの外です');
      list[node.index] = text;
      replaceInline(lines, node.line, `[${list.join(', ')}]`);
    } else if (node.kind === 'item') {
      replaceItemScalar(lines, node.line, text);
    } else if (note) {
      const range = inlineRange(lines[node.line]!);
      if (!range) throw new NotLocal('値のない行です');
      const { key } = parseNoted(lines[node.line]!.slice(range.start, range.end));
      replaceInline(lines, node.line, `{ key: ${key}, note: ${JSON.stringify(String(value))} }`);
    } else {
      const range = inlineRange(lines[node.line]!);
      if (!range) throw new NotLocal('値のない行です');
      const { note: kept } = parseNoted(lines[node.line]!.slice(range.start, range.end));
      replaceInline(lines, node.line, kept === undefined ? text : `{ key: ${text}, note: ${kept} }`);
    }
    return;
  }

  if (op === 'remove') {
    if (node.kind === 'flowItem') {
      const range = inlineRange(lines[node.line]!)!;
      const list = flowItems(lines[node.line]!.slice(range.start, range.end));
      list.splice(node.index, 1);
      replaceInline(lines, node.line, `[${list.join(', ')}]`);
    } else if (note) {
      if (node.kind !== 'key') throw new NotLocal('注記を書けない場所です');
      const range = inlineRange(lines[node.line]!);
      if (!range) throw new NotLocal('値のない行です');
      replaceInline(lines, node.line, parseNoted(lines[node.line]!.slice(range.start, range.end)).key);
    } else if (node.kind === 'item') {
      lines.splice(node.region.start, node.region.end - node.region.start);
    } else {
      lines.splice(node.line, node.region.end - node.line);
    }
    return;
  }

  if (node.kind !== 'key') throw new NotLocal('並びではありません');
  const range = inlineRange(lines[node.line]!);
  if (op === 'insert') {
    const { index, value } = change as { index: number; value: string | MacroStepValue };
    if (range) {
      const text = lines[node.line]!.slice(range.start, range.end);
      const list = text.startsWith('[') ? flowItems(text) : [text];
      if (typeof value !== 'string') throw new NotLocal('フロー表記の並びに手順は足せません');
      list.splice(index, 0, quote(value));
      replaceInline(lines, node.line, `[${list.join(', ')}]`);
      return;
    }
    const list = items(lines, node.region);
    const indent = list[0] ? ' '.repeat(indentOf(lines[list[0].start]!)) : ' '.repeat(content(lines[node.line]!).col);
    const text = typeof value === 'string' ? [`${indent}- ${quote(value)}`] : stepLines(value, indent);
    const at = list[index]?.start ?? (list.at(-1)?.end ?? node.line + 1);
    lines.splice(at, 0, ...text);
    return;
  }

  // move
  const { from, to } = change as { from: number; to: number };
  if (range) {
    const text = lines[node.line]!.slice(range.start, range.end);
    const list = text.startsWith('[') ? flowItems(text) : [text];
    const [moved] = list.splice(from, 1);
    if (moved === undefined) throw new NotLocal('並びの外です');
    list.splice(to, 0, moved);
    replaceInline(lines, node.line, `[${list.join(', ')}]`);
    return;
  }
  const list = items(lines, node.region);
  if (!list[from] || to < 0 || to >= list.length) throw new NotLocal('並びの外です');
  const blocks = list.map((item) => lines.slice(item.start, item.end));
  const [moved] = blocks.splice(from, 1);
  blocks.splice(to, 0, moved!);
  const first = list[0]!.start;
  const last = list.at(-1)!.end;
  lines.splice(first, last - first, ...blocks.flat());
}
