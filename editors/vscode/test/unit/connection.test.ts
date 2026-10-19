// 拡張の接続（vscode-jsonrpc）と偽のサーバー（自前の枠）を、メモリの上の流れでつないで確かめる
import { PassThrough } from 'node:stream';
import { ResponseError } from 'vscode-jsonrpc/node';
import { afterEach, describe, expect, it } from 'vitest';
import { ErrorCodes, type ProfileDidChangeParams } from '../../src/protocol';
import { CornixConnection } from '../../src/server/connection';
import { runFakeServer, type FakeServerOptions } from '../fake-server/server';

const connections: CornixConnection[] = [];

async function connect(options: Partial<FakeServerOptions> = {}) {
  const toServer = new PassThrough();
  const toClient = new PassThrough();
  const exits: number[] = [];
  runFakeServer(toServer, toClient, { root: '/nonexistent-root', onExit: (code) => exits.push(code), ...options });
  const connection = await CornixConnection.connect({ input: toClient, output: toServer }, { clientName: 'test', clientVersion: '0.0.0' });
  connections.push(connection);
  return { connection, exits };
}

afterEach(() => {
  for (const connection of connections.splice(0)) connection.dispose();
});

describe('CornixConnection と偽のサーバー', () => {
  it('initialize で版とできることを受け取る', async () => {
    const { connection } = await connect();
    expect(connection.initializeResult).toMatchObject({
      protocolVersion: '0.1',
      serverInfo: { name: 'cornix' },
      capabilities: { semanticValidation: true, keycodeCode: true },
    });
  });

  it('profile/list と profile/open', async () => {
    const { connection } = await connect();
    const list = await connection.request('profile/list', {});
    expect(list.default).toBe('profiles/default');
    const snapshot = await connection.request('profile/open', { dir: 'profiles/default' });
    expect(snapshot).toMatchObject({ profileId: 'p1', name: 'default', status: 'ok' });
    // position_map のすべての位置（左右 24 キーずつ）を返し、割り当てのない位置は value が null
    expect(snapshot.positionMap).toHaveLength(48);
    expect(snapshot.layers[0]?.keys).toHaveLength(48);
    expect(snapshot.layers[1]?.keys.some((key) => key.value === null)).toBe(true);
    expect(snapshot.layers[0]?.keys.find((key) => key.hand === 'left' && key.row === 3 && key.col === 4)).toMatchObject({
      address: { file: 'layers/0_base.yml', path: ['mapping', 'left_hand', 'thumb_keys', 'middle'] },
      value: { text: 'LT1(Space)', kind: 'layerTap', display: { label: 'Space', tap: 'Space', hold: 'L1' } },
    });
  });

  it('知らないプロファイルは -32050（日本語の message と data）', async () => {
    const { connection } = await connect();
    const error = await connection.request('profile/open', { dir: 'profiles/nothing' }).catch((e: unknown) => e);
    expect(error).toBeInstanceOf(ResponseError);
    expect(error).toMatchObject({ code: ErrorCodes.ProfileNotFound, data: { dir: 'profiles/nothing' } });
  });

  it('候補は前方一致を上に、typed に解釈を入れる', async () => {
    const { connection } = await connect();
    const { profileId } = await connection.request('profile/open', { dir: 'profiles/default' });
    const result = await connection.request('keycode/candidates', { profileId, context: 'layerKey', query: 'Cmd', limit: 5 });
    expect(result.items[0]?.insertText).toBe('LGui');
    expect(result.typed).toMatchObject({ text: 'Cmd', canonical: 'LGui', kind: 'basic' });
  });

  it('日本語を含む中身もバイト数の枠で読み書きできる', async () => {
    const { connection } = await connect();
    const { profileId } = await connection.request('profile/open', { dir: 'profiles/default' });
    const result = await connection.request('keycode/inspect', { profileId, context: 'layerKey', text: "Shortcut('VS Code:基本操作:コマンドパレット')" });
    expect(result.value?.origin).toBe('presetShortcut');
    const unknown = await connection.request('keycode/inspect', { profileId, context: 'layerKey', text: 'ないキー' });
    expect(unknown.diagnostics[0]?.message).toBe('「ないキー」は読めない表記です');
  });

  it('workspace/didChangeFiles で開いているプロファイルの profile/didChange が来る', async () => {
    const { connection } = await connect();
    const { profileId } = await connection.request('profile/open', { dir: 'profiles/default' });
    const received = new Promise<ProfileDidChangeParams>((resolve) => connection.onNotification('profile/didChange', resolve));
    await connection.notify('workspace/didChangeFiles', { changes: [{ path: 'profiles/default/layers/0_base.yml', type: 'changed' }] });
    await expect(received).resolves.toMatchObject({ profileId, files: { 'layers/0_base.yml': null } });
  });

  it('shutdown と exit で終わる', async () => {
    const { connection, exits } = await connect();
    await connection.shutdown();
    expect(exits).toEqual([0]);
  });
});
