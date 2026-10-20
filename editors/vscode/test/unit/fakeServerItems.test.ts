// 偽のサーバーの v0.2（protocol.md の 12.2・12.3・12.5）: 中身の snapshot、並びの Change の planEdits、profile/planItemEdit
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { PassThrough } from 'node:stream';
import { describe, expect, it } from 'vitest';
import { ErrorCodes, type PlanEditsResult, type PlanItemEditResult, type ProfileSnapshot, type TextEdit } from '../../src/protocol';
import { readMessages, runFakeServer, VERIFY_FAIL_NAME } from '../fake-server/server';
import { applyChange } from '../fake-server/yamlLines';

const WORKSPACE = path.resolve(__dirname, '../integration/workspace');

async function opened() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'cornix-fake-items-'));
  fs.cpSync(WORKSPACE, root, { recursive: true });
  const input = new PassThrough();
  const output = new PassThrough();
  const received: { id?: unknown; result?: unknown; error?: { code: number; data?: unknown } }[] = [];
  runFakeServer(input, output, { root });
  readMessages(output, (message) => received.push(message as never), () => undefined);
  let id = 0;
  const call = async (method: string, params: object) => {
    const mine = ++id;
    const body = Buffer.from(JSON.stringify({ jsonrpc: '2.0', id: mine, method, params }), 'utf-8');
    input.write(`Content-Length: ${body.length}\r\n\r\n`);
    input.write(body);
    for (let i = 0; i < 100 && !received.some((m) => m.id === mine); i++) await new Promise((r) => setTimeout(r, 5));
    return received.find((m) => m.id === mine)!;
  };
  await call('initialize', { protocolVersion: '0.3', clientInfo: { name: 't', version: '0' } });
  const snapshot = (await call('profile/open', { dir: 'profiles/default' })).result as ProfileSnapshot;
  const dir = path.join(root, 'profiles/default');
  return { root, dir, call, snapshot, cleanup: () => fs.rmSync(root, { recursive: true, force: true }) };
}

/** 書き換えを当てた中身（範囲は元の中身での位置。後ろから当てる） */
function apply(text: string, edits: TextEdit[]): string {
  const lines = text.split('\n');
  const offset = (p: { line: number; character: number }) => lines.slice(0, p.line).reduce((n, l) => n + l.length + 1, 0) + p.character;
  return [...edits]
    .sort((a, b) => offset(b.range.start) - offset(a.range.start))
    .reduce((acc, e) => acc.slice(0, offset(e.range.start)) + e.newText + acc.slice(offset(e.range.end)), text);
}

describe('偽のサーバーの v0.2 の snapshot', () => {
  it('マクロ・タップダンス・コンボ・ショートカットの中身をディスクのファイルの一覧から返す', async () => {
    const { snapshot, cleanup } = await opened();
    try {
      expect(snapshot.macros?.map((m) => [m.index, m.name, m.steps.length])).toEqual([
        [0, 'Bracket Pair', 2],
        [1, 'Curly Brace Pair', 5],
        [2, 'Copy Selected', 0],
      ]);
      expect(snapshot.tapDances?.map((t) => t.name)).toEqual(['Layer 3 Toggle', 'Tab Escape']);
      expect(snapshot.combos?.[0]?.output.value?.text).toBe('LBracket');
      expect(snapshot.shortcuts?.[0]).toMatchObject({ name: '前のタブへ', value: { text: 'Command + Shift + [' } });
      expect(snapshot.references.macros.map((m) => m.name)).toEqual(['Bracket Pair', 'Curly Brace Pair', 'Copy Selected']);
    } finally {
      cleanup();
    }
  });
});

