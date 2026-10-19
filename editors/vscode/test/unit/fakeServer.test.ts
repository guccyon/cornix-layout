// 偽のサーバーの枠とライフサイクル（protocol.md の 1. と 4.）を生のバイト列で確かめる
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { PassThrough } from 'node:stream';
import { describe, expect, it } from 'vitest';
import { ErrorCodes } from '../../src/protocol';
import { readMessages, runFakeServer } from '../fake-server/server';

function start(root = '/nonexistent-root') {
  const input = new PassThrough();
  const output = new PassThrough();
  const received: { id?: unknown; result?: unknown; error?: { code: number } }[] = [];
  runFakeServer(input, output, { root });
  readMessages(output, (message) => received.push(message as never), () => undefined);
  const send = (message: object) => {
    const body = Buffer.from(JSON.stringify({ jsonrpc: '2.0', ...message }), 'utf-8');
    input.write(`Content-Length: ${body.length}\r\n\r\n`);
    input.write(body);
  };
  const next = async (count: number) => {
    for (let i = 0; i < 50 && received.length < count; i++) await new Promise((r) => setTimeout(r, 5));
    return received;
  };
  return { input, send, next };
}

describe('偽のサーバー', () => {
  it('initialize の前は -32002、shutdown の後は -32600', async () => {
    const { send, next } = start();
    send({ id: 1, method: 'profile/list', params: {} });
    send({ id: 2, method: 'initialize', params: { protocolVersion: '0.1', clientInfo: { name: 't', version: '0' } } });
    send({ id: 3, method: 'shutdown' });
    send({ id: 4, method: 'profile/list', params: {} });
    const messages = await next(4);
    expect(messages.map((m) => m.error?.code ?? 'ok')).toEqual([ErrorCodes.ServerNotInitialized, 'ok', 'ok', ErrorCodes.InvalidRequest]);
  });

  it('約束の版が違えば -32051', async () => {
    const { send, next } = start();
    send({ id: 1, method: 'initialize', params: { protocolVersion: '9.9', clientInfo: { name: 't', version: '0' } } });
    const [message] = await next(1);
    expect(message).toMatchObject({ id: 1, error: { code: ErrorCodes.ProtocolVersionMismatch, data: { supported: ['0.1'] } } });
  });

  it('知らないメソッドは -32601、JSON でなければ -32700', async () => {
    const { input, send, next } = start();
    send({ id: 1, method: 'initialize', params: { protocolVersion: '0.1', clientInfo: { name: 't', version: '0' } } });
    send({ id: 2, method: 'profile/nothing', params: {} });
    input.write('Content-Length: 3\r\n\r\n{x}');
    const messages = await next(3);
    expect(messages.slice(1).map((m) => [m.id, m.error?.code])).toEqual([
      [2, ErrorCodes.MethodNotFound],
      [null, ErrorCodes.ParseError],
    ]);
  });

  it('枠が途中で切れて届いても読める', async () => {
    const { input, next } = start();
    const body = Buffer.from(JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'initialize', params: { protocolVersion: '0.1', clientInfo: { name: '日本語', version: '0' } } }));
    const frame = Buffer.concat([Buffer.from(`Content-Length: ${body.length}\r\n\r\n`), body]);
    for (let i = 0; i < frame.length; i += 7) input.write(frame.subarray(i, i + 7));
    const [message] = await next(1);
    expect(message).toMatchObject({ id: 1, result: { protocolVersion: '0.1' } });
  });
});

