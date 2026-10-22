// v0.5（protocol.md の 15・ADR 022）: 番号の操作とショートカットの追加を未保存の変更に積むホストの道具。
// 偽のサーバーの planItemEdit の changes を 1 つの編集（editHistory.ts の recordEdit）として足し、元に戻す・やり直し・保存（planEdits）・外での変更の当て直しを確かめる
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { PassThrough } from 'node:stream';
import { describe, expect, it } from 'vitest';
import { recordEdit, type EditContext } from '../../src/editor/editHistory';
import { describeUnuse, itemEditErrorMessage, itemEditTitle, pendingItemEditLabel } from '../../src/editor/itemEdits';
import { PendingChanges, snapshotValueAt, type SavedValue } from '../../src/editor/pendingChanges';
import { describeAddress, describeChange, rebaseChanges, structureErrors } from '../../src/editor/rebase';
import { arrangeItems, indexAddress, snapshotItems } from '../../src/itemIndex';
import { ErrorCodes, type Address, type AnyChange, type PlanEditsResult, type PlanItemEditResult, type ProfileSnapshot, type TextEdit } from '../../src/protocol';
import { readMessages, runFakeServer } from '../fake-server/server';

const WORKSPACE = path.resolve(__dirname, '../integration/workspace');
const UNUSED_LAYER = '---\nname: iPad Base\nmapping:\n  left_hand:\n    row0:\n      Q: KC_A\n';
const UNUSED_MACRO = '---\nname: Old Paste\nindex:\nsequence:\n- action: tap\n  keys: [KC_V]\n';

async function opened(extra: Record<string, string | null> = {}) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'cornix-pending-item-'));
  fs.cpSync(WORKSPACE, root, { recursive: true });
  const dir = path.join(root, 'profiles/default');
  for (const [rel, text] of Object.entries(extra)) {
    if (text === null) fs.rmSync(path.join(dir, rel));
    else fs.writeFileSync(path.join(dir, rel), text);
  }
  const input = new PassThrough();
  const output = new PassThrough();
  const received: { id?: unknown; result?: unknown; error?: { code: number; message?: string; data?: unknown } }[] = [];
  runFakeServer(input, output, { root });
  readMessages(output, (message) => received.push(message as never), () => undefined);
  let id = 0;
  const call = async (method: string, params: object) => {
    const mine = ++id;
    const body = Buffer.from(JSON.stringify({ jsonrpc: '2.0', id: mine, method, params }), 'utf-8');
    input.write(`Content-Length: ${body.length}\r\n\r\n`);
    input.write(body);
    for (let i = 0; i < 200 && !received.some((m) => m.id === mine); i++) await new Promise((r) => setTimeout(r, 5));
    return received.find((m) => m.id === mine)!;
  };
  await call('initialize', { protocolVersion: '0.5', clientInfo: { name: 't', version: '0' } });
  const open = async () => (await call('profile/open', { dir: 'profiles/default' })).result as ProfileSnapshot;
  const snapshot = await open();
  return { dir, call, open, snapshot, cleanup: () => fs.rmSync(root, { recursive: true, force: true }) };
}

function apply(text: string, edits: TextEdit[]): string {
  const lines = text.split('\n');
  const offset = (p: { line: number; character: number }) => lines.slice(0, p.line).reduce((n, l) => n + l.length + 1, 0) + p.character;
  return [...edits]
    .sort((a, b) => offset(b.range.start) - offset(a.range.start))
    .reduce((acc, e) => acc.slice(0, offset(e.range.start)) + e.newText + acc.slice(offset(e.range.end)), text);
}

/** profileDocument.ts と同じ形の、今の snapshot に対する編集の状態 */
function documentState(initial: ProfileSnapshot) {
  const state = { snapshot: initial, epoch: 0 };
  const changes = new PendingChanges();
  const savedValue: SavedValue = (address, field) => snapshotValueAt(state.snapshot, address, field);
  const context: EditContext = {
    changes,
    savedValue,
    epoch: () => state.epoch,
    currentValue: (address, field) => {
      const pending = changes.pendingValue(address, field);
      return pending !== undefined ? pending : (snapshotValueAt(state.snapshot, address, field) ?? null);
    },
  };
  const usedLayers = () => arrangeItems(snapshotItems(state.snapshot, 'layer'), changes.list()).used.map((l) => [l.index, l.file]);
  return { state, changes, savedValue, context, usedLayers };
}

