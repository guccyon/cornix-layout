// 実機の操作の流れ（src/device/deviceFlow.ts）を、偽の device のサーバー（test/fake-device-server/）とメモリの上の流れでつないで確かめる。
// VS Code の部分（保存・進み具合・ダイアログ）は偽のものに差し替える。本物のキーボードもブリッジも使わない。
import { PassThrough } from 'node:stream';
import { CancellationTokenSource, type CancellationToken } from 'vscode-jsonrpc';
import { afterEach, describe, expect, it } from 'vitest';
import type { DeviceBackup, DeviceInitializeResult, DeviceRequestMap, DeviceServerNotificationMap } from '../../src/deviceProtocol';
import { DeviceFlow, type DeviceClient, type DeviceHost, type DevicePrompts } from '../../src/device/deviceFlow';
import { DeviceStates } from '../../src/device/deviceStates';
import type { BackupPickItem, ConfirmText, Notice } from '../../src/device/deviceTexts';
import { CornixConnection } from '../../src/server/connection';
import { deviceServerArgs } from '../../src/device/deviceSettings';
import { runFakeDeviceServer, type FakeDeviceConfig, type FakeDeviceServer } from '../fake-device-server/server';

type DeviceConnection = CornixConnection<DeviceRequestMap, DeviceServerNotificationMap, DeviceInitializeResult>;

const DIR = 'profiles/default';
const connections: DeviceConnection[] = [];

afterEach(() => {
  for (const connection of connections.splice(0)) connection.dispose();
});

class FakePrompts implements DevicePrompts {
  readonly notices: Notice[] = [];
  readonly confirms: ConfirmText[] = [];
  readonly picks: BackupPickItem[][] = [];
  saveFirst: boolean | undefined;
  write = true;
  /** 確認のダイアログの間にすること（ファイルか実機が変わったことにする） */
  duringConfirm: (() => Promise<void>) | undefined;
  pick: ((items: BackupPickItem[]) => DeviceBackup | undefined) | undefined;

