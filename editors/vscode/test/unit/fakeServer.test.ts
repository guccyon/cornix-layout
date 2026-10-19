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