const SHORTCUT = (name: string): Address => ({ file: 'shortcuts.yaml', path: ['shortcuts', name] });

describe('番号とショートカットの行の畳み方（15.2）', () => {
  it('保存済みの値は snapshot の index（未使用は null）、未使用の項目の中身も引き、まだないショートカットは null', async () => {
    const { snapshot, cleanup } = await opened({ 'layers/ipad.yml': UNUSED_LAYER, 'macros/old_paste.yml': UNUSED_MACRO });
    try {
      expect(snapshotValueAt(snapshot, indexAddress('layers/1_symbols.yml'))).toBe(1);
      expect(snapshotValueAt(snapshot, indexAddress('layers/ipad.yml'))).toBeNull();
      expect(snapshotValueAt(snapshot, indexAddress('macros/old_paste.yml'))).toBeNull();
      expect(snapshotValueAt(snapshot, indexAddress('macros/00_bracket_pair.yml'))).toBe(0);
      expect(snapshotValueAt(snapshot, indexAddress('macros/99_none.yml'))).toBeUndefined();
      const ipadQ = snapshot.unused!.layers[0]!.keys.find((k) => k.value?.text !== undefined)!;
      expect(snapshotValueAt(snapshot, ipadQ.address)).toBe(ipadQ.value!.text);
      expect(snapshotValueAt(snapshot, SHORTCUT('まだない名前'))).toBeNull();
      expect(snapshotValueAt(snapshot, { file: 'other.yaml', path: ['shortcuts', 'x'] })).toBeUndefined();
      expect(describeAddress(snapshot, indexAddress('layers/ipad.yml'))).toBe('未使用のレイヤー iPad Base の番号');
      expect(describeAddress(snapshot, indexAddress('macros/00_bracket_pair.yml'))).toMatch(/^マクロ .+ の番号$/);
      expect(describeAddress(snapshot, SHORTCUT('新しい'))).toBe('ショートカット 新しい（追加）');
      expect(describeChange({ op: 'remove', address: indexAddress('layers/1_symbols.yml') })).toBe('未使用にする');
      expect(describeChange({ address: indexAddress('layers/ipad.yml'), value: 2 })).toBe('番号 2');
    } finally {
      cleanup();
    }
  });

  it('index の set / remove は保存済みと同じになったら持たない（未使用にしてから同じ番号で戻すと空）', () => {
    const saved: SavedValue = (address) => (address.file === 'layers/1_symbols.yml' ? 1 : address.file === 'layers/ipad.yml' ? null : undefined);
    const changes = new PendingChanges();
    changes.add({ op: 'remove', address: indexAddress('layers/1_symbols.yml') }, saved);
    expect(changes.list()).toEqual([{ op: 'remove', address: indexAddress('layers/1_symbols.yml') }]);
    changes.add({ address: indexAddress('layers/1_symbols.yml'), value: 1 }, saved);
    expect(changes.list()).toEqual([]);
    // 未使用のものの remove は持たない。set は持ち、同じ場所の次の set で置き換える
    changes.add({ op: 'remove', address: indexAddress('layers/ipad.yml') }, saved);
    expect(changes.list()).toEqual([]);
    changes.add({ address: indexAddress('layers/ipad.yml'), value: 2 }, saved);
    changes.add({ address: indexAddress('layers/ipad.yml'), value: 3 }, saved);
    expect(changes.list()).toEqual([{ address: indexAddress('layers/ipad.yml'), value: 3 }]);
    changes.add({ op: 'remove', address: indexAddress('layers/ipad.yml') }, saved);
    expect(changes.list()).toEqual([]);
    // 新しいショートカット（保存済みは null）の set は持ち、remove で打ち消す
    const shortcutSaved: SavedValue = () => null;
    changes.add({ address: SHORTCUT('A'), value: 'KC_A' }, shortcutSaved);
    expect(changes.size).toBe(1);
    changes.add({ op: 'remove', address: SHORTCUT('A') }, shortcutSaved);
    expect(changes.size).toBe(0);
    // assign（保存のあとの当て直し）でも、前の remove を残さない
    changes.add({ op: 'remove', address: indexAddress('layers/1_symbols.yml') }, saved);
    changes.assign(indexAddress('layers/1_symbols.yml'), 1, 1);
    expect(changes.list()).toEqual([]);
  });
});