  confirmSaveFirst(): Promise<boolean> {
    return Promise.resolve(this.saveFirst ?? true);
  }
  async confirmWrite(text: ConfirmText): Promise<boolean> {
    this.confirms.push(text);
    await this.duringConfirm?.();
    return this.write;
  }
  pickBackup(items: BackupPickItem[]): Promise<DeviceBackup | undefined> {
    this.picks.push(items);
    return Promise.resolve(this.pick ? this.pick(items) : items[0]?.backup);
  }
  notify(notice: Notice): void {
    this.notices.push(notice);
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
  const client: DeviceClient = {
    request: (method, params, token) => {
      requests.push(method);
      return connection.request(method, params, token);
    },
    prepareWrites: () => Promise.resolve(),
  };
  const prompts = new FakePrompts();
  const progress: string[] = [];
  const titles: string[] = [];
  /** withProgress の取り消しのボタン（cancelOn の文が出たら押す） */
  let cancelOn: RegExp | undefined;
  const host: DeviceHost = {
    prompts,
    ensureSaved: () => Promise.resolve(options.saved ?? true),
    filesKey: () => 'files-1',
    profileName: () => 'default',
    withProgress: async (title, task) => {
      titles.push(title);
      const source = new CancellationTokenSource();
      return task((message) => {
        progress.push(message);
        if (cancelOn?.test(message)) source.cancel();
      }, source.token as CancellationToken);
    },
  };
  const changes: (string | undefined)[] = [];
  const states = new DeviceStates(options.allowWrites ?? true, (dir) => changes.push(dir));
  const flow = new DeviceFlow(client, host, states);
  connection.onNotification('device/progress', (params) => flow.handleProgress(params));
  return {
    fake,
    flow,
    states,
    prompts,
    requests,
    progress,
    titles,
    changes,
    cancelWhen: (pattern: RegExp) => {
      cancelOn = pattern;
    },
  };
}

describe('DeviceFlow（偽の device のサーバーと）', () => {
  it('比べる: 違いを状態にし、件数を知らせる。読む進み具合を出す', async () => {
    const t = await setup({ allowWrites: false });
    expect(await t.flow.compare(DIR)).toBe('different');
    const state = t.states.get(DIR);
    expect(state).toMatchObject({ status: 'different', busy: null, allowWrites: false });
    expect(state.changes).toHaveLength(6);
    expect(t.prompts.last).toMatchObject({ level: 'info', message: expect.stringContaining('6 件違います'), actions: [] });
    expect(t.progress).toContain('実機を読んでいます（4/4）');
    // 操作の間は busy（画面のボタンを押せなくする）
    expect(t.changes.length).toBeGreaterThanOrEqual(3);
  });

  it('比べる: 同じなら「同じです」。書き込みを許していれば違うときに「反映…」のボタン', async () => {
    const same = await setup({ config: { differences: [] } });
    expect(await same.flow.compare(DIR)).toBe('same');
    expect(same.states.get(DIR).status).toBe('same');
    expect(same.prompts.last?.message).toContain('同じです');

    const t = await setup();
    await t.flow.compare(DIR);
    expect(t.prompts.last?.actions).toEqual([{ label: '反映…', command: 'cornix.device.apply', args: [DIR] }]);
  });

  it('保存しないなら何も読まない', async () => {
    const t = await setup({ saved: false });
    expect(await t.flow.compare(DIR)).toBe('declined');
    expect(await t.flow.apply(DIR)).toBe('declined');
    expect(t.requests).toEqual([]);
    expect(t.states.get(DIR).status).toBe('unknown');
  });

  it('反映: 比べ直して確認のダイアログのあと token で書き、結果を知らせて「同じ」にする', async () => {
    const t = await setup();
    expect(await t.flow.apply(DIR)).toBe('written');
    expect(t.requests).toEqual(['device/compare', 'device/apply']);
    const confirm = t.prompts.confirms[0];
    expect(confirm?.message).toBe('実機（Cornix (fake)）に、プロファイル default との違い 6 件を書き込みます。');
    expect(confirm?.button).toBe('6 件を書き込む');
    expect(confirm?.detail).toContain('レイヤー0 Q: KC_A → KC_Q');
    expect(t.prompts.last).toMatchObject({ level: 'info', message: expect.stringMatching(/^6 件を書き込みました（バックアップ: tmp\/profiles\/default\/snapshots\/.*-pre-apply\/layout\.vil）。$/) });
    expect(t.states.get(DIR)).toMatchObject({ status: 'same', changes: [] });
    expect(t.progress.some((m) => m.startsWith('書き込んでいます'))).toBe(true);
    expect(t.progress.some((m) => m.startsWith('読み直して確かめています'))).toBe(true);
    expect(Object.values(t.fake.deviceValues())).toContain('KC_Q');
  });

  it('反映: 差分がなければダイアログを出さずに「同じです」', async () => {
    const t = await setup({ config: { differences: [] } });
    expect(await t.flow.apply(DIR)).toBe('same');
    expect(t.prompts.confirms).toEqual([]);
    expect(t.requests).toEqual(['device/compare']);
  });

  it('反映: 確認でやめたら書かない', async () => {
    const t = await setup();
    t.prompts.write = false;
    const before = t.fake.deviceValues();
    expect(await t.flow.apply(DIR)).toBe('declined');
    expect(t.requests).toEqual(['device/compare']);
    expect(t.fake.deviceValues()).toEqual(before);
    // 比べた結果は残る
    expect(t.states.get(DIR).status).toBe('different');
  });

  it('allowWrites が false なら、反映・戻すは設定を開くボタン付きで案内し、サーバーに何も送らない', async () => {
    const t = await setup({ allowWrites: false });
    expect(await t.flow.apply(DIR)).toBe('blocked');
    expect(t.prompts.last).toMatchObject({
      level: 'warning',
      message: expect.stringContaining('cornix.device.allowWrites'),
      actions: [{ label: '設定を開く', command: 'workbench.action.openSettings', args: ['cornix.device.allowWrites'] }],
    });
    expect(await t.flow.restore(DIR)).toBe('blocked');
    expect(t.requests).toEqual([]);
  });

  it('サーバーが --allow-writes なしで動いていれば -32074 を案内し、書かない', async () => {
    const t = await setup({ allowWrites: true, serverWrites: false });
    const before = t.fake.deviceValues();
    expect(await t.flow.apply(DIR)).toBe('failed');
    expect(t.prompts.last).toMatchObject({ level: 'warning', actions: [{ label: '設定を開く' }] });
    expect(t.fake.deviceValues()).toEqual(before);
  });

  it('読み直しで違いが残れば警告にし、残った違いを状態に出す', async () => {
    const t = await setup({ config: { remaining: 2 } });
    expect(await t.flow.apply(DIR)).toBe('written');
    expect(t.prompts.last).toMatchObject({ level: 'warning', message: expect.stringContaining('2 件が違ったまま'), actions: [{ label: '比べる' }] });
    expect(t.states.get(DIR)).toMatchObject({ status: 'different' });
    expect(t.states.get(DIR).changes).toHaveLength(2);
  });

  it('-32072: 書いた件数とバックアップの場所、もう一度反映すれば続きからそろうことを出し、「未確認」にする', async () => {
    const t = await setup({ config: { failWriteAfter: 2 } });
    expect(await t.flow.apply(DIR)).toBe('failed');
    const notice = t.prompts.last;
    expect(notice?.level).toBe('error');
    expect(notice?.message).toMatch(/^2 件を書いたところで止まりました.*バックアップ tmp\/profiles\/default\/snapshots\/.*-pre-apply\/layout\.vil にあります。.*続きからそろいます。$/);
    expect(notice?.actions).toEqual([{ label: 'もう一度', command: 'cornix.device.apply', args: [DIR] }]);
    expect(t.states.get(DIR).status).toBe('unknown');

    // もう一度反映すれば続きからそろう
    t.fake.configure({ failWriteAfter: null });
    expect(await t.flow.apply(DIR)).toBe('written');
    expect(t.prompts.confirms.at(-1)?.message).toContain('4 件');
    expect(t.states.get(DIR).status).toBe('same');
  });

  it('-32071: 確認の間に実機が変わったら書かずに、もう一度比べるよう案内する', async () => {
    const t = await setup();
    t.prompts.duringConfirm = async () => {
      t.fake.configure({ differences: [{ kind: 'setting', name: 'tapping_term', device: '250', profile: '180' }] });
    };
    expect(await t.flow.apply(DIR)).toBe('failed');
    expect(t.prompts.last).toMatchObject({ level: 'warning', message: expect.stringContaining('何も書き込みませんでした'), actions: [{ label: '比べる', command: 'cornix.device.compare' }] });
    expect(Object.values(t.fake.deviceValues())).toEqual(['250']);
    expect(t.states.get(DIR).status).toBe('unknown');
  });

  it('-32070: 理由ごとに直し方を出す', async () => {
    const cases: [string, RegExp, string[]][] = [
      ['platform', /macOS でだけ/, []],
      ['bridge', /xcode-select --install.*swiftc -O ext\/cornix_hid\/main\.swift -o tmp\/cornix-hid/, ['出力を表示']],
      ['notConnected', /つないでから、もう一度/, ['もう一度']],
      ['timeout', /応答しません/, ['もう一度']],
    ];
    for (const [reason, pattern, labels] of cases) {
      const t = await setup({ config: { unavailable: reason as FakeDeviceConfig['unavailable'] } });
      expect(await t.flow.compare(DIR)).toBe('failed');
      expect(t.prompts.last?.level).toBe('error');
      expect(t.prompts.last?.message).toMatch(pattern);
      expect(t.prompts.last?.actions.map((a) => a.label)).toEqual(labels);
    }
  });

  it('-32075 は検証のエラーを、-32073 は書き込めないキーコードを案内する', async () => {
    const compile = await setup({ config: { compileFailed: true } });
    expect(await compile.flow.compare(DIR)).toBe('failed');
    expect(compile.prompts.last?.message).toContain('layers/0_base.yml: 知らないキーコードです: KC_FOO');
    expect(compile.prompts.last?.actions).toEqual([{ label: '問題を表示', command: 'workbench.actions.view.problems' }]);

    const rejected = await setup({ config: { rejected: ['QK_BOOT'] } });
    expect(await rejected.flow.apply(DIR)).toBe('failed');
    expect(rejected.prompts.last?.message).toBe('QK_BOOT は安全のため実機に書き込めないので、反映のをやめました。プロファイル（かバックアップ）から外してください。');
    expect(rejected.prompts.confirms).toEqual([]);
  });

  it('読む間の取り消しは $/cancelRequest を送り、知らせずに終える（状態は変えない）', async () => {
    const t = await setup({ config: { stepMs: 20 } });
    t.cancelWhen(/実機を読んでいます（2\/4）/);
    expect(await t.flow.compare(DIR)).toBe('cancelled');
    expect(t.prompts.notices).toEqual([]);
    expect(t.states.get(DIR)).toMatchObject({ status: 'unknown', busy: null });
  });

  it('書き始めたあとの取り消しはサーバーに送らず、取り消せないことを出して最後まで書く', async () => {
    const t = await setup({ config: { stepMs: 5 } });
    t.cancelWhen(/^書き込んでいます（1\//);
    expect(await t.flow.apply(DIR)).toBe('written');
    expect(t.progress).toContain('書き込みを始めたので取り消せません。終わるまでお待ちください。');
    expect(t.states.get(DIR).status).toBe('same');
  });

  it('戻す: バックアップを新しい順に出し（既定は最新）、比べて確認のあと戻す。状態は「未確認」', async () => {
    const t = await setup();
    expect(await t.flow.restore(DIR)).toBe('declined');
    expect(t.prompts.last?.message).toContain('戻せるバックアップがありません');

    await t.flow.apply(DIR);
    t.fake.configure({ differences: [] }); // 反映のあと（実機 = プロファイル）
    await t.flow.apply(DIR); // 何もしない
    const applied = t.fake.deviceValues();
    expect(await t.flow.restore(DIR)).toBe('written');
    const items = t.prompts.picks.at(-1)!;
    expect(items.map((item) => item.description)).toEqual(['反映の前・最新']);
    expect(items[0]?.label).toBe('2026-10-22 01:00:00');
    expect(t.prompts.confirms.at(-1)?.message).toContain('バックアップ 2026-10-22 01:00:00（反映の前）に戻します。6 件を書き込みます。');
    expect(t.prompts.last?.message).toMatch(/^6 件を書き込んで、バックアップ 2026-10-22 01:00:00 に戻しました（バックアップ: .*-pre-restore\/layout\.vil）。$/);
    expect(t.fake.deviceValues()).not.toEqual(applied);
    expect(t.states.get(DIR).status).toBe('unknown');
    expect(t.requests.slice(-3)).toEqual(['device/backups', 'device/compareBackup', 'device/restore']);
  });

  it('戻す: 選ばなければ何もしない', async () => {
    const t = await setup();
    await t.flow.apply(DIR);
    t.prompts.pick = () => undefined;
    expect(await t.flow.restore(DIR)).toBe('declined');
    expect(t.requests.at(-1)).toBe('device/backups');
  });

  it('操作は 1 つずつ（最中に押されたら案内する）', async () => {
    const t = await setup({ config: { stepMs: 20 } });
    const first = t.flow.compare(DIR);
    expect(await t.flow.compare(DIR)).toBe('blocked');
    expect(t.prompts.last?.message).toContain('最中です');
    expect(await first).toBe('different');
  });
});

describe('deviceServerArgs', () => {
  it('allowWrites のときだけ --allow-writes を付ける', () => {
    expect(deviceServerArgs(false)).toEqual(['--device']);
    expect(deviceServerArgs(true)).toEqual(['--device', '--allow-writes']);
  });
});