describe('偽のサーバーの並びの Change（12.3）', () => {
  it('insert・move・remove・注記を当てる順に当て、ファイル全体の書き換えにする', async () => {
    const { dir, call, snapshot, cleanup } = await opened();
    try {
      const macro = 'macros/00_bracket_pair.yml';
      const layer = 'layers/0_base.yml';
      const plan = await call('profile/planEdits', {
        profileId: snapshot.profileId,
        baseVersions: { [macro]: snapshot.files[macro], [layer]: snapshot.files[layer] },
        changes: [
          { op: 'insert', address: { file: macro, path: ['sequence'] }, index: 2, value: { action: 'delay', duration: 10 } },
          { op: 'move', address: { file: macro, path: ['sequence'] }, from: 2, to: 0 },
          { op: 'insert', address: { file: macro, path: ['sequence', 2, 'keys'] }, index: 1, value: 'Right' },
          { op: 'remove', address: { file: macro, path: ['sequence', 1, 'keys', 0] } },
          { address: { file: layer, path: ['mapping', 'left_hand', 'row0', 'Q'] }, value: 'メモ', field: 'note' },
          { op: 'remove', address: { file: layer, path: ['mapping', 'left_hand', 'row0', 'W'] } },
        ],
      });
      const result = plan.result as PlanEditsResult;
      const text = (rel: string) => apply(fs.readFileSync(path.join(dir, rel), 'utf-8'), result.files.find((f) => f.file === rel)!.edits);
      expect(text(macro)).toBe(
        '---\nname: Bracket Pair\ndescription: 角括弧ペア\nindex: 0\nsequence:\n- action: delay\n  duration: 10\n- action: tap\n  keys:\n  - RBracket\n- action: tap\n  keys: [Left, Right]\n',
      );
      const base = text(layer);
      expect(base).toContain('      Q: { key: Q, note: "メモ" }\n');
      expect(base).not.toContain('      W: W\n');
    } finally {
      cleanup();
    }
  });

  it('当てられない並びの Change は -32061', async () => {
    const { call, snapshot, cleanup } = await opened();
    try {
      const macro = 'macros/00_bracket_pair.yml';
      const response = await call('profile/planEdits', {
        profileId: snapshot.profileId,
        baseVersions: { [macro]: snapshot.files[macro] },
        changes: [{ op: 'remove', address: { file: macro, path: ['sequence', 9] } }],
      });
      expect(response.error).toMatchObject({ code: ErrorCodes.EditNotLocal, data: { reason: 'flowInsert' } });
    } finally {
      cleanup();
    }
  });

  it('yamlLines は 1 つの値で書いた keys に足すとフロー表記の並びにする', () => {
    const lines = ['sequence:', '- action: tap', '  keys: A'];
    applyChange(lines, { op: 'insert', address: { file: 'm', path: ['sequence', 0, 'keys'] }, index: 1, value: 'B' });
    expect(lines).toEqual(['sequence:', '- action: tap', '  keys: [A, B]']);
  });
});