describe('取り出す → 元に戻す → やり直す → 保存', () => {
  it('use の changes を 1 つの編集として足し、undo・redo で一緒に動き、planEdits で index の行を書く。保存のあとは何も残らない', async () => {
    const server = await opened({ 'layers/ipad.yml': UNUSED_LAYER });
    try {
      const doc = documentState(server.snapshot);
      const plan = (await server.call('profile/planItemEdit', {
        profileId: server.snapshot.profileId,
        baseVersions: server.snapshot.files,
        changes: doc.changes.list(),
        edit: { op: 'use', kind: 'layer', file: 'layers/ipad.yml' },
      })).result as PlanItemEditResult;
      const edit = recordEdit(doc.context, plan.changes!)!;
      expect(doc.changes.list()).toEqual([{ address: indexAddress('layers/ipad.yml'), value: 2 }]);
      expect(doc.usedLayers()).toEqual([[0, 'layers/0_base.yml'], [1, 'layers/1_symbols.yml'], [2, 'layers/ipad.yml']]);
      edit.undo();
      expect(doc.changes.list()).toEqual([]);
      expect(doc.usedLayers()).toHaveLength(2);
      edit.redo();
      expect(doc.usedLayers()).toHaveLength(3);

      // 保存（profile/planEdits を当ててディスクに書き、読み直す）
      const edits = (await server.call('profile/planEdits', {
        profileId: server.snapshot.profileId,
        baseVersions: doc.changes.baseVersions(server.snapshot.files),
        changes: doc.changes.list(),
      })).result as PlanEditsResult;
      const file = path.join(server.dir, 'layers/ipad.yml');
      fs.writeFileSync(file, apply(fs.readFileSync(file, 'utf-8'), edits.files[0]!.edits));
      expect(fs.readFileSync(file, 'utf-8')).toMatch(/^name: iPad Base\nindex: 2\n/m);
      const after = await server.open();
      // 保存のあとの当て直し（profileDocument.ts の runSave と同じ）: 画面の値を新しい snapshot に当てると、保存した値と同じなので外れる
      const screen = doc.context.currentValue(indexAddress('layers/ipad.yml'), 'key');
      doc.state.snapshot = after;
      doc.changes.clear();
      doc.changes.assign(indexAddress('layers/ipad.yml'), screen, doc.savedValue(indexAddress('layers/ipad.yml'), 'key'));
      expect(doc.changes.list()).toEqual([]);
      expect(doc.usedLayers()).toHaveLength(3);
      // 保存のあとの undo は、ディスクの値に対する変更（未使用にする）として残る
      edit.undo();
      expect(doc.changes.list()).toEqual([{ op: 'remove', address: indexAddress('layers/ipad.yml') }]);
    } finally {
      server.cleanup();
    }
  });

  it('未保存の変更があっても止めずに末尾に足し、それを当てた状態で決める（続けて取り出すと次の番号）。undo はその操作の分だけ戻す', async () => {
    const server = await opened({ 'layers/ipad.yml': UNUSED_LAYER, 'layers/mac.yml': UNUSED_LAYER.replace('iPad Base', 'Mac Base') });
    try {
      const doc = documentState(server.snapshot);
      const key = server.snapshot.layers[0]!.keys.find((k) => k.value?.text === 'Q')!.address;
      recordEdit(doc.context, [{ address: key, value: 'KC_B' }]);
      const use = async (file: string) =>
        (await server.call('profile/planItemEdit', {
          profileId: server.snapshot.profileId,
          baseVersions: server.snapshot.files,
          changes: doc.changes.list(),
          edit: { op: 'use', kind: 'layer', file },
        })).result as PlanItemEditResult;
      const first = recordEdit(doc.context, (await use('layers/ipad.yml')).changes!)!;
      const second = recordEdit(doc.context, (await use('layers/mac.yml')).changes!)!;
      expect(doc.changes.list()).toEqual([
        { address: key, value: 'KC_B' },
        { address: indexAddress('layers/ipad.yml'), value: 2 },
        { address: indexAddress('layers/mac.yml'), value: 3 },
      ]);
      second.undo();
      first.undo();
      expect(doc.changes.list()).toEqual([{ address: key, value: 'KC_B' }]);
      first.redo();
      second.redo();
      expect(doc.changes.size).toBe(3);
    } finally {
      server.cleanup();
    }
  });

  it('setIndex の入れ替えと番号の参照の書き換えは 1 つの編集で、undo で全部戻す', async () => {
    const server = await opened();
    try {
      const doc = documentState(server.snapshot);
      const key = server.snapshot.layers[0]!.keys.find((k) => k.value?.text === 'Q')!.address;
      recordEdit(doc.context, [{ address: key, value: 'Macro(0)' }]);
      const plan = (await server.call('profile/planItemEdit', {
        profileId: server.snapshot.profileId,
        baseVersions: server.snapshot.files,
        changes: doc.changes.list(),
        edit: { op: 'setIndex', kind: 'macro', file: 'macros/00_bracket_pair.yml', index: 2 },
      })).result as PlanItemEditResult;
      const edit = recordEdit(doc.context, plan.changes!)!;
      // 参照の書き換えは同じキーの前の変更を置き換える（畳む）
      expect(doc.changes.list()).toEqual([
        { address: key, value: 'Macro(2)' },
        { address: indexAddress('macros/00_bracket_pair.yml'), value: 2 },
        { address: indexAddress('macros/02_copy_selected.yml'), value: 0 },
      ]);
      edit.undo();
      expect(doc.changes.list()).toEqual([{ address: key, value: 'Macro(0)' }]);
    } finally {
      server.cleanup();
    }
  });

  it('ショートカットの追加は行の set を積み、undo で外す', async () => {
    const server = await opened();
    try {
      const doc = documentState(server.snapshot);
      const plan = (await server.call('profile/planItemEdit', {
        profileId: server.snapshot.profileId,
        baseVersions: server.snapshot.files,
        changes: [],
        edit: { op: 'create', kind: 'shortcut', name: '次のタブへ', value: 'Command + Shift + ]' },
      })).result as PlanItemEditResult;
      const edit = recordEdit(doc.context, plan.changes!)!;
      expect(doc.changes.list()).toEqual([{ address: SHORTCUT('次のタブへ'), value: 'Command + Shift + ]' }]);
      // 保存できる（runSave は planEdits の構造の error が増えれば止める）
      const edits = (await server.call('profile/planEdits', {
        profileId: server.snapshot.profileId,
        baseVersions: doc.changes.baseVersions(server.snapshot.files),
        changes: doc.changes.list(),
      })).result as PlanEditsResult;
      expect(structureErrors(edits.diagnostics, server.snapshot.diagnostics)).toEqual([]);
      edit.undo();
      expect(doc.changes.list()).toEqual([]);
    } finally {
      server.cleanup();
    }
  });
});

