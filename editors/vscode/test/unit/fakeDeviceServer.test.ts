// 偽の device のサーバー（test/fake-device-server/）の振る舞いを確かめる（protocol.md の 14.）
import { PassThrough } from 'node:stream';
import { describe, expect, it } from 'vitest';
import { DeviceErrorCodes, type DeviceApplyResult, type DeviceBackupsResult, type DeviceCompareResult } from '../../src/deviceProtocol';
import { ErrorCodes, PROTOCOL_VERSION } from '../../src/protocol';
import { FAKE_DEVICE_CONFIGURE, runFakeDeviceServer, type FakeDeviceConfig } from '../fake-device-server/server';
import { readMessages } from '../fake-server/server';

type Received = { id?: unknown; method?: string; params?: unknown; result?: unknown; error?: { code: number; data?: unknown } };

function start(options: { allowWrites?: boolean; config?: FakeDeviceConfig } = {}) {
  const input = new PassThrough();
  const output = new PassThrough();
  const received: Received[] = [];
  let seconds = 0;
  runFakeDeviceServer(input, output, {
    root: '/workspace',
    allowWrites: options.allowWrites ?? true,
    config: options.config,
    now: () => new Date(Date.UTC(2026, 9, 22, 1, 0, seconds++)),
  });
  readMessages(output, (message) => received.push(message as Received), () => undefined);
  let nextId = 1;
  const send = (message: object) => {
    const body = Buffer.from(JSON.stringify({ jsonrpc: '2.0', ...message }), 'utf-8');
    input.write(`Content-Length: ${body.length}\r\n\r\n`);
    input.write(body);
  };
  const waitFor = async (id: number) => {
    for (let i = 0; i < 200; i++) {
      const found = received.find((m) => m.id === id);
      if (found) return found;
      await new Promise((r) => setTimeout(r, 5));
    }
    throw new Error(`応答が来ません: ${id}`);
  };
  const request = async (method: string, params?: unknown) => {
    const id = nextId++;
    send({ id, method, params });
    return waitFor(id);
  };
  const result = async <T>(method: string, params?: unknown) => {
    const message = await request(method, params);
    if (message.error) throw new Error(JSON.stringify(message.error));
    return message.result as T;
  };
  return { send, request, result, received, waitFor, nextId: () => nextId++ };
}

async function initialized(options: Parameters<typeof start>[0] = {}) {
  const server = start(options);
  await server.result('initialize', { protocolVersion: PROTOCOL_VERSION, clientInfo: { name: 't', version: '0' } });
  return server;
}

const dir = { dir: 'profiles/default' };