// protocol.md の 5.2〜5.5 に書いた決まり（Ruby のサーバーと同じ振る舞い）
describe('偽のサーバーの profile/open・keycode/*', () => {
  async function opened() {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), 'cornix-fake-'));
    fs.mkdirSync(path.join(root, 'profiles/default/layers'), { recursive: true });
    fs.writeFileSync(path.join(root, 'profiles/default/metadata.yaml'), 'keyboard: cornix\n');
    fs.writeFileSync(path.join(root, 'profiles/default/layers/0_base.yaml'), 'name: Base\n');
    fs.writeFileSync(path.join(root, 'profiles/default/notes.yaml'), 'x\n');
    const server = start(root);
    server.send({ id: 1, method: 'initialize', params: { protocolVersion: '0.1', clientInfo: { name: 't', version: '0' } } });
    server.send({ id: 2, method: 'profile/open', params: { dir: 'profiles/default' } });
    const messages = await server.next(2);
    fs.rmSync(root, { recursive: true, force: true });
    return { ...server, snapshot: messages[1]?.result as { profileId: string; files: Record<string, string | null> } };
  }

  it('files は設定ファイルの構成のものだけで、settings/qmk_settings.yaml がなければ null', async () => {
    const { snapshot } = await opened();
    expect(Object.keys(snapshot.files).sort()).toEqual(['layers/0_base.yaml', 'metadata.yaml', 'settings/qmk_settings.yaml']);
    expect(snapshot.files['settings/qmk_settings.yaml']).toBeNull();
  });

  it('candidates の limit は 1 未満なら 1、query は前後の空白を除いて読む（typed の text は送ったまま）', async () => {
    const { send, next, snapshot } = await opened();
    send({ id: 3, method: 'keycode/candidates', params: { profileId: snapshot.profileId, context: 'layerKey', query: 'Cmd ', limit: 0 } });
    const result = (await next(3))[2]?.result as { items: unknown[]; typed: { text: string; canonical: string } | null; truncated: boolean };
    expect(result.items).toHaveLength(1);
    expect(result.typed).toMatchObject({ text: 'Cmd ', canonical: 'LGui' });
  });

  it('inspect の説明の title はショートカットの名前（同梱は「同梱のショートカット」）', async () => {
    const { send, next, snapshot } = await opened();
    send({ id: 3, method: 'keycode/inspect', params: { profileId: snapshot.profileId, context: 'layerKey', text: "Shortcut('前のタブへ')" } });
    send({ id: 4, method: 'keycode/inspect', params: { profileId: snapshot.profileId, context: 'layerKey', text: "Shortcut('VS Code:基本操作:コマンドパレット')" } });
    const messages = await next(4);
    const titles = messages.slice(2).map((m) => (m.result as { description: { title: string } }).description.title);
    expect(titles).toEqual(['ショートカット 前のタブへ', '同梱のショートカット VS Code:基本操作:コマンドパレット']);
  });
});

