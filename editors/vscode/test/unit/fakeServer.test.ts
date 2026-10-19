// 偽のサーバーの枠とライフサイクル（protocol.md の 1. と 4.）を生のバイト列で確かめる
import { PassThrough } from 'node:stream';
import { describe, expect, it } from 'vitest';
import { ErrorCodes } from '../../src/protocol';
import { readMessages, runFakeServer } from '../fake-server/server';

function start() {
  const input = new PassThrough();
  const output = new PassThrough();
  const received: { id?: unknown; result?: unknown; error?: { code: number } }[] = [];
  runFakeServer(input, output, { root: '/nonexistent-root' });
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
