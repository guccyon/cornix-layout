// 実機への反映の流れ（src/device/deviceFlow.ts。プレビュー → 確定）を、偽の device のサーバー（test/fake-device-server/）とメモリの上の流れでつないで確かめる。
// VS Code の部分（保存・通知）は偽のものに差し替える。本物のキーボードもブリッジも使わない。
import { PassThrough } from 'node:stream';
import { afterEach, describe, expect, it } from 'vitest';
import type { DeviceInitializeResult, DeviceRequestMap, DeviceServerNotificationMap } from '../../src/deviceProtocol';
import { DeviceFlow, type DeviceClient, type DeviceHost, type DevicePrompts } from '../../src/device/deviceFlow';
import { DeviceStates } from '../../src/device/deviceStates';
import type { Notice } from '../../src/device/deviceTexts';
import { CornixConnection } from '../../src/server/connection';
import { deviceServerArgs } from '../../src/device/deviceSettings';
import type { DeviceTransfer } from '../../src/webviewMessages';
import { runFakeDeviceServer, type FakeDeviceConfig, type FakeDeviceServer } from '../fake-device-server/server';

type DeviceConnection = CornixConnection<DeviceRequestMap, DeviceServerNotificationMap, DeviceInitializeResult>;

const DIR = 'profiles/default';
const connections: DeviceConnection[] = [];

afterEach(() => {
  for (const connection of connections.splice(0)) connection.dispose();
});

class FakePrompts implements DevicePrompts {
  readonly notices: Notice[] = [];
  saveFirst: boolean | undefined;
  settingsOpened = 0;

  confirmSaveFirst(): Promise<boolean> {
    return Promise.resolve(this.saveFirst ?? true);
  }
  notify(notice: Notice): void {
    this.notices.push(notice);
  }
  openWriteSetting(): void {
    this.settingsOpened++;
  }
  get last(): Notice | undefined {
    return this.notices.at(-1);
  }
}

async function setup(options: { allowWrites?: boolean; serverWrites?: boolean; config?: FakeDeviceConfig; saved?: boolean } = {}) {
  const toServer = new PassThrough();
  const toClient = new PassThrough();
  let seconds = 0;
  const fake: FakeDeviceServer = runFakeDeviceServer(toServer, toClient, {
    root: '/workspace',
    allowWrites: options.serverWrites ?? options.allowWrites ?? true,
    config: options.config,
    now: () => new Date(Date.UTC(2026, 9, 22, 1, 0, seconds++)),
  });
  const connection = await CornixConnection.connect<DeviceRequestMap, DeviceServerNotificationMap, DeviceInitializeResult>(
    { input: toClient, output: toServer },
    { clientName: 'test', clientVersion: '0.0.0' },
  );
  connections.push(connection);

  const requests: string[] = [];
  let prepared = 0;
  const client: DeviceClient = {
    request: (method, params, token) => {
      requests.push(method);
      return connection.request(method, params, token);
    },
    prepareWrites: () => {
      prepared++;
      return Promise.resolve();
    },
  };
  const prompts = new FakePrompts();
  let files = 'files-1';
  let errors = 0;
  const host: DeviceHost = {
    prompts,
    ensureSaved: () => Promise.resolve(options.saved ?? true),
    filesKey: () => files,
    profileName: () => 'default',
    errorCount: () => errors,
  };
  /** 状態の移り変わり（transfer の step と進み具合） */
  const steps: (DeviceTransfer | null)[] = [];
  let onChange: ((transfer: DeviceTransfer | null) => void) | undefined;
  const states: DeviceStates = new DeviceStates(options.allowWrites ?? true, () => {
    const transfer = states.transferOf(DIR);
    steps.push(transfer);
    onChange?.(transfer);
  });
  const flow = new DeviceFlow(client, host, states);
  connection.onNotification('device/progress', (params) => flow.handleProgress(params));
  return {
    fake,
    flow,
    states,
    prompts,
    requests,
    steps,
    prepared: () => prepared,
    setFiles: (key: string) => {
      files = key;
      states.checkFiles(DIR, key);
    },
    setErrors: (count: number) => {
      errors = count;
    },
    onChange: (listener: (transfer: DeviceTransfer | null) => void) => {
      onChange = listener;
    },
  };
}