describe('未使用にするときの確認と、失敗の知らせ', () => {
  it('unuse で壊れる参照があるときの文は件数と場所を出し、すぐ書くとは言わない', async () => {
    const server = await opened();
    try {
      const edit = { op: 'unuse', kind: 'layer', file: 'layers/1_symbols.yml' } as const;
      const plan = (await server.call('profile/planItemEdit', { profileId: server.snapshot.profileId, baseVersions: server.snapshot.files, edit })).result as PlanItemEditResult;
      const count = plan.references.length;
      expect(count).toBeGreaterThan(0);
      const { message, detail } = describeUnuse(edit, plan, (address) => describeAddress(server.snapshot, address), 'Symbols');
      expect(message).toContain('レイヤー Symbols を未使用にします。');
      expect(message).toContain(`${count} 件`);
      expect(message).toContain('未保存の変更に積みます');
      expect(message).not.toContain('すぐにファイルに書きます');
      expect(detail.split('\n')).toHaveLength(count + 1);
      expect(detail.split('\n')[1]).toMatch(/^レイヤー 0 /);
    } finally {
      server.cleanup();
    }
  });

  it('編集の名前と、-32602 の知らせ', () => {
    const use = { op: 'use', kind: 'layer', file: 'layers/ipad.yml' } as const;
    expect(pendingItemEditLabel(use, 'iPad Base')).toBe('レイヤー iPad Base を使い始める');
    expect(pendingItemEditLabel({ op: 'unuse', kind: 'macro', file: 'macros/a.yml' }, 'A')).toBe('マクロ A を未使用にする');
    expect(pendingItemEditLabel({ op: 'setIndex', kind: 'tapDance', file: 'tap_dance/a.yml', index: 3 }, 'A')).toBe('タップダンス A の番号を 3 に変える');
    expect(pendingItemEditLabel({ op: 'create', kind: 'shortcut', name: 'X', value: 'KC_A' })).toBe('ショートカット X を追加する');
    expect(itemEditTitle(use)).toBe('レイヤー（layers/ipad.yml）を使い始めます。');
    const error = { code: ErrorCodes.InvalidParams, message: '空いている番号がありません。先にどれかを未使用にしてください' };
    expect(itemEditErrorMessage(use, error, 'iPad Base')).toBe('レイヤー iPad Base を使い始められませんでした（空いている番号がありません。先にどれかを未使用にしてください）');
    expect(itemEditErrorMessage({ op: 'unuse', kind: 'layer', file: 'l.yml' }, error, 'L')).toMatch(/^レイヤー L を未使用にできませんでした/);
    expect(itemEditErrorMessage({ op: 'setIndex', kind: 'layer', file: 'l.yml', index: 4 }, error, 'L')).toMatch(/^レイヤー L の番号を 4 に変えられませんでした/);
    expect(itemEditErrorMessage({ op: 'create', kind: 'shortcut', name: 'X', value: 'KC_A' }, error)).toMatch(/^ショートカット X を追加できませんでした/);
  });
});

