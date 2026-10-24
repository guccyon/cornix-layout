// 偽のサーバーの v0.5（protocol.md の 15）: 未使用の項目の snapshot、番号の操作とショートカットの追加の Change、index とショートカットの行の planEdits
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { PassThrough } from 'node:stream';
import { describe, expect, it } from 'vitest';
import { indexAddress } from '../../src/itemIndex';
import { ErrorCodes, type AnyChange, type PlanEditsResult, type PlanItemEditResult, type ProfileSnapshot, type TextEdit } from '../../src/protocol';
import { readMessages, runFakeServer } from '../fake-server/server';

const WORKSPACE = path.resolve(__dirname, '../integration/workspace');

async function opened(extra: Record<string, string | null> = {}) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'cornix-fake-unused-'));
  fs.cpSync(WORKSPACE, root, { recursive: true });
  const dir = path.join(root, 'profiles/default');
  for (const [rel, text] of Object.entries(extra)) {
    if (text === null) fs.rmSync(path.join(dir, rel));
    else fs.writeFileSync(path.join(dir, rel), text);
  }
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
  await call('initialize', { protocolVersion: '0.5', clientInfo: { name: 't', version: '0' } });
  const snapshot = (await call('profile/open', { dir: 'profiles/default' })).result as ProfileSnapshot;
  return { dir, call, snapshot, cleanup: () => fs.rmSync(root, { recursive: true, force: true }) };
}

function apply(text: string, edits: TextEdit[]): string {
  const lines = text.split('\n');
  const offset = (p: { line: number; character: number }) => lines.slice(0, p.line).reduce((n, l) => n + l.length + 1, 0) + p.character;
  return [...edits]
    .sort((a, b) => offset(b.range.start) - offset(a.range.start))
    .reduce((acc, e) => acc.slice(0, offset(e.range.start)) + e.newText + acc.slice(offset(e.range.end)), text);
}

const UNUSED_LAYER = '---\nname: iPad Base\nmapping:\n  left_hand:\n    row0:\n      Q: KC_A\n';
const UNUSED_MACRO = '---\nname: Old Paste\nindex:\nsequence:\n- action: tap\n  keys: [KC_V]\n';

describe('偽のサーバーの未使用の項目（15.1）', () => {
  it('index: のないファイルは unused に返し、使っている一覧には入れない', async () => {
    const { snapshot, cleanup } = await opened({ 'layers/ipad.yml': UNUSED_LAYER, 'macros/old_paste.yml': UNUSED_MACRO });
    try {
      expect(snapshot.layers.map((l) => l.file)).toEqual(['layers/0_base.yml', 'layers/1_symbols.yml']);
      expect(snapshot.unused?.layers.map((l) => [l.file, l.name, l.index])).toEqual([['layers/ipad.yml', 'iPad Base', null]]);
      expect(snapshot.unused?.macros.map((m) => [m.file, m.index])).toEqual([['macros/old_paste.yml', null]]);
      expect(snapshot.macros?.map((m) => m.file)).not.toContain('macros/old_paste.yml');
      expect(snapshot.files['shortcuts.yaml']).toEqual(expect.any(String));
    } finally {
      cleanup();
    }
  });
});