describe('DeviceFlow（偽の device のサーバーと）', () => {
  it('プレビュー: 実機を読んで違いを transfer に出す（読む進み具合も）。書き込みを許していなくてもできる', async () => {
    const t = await setup({ allowWrites: false });
    expect(await t.flow.preview(DIR)).toBe('different');
    const transfer = t.states.transferOf(DIR);
    expect(transfer).toMatchObject({ step: 'preview', profile: 'default', stale: false, plan: { empty: false, keyboard: { name: 'Cornix (fake)' } } });
    expect(transfer?.step === 'preview' && transfer.plan.changes).toHaveLength(6);
    expect(t.steps.some((s) => s?.step === 'reading' && s.progress?.done === 4 && s.progress.total === 4)).toBe(true);
    expect(t.requests).toEqual(['device/compare']);
    expect(t.prompts.notices).toEqual([]);
    expect(t.states.get(DIR)).toMatchObject({ busyElsewhere: false, allowWrites: false });
    expect(t.states.get('profiles/other').busyElsewhere).toBe(true);
  });

  it('プレビュー: 同じなら plan.empty のプレビュー（確定はできない）', async () => {
    const t = await setup({ config: { differences: [] } });
    expect(await t.flow.preview(DIR)).toBe('same');
    expect(t.states.transferOf(DIR)).toMatchObject({ step: 'preview', plan: { empty: true } });
    expect(await t.flow.confirm(DIR)).toBe('blocked');
    expect(t.flow.cancel(DIR)).toBe('declined');
    expect(t.states.transferOf(DIR)).toBeNull();
  });

  it('保存しないなら何も読まない', async () => {
    const t = await setup({ saved: false });
    expect(await t.flow.preview(DIR)).toBe('declined');
    expect(t.requests).toEqual([]);
    expect(t.states.transferOf(DIR)).toBeNull();
  });

  it('確定: プレビューの token で書き、結果を知らせてモーダルを閉じる', async () => {
    const t = await setup();
    await t.flow.preview(DIR);
    expect(await t.flow.confirm(DIR)).toBe('written');
    expect(t.requests).toEqual(['device/compare', 'device/apply']);
    expect(t.prepared()).toBe(1);
    expect(t.prompts.last).toMatchObject({ level: 'info', message: expect.stringMatching(/^6 件を書き込みました（バックアップ: tmp\/profiles\/default\/snapshots\/.*-pre-apply\/layout\.vil）。$/) });
    expect(t.steps.some((s) => s?.step === 'writing' && s.progress?.phase === 'write')).toBe(true);
    expect(t.steps.some((s) => s?.step === 'writing' && s.progress?.phase === 'verify')).toBe(true);
    expect(t.states.transferOf(DIR)).toBeNull();
    expect(Object.values(t.fake.deviceValues())).toContain('KC_Q');
  });

  it('やめる: プレビューを閉じ、何も書かない', async () => {
    const t = await setup();
    const before = t.fake.deviceValues();
    await t.flow.preview(DIR);
    expect(await t.flow.run('cancel', DIR)).toBe('declined');
    expect(t.states.transferOf(DIR)).toBeNull();
    expect(await t.flow.confirm(DIR)).toBe('blocked');
    expect(t.requests).toEqual(['device/compare']);
    expect(t.fake.deviceValues()).toEqual(before);
  });

  it('allowWrites が false なら、確定は設定を開くボタン付きで案内し、サーバーに何も送らない（プレビューは残す）', async () => {
    // サーバーの起動し直し（prepareWrites）はここでは偽物なので、サーバーは初めから書き込みを許しておく
    const t = await setup({ allowWrites: false, serverWrites: true });
    await t.flow.preview(DIR);
    expect(await t.flow.confirm(DIR)).toBe('blocked');
    expect(t.prompts.last).toMatchObject({
      level: 'warning',
      message: expect.stringContaining('cornix.device.allowWrites'),
      actions: [{ label: '設定を開く', command: 'workbench.action.openSettings', args: ['cornix.device.allowWrites'] }],
    });
    expect(t.requests).toEqual(['device/compare']);
    expect(t.states.transferOf(DIR)?.step).toBe('preview');
    await t.flow.run('openSettings', DIR);
    expect(t.prompts.settingsOpened).toBe(1);

    // 許したら、そのプレビューのまま確定できる
    t.states.setAllowWrites(true);
    expect(await t.flow.confirm(DIR)).toBe('written');
  });

  it('検証のエラーがあれば、実機を読む前に止めて知らせる（直せば読む）', async () => {
    const t = await setup();
    t.setErrors(3);
    expect(await t.flow.preview(DIR)).toBe('blocked');
    expect(t.prompts.last).toMatchObject({ level: 'warning', message: expect.stringContaining('検証のエラーが 3 件'), actions: [{ label: '問題を表示' }] });
    expect(t.requests).toEqual([]);
    expect(t.states.transferOf(DIR)).toBeNull();
    expect(t.states.busy).toBe(false);
    t.setErrors(0);
    expect(await t.flow.preview(DIR)).toBe('different');
  });

  it('プレビューのあとで検証のエラーが出たら確定させない', async () => {
    const t = await setup();
    await t.flow.preview(DIR);
    t.setErrors(2);
    expect(await t.flow.confirm(DIR)).toBe('blocked');
    expect(t.prompts.last).toMatchObject({ level: 'warning', message: expect.stringContaining('検証のエラーが 2 件'), actions: [{ label: '問題を表示' }] });
    expect(t.requests).toEqual(['device/compare']);
    expect(t.states.transferOf(DIR)?.step).toBe('preview');
  });

  it('プレビューのあとで設定ファイルが変わったら古いにし、確定させない。もう一度比べれば新しいプレビュー', async () => {
    const t = await setup();
    await t.flow.preview(DIR);
    t.setFiles('files-2');
    expect(t.states.transferOf(DIR)).toMatchObject({ step: 'preview', stale: true });
    expect(await t.flow.confirm(DIR)).toBe('blocked');
    expect(t.requests).toEqual(['device/compare']);
    expect(await t.flow.run('preview', DIR)).toBe('different');
    expect(t.states.transferOf(DIR)).toMatchObject({ step: 'preview', stale: false });
    expect(await t.flow.confirm(DIR)).toBe('written');
  });

  it('読んでいる間に設定ファイルが変わったら、読み終えたプレビューを古いにする', async () => {
    const t = await setup({ config: { stepMs: 10 } });
    t.onChange((transfer) => {
      if (transfer?.step === 'reading' && transfer.progress?.done === 1) t.setFiles('files-2');
    });
    expect(await t.flow.preview(DIR)).toBe('different');
    expect(t.states.transferOf(DIR)).toMatchObject({ step: 'preview', stale: true });
  });

  it('サーバーが --allow-writes なしで動いていれば -32074 を案内し、書かない', async () => {
    const t = await setup({ allowWrites: true, serverWrites: false });
    const before = t.fake.deviceValues();
    await t.flow.preview(DIR);
    expect(await t.flow.confirm(DIR)).toBe('failed');
    expect(t.prompts.last).toMatchObject({ level: 'warning', actions: [{ label: '設定を開く' }] });
    expect(t.fake.deviceValues()).toEqual(before);
    expect(t.states.transferOf(DIR)).toBeNull();
  });

  it('読み直しで違いが残れば警告にし、もう一度プレビューするボタンを付ける', async () => {
    const t = await setup({ config: { remaining: 2 } });
    await t.flow.preview(DIR);
    expect(await t.flow.confirm(DIR)).toBe('written');
    expect(t.prompts.last).toMatchObject({
      level: 'warning',
      message: expect.stringContaining('2 件が違ったまま'),
      actions: [{ label: 'もう一度プレビュー', command: 'cornix.device.apply', args: [DIR] }],
    });
  });

  it('-32072: 書いた件数とバックアップの場所、もう一度反映すれば続きからそろうことを出す', async () => {
    const t = await setup({ config: { failWriteAfter: 2 } });
    await t.flow.preview(DIR);
    expect(await t.flow.confirm(DIR)).toBe('failed');
    const notice = t.prompts.last;
    expect(notice?.level).toBe('error');
    expect(notice?.message).toMatch(/^2 件を書いたところで止まりました.*バックアップ tmp\/profiles\/default\/snapshots\/.*-pre-apply\/layout\.vil にあります。.*続きからそろいます。$/);
    expect(notice?.actions).toEqual([{ label: 'もう一度プレビュー', command: 'cornix.device.apply', args: [DIR] }]);
    expect(t.states.transferOf(DIR)).toBeNull();

    t.fake.configure({ failWriteAfter: null });
    await t.flow.preview(DIR);
    const transfer = t.states.transferOf(DIR);
    expect(transfer?.step === 'preview' && transfer.plan.changes).toHaveLength(4);
    expect(await t.flow.confirm(DIR)).toBe('written');
  });

  it('-32071: プレビューのあとで実機が変わったら書かずに、もう一度プレビューするよう案内する', async () => {
    const t = await setup();
    await t.flow.preview(DIR);
    t.fake.configure({ differences: [{ kind: 'setting', name: 'tapping_term', device: '250', profile: '180' }] });
    expect(await t.flow.confirm(DIR)).toBe('failed');
    expect(t.prompts.last).toMatchObject({
      level: 'warning',
      message: expect.stringContaining('何も書き込みませんでした'),
      actions: [{ label: 'もう一度プレビュー', command: 'cornix.device.apply' }],
    });
    expect(Object.values(t.fake.deviceValues())).toEqual(['250']);
    expect(t.states.transferOf(DIR)).toBeNull();
  });

  it('-32070: 理由ごとに直し方を出し、モーダルは閉じる', async () => {
    const cases: [string, RegExp, string[]][] = [
      ['platform', /macOS でだけ/, []],
      ['bridge', /xcode-select --install.*swiftc -O ext\/cornix_hid\/main\.swift -o tmp\/cornix-hid/, ['出力を表示']],
      ['notConnected', /つないでから、もう一度/, ['もう一度']],
      ['timeout', /応答しません/, ['もう一度']],
    ];
    for (const [reason, pattern, labels] of cases) {
      const t = await setup({ config: { unavailable: reason as FakeDeviceConfig['unavailable'] } });
      expect(await t.flow.preview(DIR)).toBe('failed');
      expect(t.prompts.last?.level).toBe('error');
      expect(t.prompts.last?.message).toMatch(pattern);
      expect(t.prompts.last?.actions.map((a) => a.label)).toEqual(labels);
      expect(t.states.transferOf(DIR)).toBeNull();
    }
  });

  it('-32075 は検証のエラーを、-32073 は書き込めないキーコードを案内する', async () => {
    const compile = await setup({ config: { compileFailed: true } });
    expect(await compile.flow.preview(DIR)).toBe('failed');
    expect(compile.prompts.last?.message).toContain('layers/0_base.yml: 知らないキーコードです: KC_FOO');
    expect(compile.prompts.last?.actions).toEqual([{ label: '問題を表示', command: 'workbench.actions.view.problems' }]);

    const rejected = await setup({ config: { rejected: ['QK_BOOT'] } });
    expect(await rejected.flow.preview(DIR)).toBe('failed');
    expect(rejected.prompts.last?.message).toBe('QK_BOOT は安全のため実機に書き込めないので、反映をやめました。プロファイルから外してください。');
  });

  it('読む間の「やめる」は $/cancelRequest を送り、知らせずにモーダルを閉じる', async () => {
    const t = await setup({ config: { stepMs: 20 } });
    t.onChange((transfer) => {
      if (transfer?.step === 'reading' && transfer.progress?.done === 2) t.flow.cancel(DIR);
    });
    expect(await t.flow.preview(DIR)).toBe('cancelled');
    expect(t.prompts.notices).toEqual([]);
    expect(t.states.transferOf(DIR)).toBeNull();
  });

  it('書いている間の「やめる」は効かず、最後まで書く', async () => {
    const t = await setup({ config: { stepMs: 5 } });
    await t.flow.preview(DIR);
    const cancels: string[] = [];
    t.onChange((transfer) => {
      if (transfer?.step === 'writing' && transfer.progress?.phase === 'write' && cancels.length === 0) cancels.push(t.flow.cancel(DIR));
    });
    expect(await t.flow.confirm(DIR)).toBe('written');
    expect(cancels).toEqual(['blocked']);
  });

  it('反映は一度に 1 つ（ほかのプロファイルの途中なら案内する）', async () => {
    const t = await setup({ config: { stepMs: 20 } });
    const first = t.flow.preview(DIR);
    expect(await t.flow.preview('profiles/other')).toBe('blocked');
    expect(t.prompts.last?.message).toContain('途中です');
    expect(await first).toBe('different');
    expect(await t.flow.preview('profiles/other')).toBe('blocked');
  });
});

describe('deviceServerArgs', () => {
  it('allowWrites のときだけ --allow-writes を付ける', () => {
    expect(deviceServerArgs(false)).toEqual(['--device']);
    expect(deviceServerArgs(true)).toEqual(['--device', '--allow-writes']);
  });
});