describe('偽のサーバーの profile/planItemEdit（12.5）', () => {
  const plan = async (edit: object) => {
    const server = await opened();
    const response = await server.call('profile/planItemEdit', { profileId: server.snapshot.profileId, baseVersions: server.snapshot.files, edit });
    return { ...server, response, result: response.result as PlanItemEditResult };
  };

  it('追加は空いているいちばん小さい番号のファイルを作る', async () => {
    const { result, cleanup } = await plan({ op: 'create', kind: 'combo', name: 'Right Bracket!' });
    try {
      expect(result.files).toEqual([
        expect.objectContaining({ file: 'combos/01_right_bracket.yml', baseVersion: null, create: true }),
      ]);
      expect(result.files[0]?.edits[0]?.newText).toContain('output_key: KC_NO');
    } finally {
      cleanup();
    }
  });

  it('削除はファイルを消し、壊れる参照を返す', async () => {
    const { result, snapshot, cleanup } = await plan({ op: 'delete', kind: 'tapDance', name: 'Tab Escape' });
    try {
      expect(result.files).toEqual([{ file: 'tap_dance/04_tab_escape.yml', baseVersion: snapshot.files['tap_dance/04_tab_escape.yml'], create: false, delete: true, edits: [] }]);
      expect(result.references).toEqual([{ file: 'layers/0_base.yml', path: ['mapping', 'left_hand', 'row0', 'tab'] }]);
    } finally {
      cleanup();
    }
  });

  it('名前の変更は name の行・ファイル名・参照を書き換える', async () => {
    const { result, dir, cleanup } = await plan({ op: 'rename', kind: 'tapDance', name: 'Tab Escape', to: 'Tab Esc' });
    try {
      const [own, layer] = result.files;
      expect(own).toMatchObject({ file: 'tap_dance/04_tab_escape.yml', renameTo: 'tap_dance/04_tab_esc.yml' });
      expect(apply(fs.readFileSync(path.join(dir, own!.file), 'utf-8'), own!.edits)).toContain('name: Tab Esc\n');
      expect(apply(fs.readFileSync(path.join(dir, 'layers/0_base.yml'), 'utf-8'), layer!.edits)).toContain("tab: TapDance('Tab Esc')\n");
      expect(result.references).toHaveLength(1);
    } finally {
      cleanup();
    }
  });

  it('位置の名前の変更は position_map とレイヤーのキーを書き換え、同じグループに同じ名前があれば -32602', async () => {
    const { result, dir, cleanup } = await plan({ op: 'renamePosition', hand: 'left', row: 0, col: 0, to: 'esc' });
    try {
      const map = result.files.find((f) => f.file === 'position_map.yaml')!;
      expect(apply(fs.readFileSync(path.join(dir, map.file), 'utf-8'), map.edits)).toContain('  row0: [esc, Q, W, E, R, T]\n');
      expect(result.files.map((f) => f.file)).toEqual(['position_map.yaml', 'layers/0_base.yml', 'layers/1_symbols.yml']);
    } finally {
      cleanup();
    }
    const duplicate = await plan({ op: 'renamePosition', hand: 'left', row: 0, col: 0, to: 'Q' });
    try {
      expect(duplicate.response.error).toMatchObject({ code: ErrorCodes.InvalidParams, data: { field: 'edit.to' } });
    } finally {
      duplicate.cleanup();
    }
  });

  it('preset の展開（13.1）は preset: の行を同梱の定義の sequence: に置き換える。preset: でないマクロは -32602', async () => {
    const { result, dir, cleanup } = await plan({ op: 'expandPreset', kind: 'macro', name: 'Copy Selected' });
    try {
      expect(result.files.map((f) => f.file)).toEqual(['macros/02_copy_selected.yml']);
      const text = apply(fs.readFileSync(path.join(dir, 'macros/02_copy_selected.yml'), 'utf-8'), result.files[0]!.edits);
      expect(text).toBe(
        '---\nname: Copy Selected\nindex: 2\nsequence:\n' +
          ['down', 'tap', 'up', 'down', 'tap', 'up'].map((action, i) => `- action: ${action}\n  keys:\n  - ${['LGui', 'K', 'LGui', 'LGui', 'S', 'LGui'][i]}\n`).join(''),
      );
      expect(result.references).toEqual([]);
    } finally {
      cleanup();
    }
    const plain = await plan({ op: 'expandPreset', kind: 'macro', name: 'Bracket Pair' });
    try {
      expect(plain.response.error).toMatchObject({ code: ErrorCodes.InvalidParams, data: { field: 'edit.name' } });
    } finally {
      plain.cleanup();
    }
  });

  it('照合に失敗する名前は -32061（verify）', async () => {
    const { response, cleanup } = await plan({ op: 'rename', kind: 'macro', name: 'Bracket Pair', to: VERIFY_FAIL_NAME });
    try {
      expect(response.error).toMatchObject({ code: ErrorCodes.EditNotLocal, data: { reason: 'verify' } });
    } finally {
      cleanup();
    }
  });
});