describe('偽のサーバーの番号の操作（15.3）', () => {
  it('use は末尾の番号の set を返し、planEdits は name の行のあとに index を足す', async () => {
    const { dir, call, snapshot, cleanup } = await opened({ 'layers/ipad.yml': UNUSED_LAYER });
    try {
      const params = { profileId: snapshot.profileId, baseVersions: snapshot.files };
      const plan = (await call('profile/planItemEdit', { ...params, edit: { op: 'use', kind: 'layer', file: 'layers/ipad.yml' } })).result as PlanItemEditResult;
      expect(plan.files).toEqual([]);
      expect(plan.changes).toEqual([{ address: indexAddress('layers/ipad.yml'), value: 2 }]);
      // 未保存の use を当てた状態で、もう 1 つの use は次の番号
      const again = await call('profile/planItemEdit', { ...params, changes: plan.changes, edit: { op: 'use', kind: 'layer', file: 'layers/ipad.yml' } });
      expect(again.error).toMatchObject({ code: ErrorCodes.InvalidParams, data: { field: 'edit.file' } });
      const edits = (await call('profile/planEdits', { ...params, changes: plan.changes })).result as PlanEditsResult;
      const text = fs.readFileSync(path.join(dir, 'layers/ipad.yml'), 'utf-8');
      expect(apply(text, edits.files[0]!.edits)).toBe('---\nname: iPad Base\nindex: 2\nmapping:\n  left_hand:\n    row0:\n      Q: KC_A\n');
    } finally {
      cleanup();
    }
  });

  it('unuse は index の remove を返し、planEdits はその行を消す', async () => {
    const { dir, call, snapshot, cleanup } = await opened();
    try {
      const params = { profileId: snapshot.profileId, baseVersions: snapshot.files };
      const plan = (await call('profile/planItemEdit', { ...params, edit: { op: 'unuse', kind: 'layer', file: 'layers/1_symbols.yml' } })).result as PlanItemEditResult;
      expect(plan.changes).toEqual([{ op: 'remove', address: indexAddress('layers/1_symbols.yml') }]);
      expect(plan.references.length).toBeGreaterThan(0);
      const edits = (await call('profile/planEdits', { ...params, changes: plan.changes })).result as PlanEditsResult;
      const text = fs.readFileSync(path.join(dir, 'layers/1_symbols.yml'), 'utf-8');
      expect(apply(text, edits.files[0]!.edits)).not.toMatch(/^index:/m);
    } finally {
      cleanup();
    }
  });

  it('setIndex は使っている番号なら入れ替え、マクロの番号の参照を書き換える', async () => {
    const { call, snapshot, cleanup } = await opened();
    try {
      const key = snapshot.layers[0]!.keys.find((k) => k.value?.text === 'Q')!.address;
      const pending: AnyChange[] = [{ address: key, value: 'Macro(0)' }];
      const params = { profileId: snapshot.profileId, baseVersions: snapshot.files, changes: pending };
      const plan = (await call('profile/planItemEdit', { ...params, edit: { op: 'setIndex', kind: 'macro', file: 'macros/00_bracket_pair.yml', index: 2 } })).result as PlanItemEditResult;
      expect(plan.changes).toEqual([
        { address: indexAddress('macros/00_bracket_pair.yml'), value: 2 },
        { address: indexAddress('macros/02_copy_selected.yml'), value: 0 },
        { address: key, value: 'Macro(2)' },
      ]);
      expect(plan.references).toEqual([key]);
      // レイヤーの入れ替えでは、レイヤー操作（MO(1) など）の番号も新しい番号に書き換える（ADR 025）
      const layers = (await call('profile/planItemEdit', { ...params, edit: { op: 'setIndex', kind: 'layer', file: 'layers/0_base.yml', index: 1 } })).result as PlanItemEditResult;
      expect(layers.changes!.slice(0, 2)).toEqual([
        { address: indexAddress('layers/0_base.yml'), value: 1 },
        { address: indexAddress('layers/1_symbols.yml'), value: 0 },
      ]);
      const texts = new Map(snapshot.layers.flatMap((layer) => layer.keys.map((k) => [JSON.stringify(k.address), k.value?.text] as const)));
      const rewrites = layers.changes!.slice(2);
      expect(rewrites.length).toBeGreaterThan(0);
      for (const change of rewrites) {
        const before = texts.get(JSON.stringify(change.address));
        expect(before).toMatch(/\b(MO|TG|TO|TT|OSL|DF|PDF|LT|LM)\(?[01]\b/);
        expect((change as { value: unknown }).value).toBe(before!.replace(/([01])/, (n) => (n === '0' ? '1' : '0')));
      }
      expect(layers.references).toEqual(rewrites.map((c) => c.address));
      const out = await call('profile/planItemEdit', { ...params, edit: { op: 'setIndex', kind: 'layer', file: 'layers/0_base.yml', index: 10 } });
      expect(out.error).toMatchObject({ code: ErrorCodes.InvalidParams, data: { field: 'edit.index' } });
    } finally {
      cleanup();
    }
  });
});

describe('偽のサーバーの並び替え（15.3 の reorder）', () => {
  it('今の番号を小さい順に新しい並びへ当て、番号の参照を追従させる。同じ並びなら変更なし', async () => {
    const { call, snapshot, cleanup } = await opened();
    try {
      const key = snapshot.layers[0]!.keys.find((k) => k.value?.text === 'Q')!.address;
      const pending: AnyChange[] = [{ address: key, value: 'M2' }];
      const params = { profileId: snapshot.profileId, baseVersions: snapshot.files, changes: pending };
      const files = ['macros/02_copy_selected.yml', 'macros/00_bracket_pair.yml', 'macros/01_curly_brace_pair.yml'];
      const plan = (await call('profile/planItemEdit', { ...params, edit: { op: 'reorder', kind: 'macro', files } })).result as PlanItemEditResult;
      expect(plan.files).toEqual([]);
      expect(plan.changes!.slice(0, 3)).toEqual([
        { address: indexAddress('macros/02_copy_selected.yml'), value: 0 },
        { address: indexAddress('macros/00_bracket_pair.yml'), value: 1 },
        { address: indexAddress('macros/01_curly_brace_pair.yml'), value: 2 },
      ]);
      expect(plan.changes).toContainEqual({ address: key, value: 'M0' });
      const same = (await call('profile/planItemEdit', { ...params, edit: { op: 'reorder', kind: 'macro', files: [...files.slice(1), files[0]] } })).result as PlanItemEditResult;
      expect(same.changes).toEqual([]);
      const out = await call('profile/planItemEdit', { ...params, edit: { op: 'reorder', kind: 'macro', files: files.slice(1) } });
      expect(out.error).toMatchObject({ code: ErrorCodes.InvalidParams, data: { field: 'edit.files' } });
      // indexes を書けば files の順にその番号（抜け番を作れる）
      const layerFiles = snapshot.layers.map((layer) => layer.file);
      const spread = (await call('profile/planItemEdit', { ...params, edit: { op: 'reorder', kind: 'layer', files: layerFiles, indexes: layerFiles.map((_, i) => (i === 0 ? 9 : i)) } }))
        .result as PlanItemEditResult;
      expect(spread.changes![0]).toEqual({ address: indexAddress(layerFiles[0]!), value: 9 });
      const bad = await call('profile/planItemEdit', { ...params, edit: { op: 'reorder', kind: 'layer', files: layerFiles, indexes: layerFiles.map(() => 1) } });
      expect(bad.error).toMatchObject({ code: ErrorCodes.InvalidParams, data: { field: 'edit.indexes' } });
    } finally {
      cleanup();
    }
  });
});

describe('偽のサーバーのショートカットの追加（15.2・15.3）', () => {
  it('create は shortcuts の行の set を返し、planEdits は末尾に足す。shortcuts.yaml がなければ作る', async () => {
    const { dir, call, snapshot, cleanup } = await opened();
    try {
      const params = { profileId: snapshot.profileId, baseVersions: snapshot.files };
      const plan = (await call('profile/planItemEdit', { ...params, edit: { op: 'create', kind: 'shortcut', name: '次のタブへ', value: 'Command + Shift + ]' } }))
        .result as PlanItemEditResult;
      expect(plan.changes).toEqual([{ address: { file: 'shortcuts.yaml', path: ['shortcuts', '次のタブへ'] }, value: 'Command + Shift + ]' }]);
      const twice = await call('profile/planItemEdit', { ...params, changes: plan.changes, edit: { op: 'create', kind: 'shortcut', name: '次のタブへ', value: 'KC_A' } });
      expect(twice.error).toMatchObject({ code: ErrorCodes.InvalidParams, data: { field: 'edit.name' } });
      const edits = (await call('profile/planEdits', { ...params, changes: plan.changes })).result as PlanEditsResult;
      const text = fs.readFileSync(path.join(dir, 'shortcuts.yaml'), 'utf-8');
      expect(apply(text, edits.files[0]!.edits).trimEnd().split('\n').at(-1)).toBe('  次のタブへ: "Command + Shift + ]"');
    } finally {
      cleanup();
    }
    const fresh = await opened({ 'shortcuts.yaml': null });
    try {
      expect(fresh.snapshot.files['shortcuts.yaml']).toBeNull();
      const changes = [{ address: { file: 'shortcuts.yaml', path: ['shortcuts', 'A'] }, value: 'KC_A' }];
      const edits = (await fresh.call('profile/planEdits', { profileId: fresh.snapshot.profileId, baseVersions: fresh.snapshot.files, changes })).result as PlanEditsResult;
      expect(edits.files[0]).toMatchObject({ file: 'shortcuts.yaml', create: true, baseVersion: null });
      expect(edits.files[0]!.edits[0]!.newText).toBe('---\nshortcuts:\n  A: KC_A\n');
    } finally {
      fresh.cleanup();
    }
  });
});