describe('偽の device のサーバー', () => {
  it('initialize の capabilities に device と deviceWrites を返す', async () => {
    const server = start({ allowWrites: false });
    const result = await server.result<{ capabilities: object }>('initialize', { protocolVersion: PROTOCOL_VERSION, clientInfo: { name: 't', version: '0' } });
    expect(result.capabilities).toMatchObject({ device: true, deviceWrites: false });
  });

  it('比べる → 反映 → 同じになる。進み具合を知らせる', async () => {
    const server = await initialized();
    const compared = await server.result<DeviceCompareResult>('device/compare', dir);
    expect(compared.source).toBe('tmp/profiles/default/build/layout.vil');
    expect(compared.plan.empty).toBe(false);
    expect(compared.plan.changes[0]).toMatchObject({ device: expect.any(String), profile: expect.any(String), text: expect.any(String) });
    const key = compared.plan.changes.find((c) => c.kind === 'key');
    expect(key).toMatchObject({ layer: expect.any(Number), key: { hand: expect.any(String) }, position: expect.any(String) });

    const applied = await server.result<DeviceApplyResult>('device/apply', { ...dir, token: compared.plan.token });
    expect(applied).toMatchObject({ applied: compared.plan.changes.length, remaining: [] });
    expect(applied.backup).toMatch(/^tmp\/profiles\/default\/snapshots\/20261022-010000-pre-apply\/layout\.vil$/);
    const phases = new Set(server.received.filter((m) => m.method === 'device/progress').map((m) => (m.params as { phase: string }).phase));
    expect([...phases]).toEqual(['read', 'write', 'verify']);

    const again = await server.result<DeviceCompareResult>('device/compare', dir);
    expect(again.plan).toMatchObject({ empty: true, changes: [] });
  });

  it('token が違えば -32071、--allow-writes なしなら -32074 で何も書かない', async () => {
    const server = await initialized();
    const changed = await server.request('device/apply', { ...dir, token: 'nope' });
    expect(changed.error?.code).toBe(DeviceErrorCodes.PlanChanged);

    const readOnly = await initialized({ allowWrites: false });
    const { plan } = await readOnly.result<DeviceCompareResult>('device/compare', dir);
    const refused = await readOnly.request('device/apply', { ...dir, token: plan.token });
    expect(refused.error?.code).toBe(DeviceErrorCodes.WritesNotAllowed);
    const after = await readOnly.result<DeviceCompareResult>('device/compare', dir);
    expect(after.plan.token).toBe(plan.token);
  });

  it('戻すと反映の前に戻り、戻す前のバックアップも残る', async () => {
    const server = await initialized();
    const first = await server.result<DeviceCompareResult>('device/compare', dir);
    await server.result('device/apply', { ...dir, token: first.plan.token });
    const { backups } = await server.result<DeviceBackupsResult>('device/backups', dir);
    expect(backups.map((b) => b.kind)).toEqual(['pre-apply']);

    const restoring = await server.result<DeviceCompareResult>('device/compareBackup', { ...dir, backup: backups[0]!.name });
    expect(restoring.plan.changes).toHaveLength(first.plan.changes.length);
    await server.result('device/restore', { ...dir, backup: backups[0]!.name, token: restoring.plan.token });
    const back = await server.result<DeviceCompareResult>('device/compare', dir);
    expect(back.plan.token).toBe(first.plan.token);

    const after = await server.result<DeviceBackupsResult>('device/backups', dir);
    expect(after.backups.map((b) => b.kind)).toEqual(['pre-restore', 'pre-apply']);
    const unknown = await server.request('device/compareBackup', { ...dir, backup: 'nothing' });
    expect(unknown.error).toMatchObject({ code: ErrorCodes.InvalidParams, data: { field: 'backup' } });
  });

  it('使えない・compile できない・書き込み禁止・途中で切れたときのエラー', async () => {
    const server = await initialized({ config: { unavailable: 'bridge' } });
    expect((await server.request('device/compare', dir)).error).toMatchObject({ code: DeviceErrorCodes.DeviceUnavailable, data: { reason: 'bridge' } });
    // device/backups は実機を読まないので、使えなくても一覧を返す（Ruby と同じ。protocol.md の 14.5）
    expect((await server.request('device/backups', dir)).result).toEqual({ backups: [] });

    server.send({ method: FAKE_DEVICE_CONFIGURE, params: { unavailable: null, compileFailed: true } });
    expect((await server.request('device/compare', dir)).error).toMatchObject({ code: DeviceErrorCodes.CompileFailed, data: { diagnostics: [{ severity: 'error' }] } });

    server.send({ method: FAKE_DEVICE_CONFIGURE, params: { compileFailed: false, rejected: ['QK_BOOT'] } });
    expect((await server.request('device/compare', dir)).error).toMatchObject({ code: DeviceErrorCodes.PlanRejected, data: { keycodes: ['QK_BOOT'] } });

    server.send({ method: FAKE_DEVICE_CONFIGURE, params: { rejected: null, failWriteAfter: 2 } });
    const { plan } = await server.result<DeviceCompareResult>('device/compare', dir);
    const failed = await server.request('device/apply', { ...dir, token: plan.token });
    expect(failed.error).toMatchObject({ code: DeviceErrorCodes.WriteIncomplete, data: { applied: 2, backup: expect.stringContaining('pre-apply') } });
    const rest = await server.result<DeviceCompareResult>('device/compare', dir);
    expect(rest.plan.changes).toHaveLength(plan.changes.length - 2);
  });

  it('読む間は $/cancelRequest で -32800 になる', async () => {
    const server = await initialized({ config: { stepMs: 20 } });
    const id = server.nextId();
    server.send({ id, method: 'device/compare', params: dir });
    server.send({ method: '$/cancelRequest', params: { id } });
    const response = await server.waitFor(id);
    expect(response.error?.code).toBe(DeviceErrorCodes.RequestCancelled);
  });

  it('device/* のほかのメソッドは -32601', async () => {
    const server = await initialized();
    expect((await server.request('profile/list', {})).error?.code).toBe(ErrorCodes.MethodNotFound);
  });
});