// 保存と外での変更のメソッド（protocol.md の 5.6・6・7）。統合テストのワークスペースを写して使う
describe('偽のサーバーの profile/validate・planEdits・saved・didChange', () => {
  const WORKSPACE = path.resolve(__dirname, '../integration/workspace');
  const base = 'layers/0_base.yml';
  const q = { file: base, path: ['mapping', 'left_hand', 'row0', 'Q'] };

  async function opened() {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), 'cornix-fake-save-'));
    fs.cpSync(WORKSPACE, root, { recursive: true });
    const server = start(root);
    let id = 10;
    /** これまでに届いた profile/didChange の数 */
    const didChanges = async () => (await server.next(0)).filter((m) => (m as { method?: string }).method === 'profile/didChange').length;
    const call = async (method: string, params: object) => {
      const before = (await server.next(0)).length;
      server.send({ id: ++id, method, params });
      const messages = await server.next(before + 1);
      // 通知（profile/didChange）が先に来ることもあるので、id の合うものを探す
      for (let i = 0; i < 50 && !messages.some((m) => m.id === id); i++) await new Promise((r) => setTimeout(r, 5));
      return messages.find((m) => m.id === id)!;
    };
    server.send({ id: 1, method: 'initialize', params: { protocolVersion: '0.1', clientInfo: { name: 't', version: '0' } } });
    await server.next(1);
    const open = await call('profile/open', { dir: 'profiles/default' });
    const snapshot = open.result as { profileId: string; files: Record<string, string> };
    const file = path.join(root, 'profiles/default', base);
    const notify = (method: string, params: object) => server.send({ method, params });
    return { root, file, call, notify, snapshot, didChanges, cleanup: () => fs.rmSync(root, { recursive: true, force: true }) };
  }

  it('validate は保存済みの問題に変更の問題を足し、読めない表記があれば構造の error だけを返す', async () => {
    const { call, snapshot, cleanup } = await opened();
    try {
      const baseVersions = { [base]: snapshot.files[base] };
      const semantic = await call('profile/validate', { profileId: snapshot.profileId, baseVersions, changes: [{ address: q, value: 'MO(9)' }] });
      const messages = (semantic.result as { diagnostics: { message: string; address?: { path: string[] } }[] }).diagnostics;
      expect(messages.map((d) => d.address?.path.at(-1) ?? null)).toEqual([null, 'Q', 'fn']);
      const structure = await call('profile/validate', { profileId: snapshot.profileId, baseVersions, changes: [{ address: q, value: 'ないキー' }] });
      expect(structure.result).toMatchObject({ diagnostics: [{ source: 'structure', address: q }] });
      expect((structure.result as { diagnostics: unknown[] }).diagnostics).toHaveLength(1);
    } finally {
      cleanup();
    }
  });

  it('planEdits は値の部分だけを書き換え、同じ値なら書き換えを作らない。版が違えば -32060', async () => {
    const { call, snapshot, file, cleanup } = await opened();
    try {
      const baseVersions = { [base]: snapshot.files[base] };
      const plan = await call('profile/planEdits', {
        profileId: snapshot.profileId,
        baseVersions,
        changes: [{ address: q, value: 'Escape' }, { address: { file: base, path: ['mapping', 'left_hand', 'row0', 'W'] }, value: 'W' }],
      });
      expect(plan.result).toMatchObject({
        files: [{ file: base, baseVersion: snapshot.files[base], create: false, edits: [{ range: { start: { line: 8 }, end: { line: 8 } }, newText: 'Escape' }] }],
      });
      expect((plan.result as { files: { edits: unknown[] }[] }).files[0]?.edits).toHaveLength(1);
      fs.appendFileSync(file, '# 外で書いた\n');
      const conflict = await call('profile/planEdits', { profileId: snapshot.profileId, baseVersions, changes: [{ address: q, value: 'Escape' }] });
      expect(conflict.error).toMatchObject({ code: ErrorCodes.VersionConflict, data: { files: { [base]: expect.stringMatching(/^sha256:/) } } });
    } finally {
      cleanup();
    }
  });

  it('saved はディスクから読み直し、知らされた版と違えば profile/didChange も送る。didChangeFiles は知っている版と違うときだけ', async () => {
    const { call, notify, snapshot, file, didChanges, cleanup } = await opened();
    try {
      fs.writeFileSync(file, fs.readFileSync(file, 'utf-8').replace('      Q: Q\n', '      Q: Escape\n'));
      const saved = await call('profile/saved', { profileId: snapshot.profileId, files: { [base]: 'sha256:stale' } });
      const result = saved.result as { files: Record<string, string>; layers: { keys: { address: { path: string[] }; value: { text: string } | null }[] }[] };
      expect(result.layers[0]?.keys.find((k) => k.address.path.at(-1) === 'Q')?.value?.text).toBe('Escape');
      expect(await didChanges()).toBe(1);
      // saved で覚えた版と同じなので知らせない。変われば知らせる
      const changes = [{ path: `profiles/default/${base}`, type: 'changed' }];
      notify('workspace/didChangeFiles', { changes });
      await call('profile/list', {});
      expect(await didChanges()).toBe(1);
      fs.appendFileSync(file, '# 外で書いた\n');
      notify('workspace/didChangeFiles', { changes });
      await call('profile/list', {});
      expect(await didChanges()).toBe(2);
    } finally {
      cleanup();
    }
  });

  it('レイヤーのファイルにない位置は value が null', async () => {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), 'cornix-fake-null-'));
    try {
      fs.mkdirSync(path.join(root, 'profiles/default/layers'), { recursive: true });
      fs.writeFileSync(path.join(root, 'profiles/default/metadata.yaml'), 'keyboard: cornix\n');
      fs.writeFileSync(path.join(root, 'profiles/default', base), 'name: Base\nmapping:\n  left_hand:\n    row0:\n      Q: Tab\n');
      const server = start(root);
      server.send({ id: 1, method: 'initialize', params: { protocolVersion: '0.1', clientInfo: { name: 't', version: '0' } } });
      server.send({ id: 2, method: 'profile/open', params: { dir: 'profiles/default' } });
      const snapshot = (await server.next(2))[1]?.result as { layers: { keys: { address: { path: string[] }; value: { text: string } | null }[] }[] };
      const keys = snapshot.layers[0]?.keys ?? [];
      expect(keys.find((k) => k.address.path.at(-1) === 'Q')?.value?.text).toBe('Tab');
      expect(keys.filter((k) => k.value === null)).toHaveLength(47);
    } finally {
      fs.rmSync(root, { recursive: true, force: true });
    }
  });
});