describe('外での変更の当て直し（7.3）', () => {
  it('index の set とショートカットの行の追加は、外で変わっていなければそのまま当て直し、ファイルが消えたら当て直せない', async () => {
    const server = await opened({ 'layers/ipad.yml': UNUSED_LAYER });
    try {
      const before = server.snapshot;
      const pending: AnyChange[] = [
        { address: indexAddress('layers/ipad.yml'), value: 2 },
        { op: 'remove', address: indexAddress('layers/1_symbols.yml') },
        { address: SHORTCUT('新しい'), value: 'KC_A' },
      ];
      const valueBefore = (address: Address, field: 'key' | 'note') => snapshotValueAt(before, address, field);
      // 外でほかのファイル（マクロ）を書き換えた
      const macro = path.join(server.dir, 'macros/00_bracket_pair.yml');
      fs.writeFileSync(macro, fs.readFileSync(macro, 'utf-8').replace(/description: .*/, 'description: 外で変えた'));
      const changed = await server.open();
      expect(rebaseChanges(pending, valueBefore, changed, before.files)).toEqual({ kept: pending, conflicts: [], lost: [] });

      // 外で同じ名前のショートカットを足した → 選ばせる。取り出すファイルが消えた → 当て直せない
      fs.rmSync(path.join(server.dir, 'layers/ipad.yml'));
      fs.appendFileSync(path.join(server.dir, 'shortcuts.yaml'), '  新しい: KC_B\n');
      const after = await server.open();
      const result = rebaseChanges(pending, valueBefore, after, before.files);
      expect(result.kept).toEqual([pending[1]]);
      expect(result.lost).toEqual([pending[0]]);
      expect(result.conflicts).toEqual([{ change: pending[2], external: 'KC_B' }]);
    } finally {
      server.cleanup();
    }
  });
});
