// テスト用の偽の device のサーバー（`cornix serve --device`。protocol.md の 14.）。本物のキーボードもブリッジも使わない。
// 実機とプロファイルを「場所 → 値の表記」の表として持ち、違う場所を DeviceChange にして返す。
// 反映すると実機の表がプロファイルの表になり、戻すとバックアップの表になる（プロセスの中だけ。ファイルには書かない）。
// プロファイルのファイルは読まない（保存しても比べる結果は変わらない）。
//
// 振る舞いを変えるもの:
//   環境変数 CORNIX_FAKE_DEVICE=<シナリオ>（main.ts が読む）と、通知 $/fake/configure（params は FakeDeviceConfig）
import * as crypto from 'node:crypto';
import type { Readable, Writable } from 'node:stream';
import {
  DeviceErrorCodes,
  type DeviceApplyResult,
  type DeviceBackup,
  type DeviceChange,
  type DeviceCompareResult,
  type DevicePhase,
  type DevicePlan,
  type DeviceUnavailableReason,
} from '../../src/deviceProtocol';
import { ErrorCodes, PROTOCOL_VERSION } from '../../src/protocol';
import { readMessages, writeMessage } from '../fake-server/server';

/** 場所 1 つ。DeviceChange から device と profile と text を除いたもの */
export type FakeLocation = Omit<DeviceChange, 'device' | 'profile' | 'text'>;

/** 実機とプロファイルの違い 1 件の元（初期の状態を作るのに使う） */
export type FakeDifference = FakeLocation & { device: string; profile: string };

/**
 * 偽の device のサーバーの振る舞い。$/fake/configure で途中から変えられる（書いた項目だけ変わる）。
 * - differences: 実機とプロファイルの違い（実機とプロファイルの表を作り直す。バックアップは残す）
 * - unavailable: 実機が使えない理由（null で使える）。どの device/* も -32070
 * - compileFailed: device/compare・device/apply が -32075 になる
 * - rejected: 書き込み禁止のキーコード。device/compare・device/apply が -32073 になる
 * - failWriteAfter: 反映・戻すでこの件数を書いたところで -32072 にする（null で失敗しない）
 * - remaining: 反映・戻すのあと読み直しても残る違いの場所の数（先頭から。既定 0）
 * - stepMs: 進み具合の 1 歩の間隔（ミリ秒。既定 0）。読む間の取り消しを試すときに延ばす
 */
export type FakeDeviceConfig = {
  differences?: FakeDifference[];
  unavailable?: DeviceUnavailableReason | null;
  compileFailed?: boolean;
  rejected?: string[] | null;
  failWriteAfter?: number | null;
  remaining?: number;
  stepMs?: number;
  warnings?: string[];
};

/** $/fake/configure（偽のサーバーだけの通知） */
export const FAKE_DEVICE_CONFIGURE = '$/fake/configure';

export const FAKE_KEYBOARD = { name: 'Cornix (fake)', uid: 'fake-0001' };

/** 既定の違い（fake-server の fixtures の Base / Symbols と同じ位置。図で枠を確かめられるように） */
export const DEFAULT_DIFFERENCES: FakeDifference[] = [
  { kind: 'key', layer: 0, key: { hand: 'left', row: 0, col: 1 }, position: 'Q', device: 'KC_A', profile: 'KC_Q' },
  { kind: 'key', layer: 0, key: { hand: 'right', row: 1, col: 5 }, position: 'enter', device: 'KC_NO', profile: 'KC_ENTER' },
  { kind: 'key', layer: 1, key: { hand: 'left', row: 0, col: 0 }, position: 'tab', device: 'KC_TRNS', profile: 'KC_ESCAPE' },
  { kind: 'encoder', layer: 0, encoder: { side: 'left', direction: 'cw' }, device: 'KC_NO', profile: 'KC_VOLU' },
  { kind: 'macro', index: 0, name: 'Bracket Pair', device: '(空)', profile: '[ ] ←' },
  { kind: 'setting', name: 'tapping_term', device: '200', profile: '180' },
];

/** シナリオ（CORNIX_FAKE_DEVICE）→ 初期の設定 */
export function scenarioConfig(name: string | undefined): FakeDeviceConfig {
  switch (name) {
    case undefined:
    case '':
    case 'default':
      return {};
    case 'same':
      return { differences: [] };
    case 'compileFailed':
      return { compileFailed: true };
    case 'rejected':
      return { rejected: ['QK_BOOT'] };
    case 'writeFail':
      return { failWriteAfter: 2 };
    case 'slow':
      return { stepMs: 200 };
    default: {
      const reason = /^unavailable:(platform|bridge|notConnected|timeout)$/.exec(name)?.[1] as DeviceUnavailableReason | undefined;
      if (reason) return { unavailable: reason };
      throw new Error(`知らないシナリオです: ${name}`);
    }
  }
}

export type FakeDeviceServerOptions = {
  /** ワークスペースのフォルダ（--root）。source と backup のパスに使う */
  root: string;
  /** --allow-writes を付けて起動した */
  allowWrites: boolean;
  config?: FakeDeviceConfig;
  log?: (line: string) => void;
  onExit?: (code: number) => void;
  /** バックアップの日時（テストで固定する） */
  now?: () => Date;
};

type Message = { jsonrpc?: string; id?: number | string | null; method?: string; params?: unknown };

class RpcError extends Error {
  constructor(
    readonly code: number,
    message: string,
    readonly data?: unknown,
  ) {
    super(message);
  }
}

type Table = Map<string, { location: FakeLocation; value: string }>;

type Backup = DeviceBackup & { table: Table };

const NOTIFICATIONS = new Set(['initialized', 'exit', '$/cancelRequest', FAKE_DEVICE_CONFIGURE]);

export function runFakeDeviceServer(input: Readable, output: Writable, options: FakeDeviceServerOptions): FakeDeviceServer {
  const server = new FakeDeviceServer(options, (message) => writeMessage(output, message));
  readMessages(input, (message) => void server.handle(message as Message), (error) => {
    writeMessage(output, { jsonrpc: '2.0', id: null, error: { code: ErrorCodes.ParseError, message: error.message } });
  });
  return server;
}

export class FakeDeviceServer {
  private state: 'uninitialized' | 'running' | 'shutdown' = 'uninitialized';
  private config: Required<Omit<FakeDeviceConfig, 'differences'>>;
  private device: Table = new Map();
  private profile: Table = new Map();
  private backups: Backup[] = [];
  /** 取り消しを受け付けるリクエスト（届いてから読み終えるまで） */
  private cancellable = new Set<number | string>();
  private cancelled = new Set<number | string>();
  /** リクエストは 1 つずつ処理する（本物と同じ） */
  private queue: Promise<void> = Promise.resolve();

  constructor(
    private readonly options: FakeDeviceServerOptions,
    private readonly send: (message: object) => void,
  ) {
    this.config = { unavailable: null, compileFailed: false, rejected: null, failWriteAfter: null, remaining: 0, stepMs: 0, warnings: [] };
    this.configure({ differences: DEFAULT_DIFFERENCES, ...options.config });
  }

  configure(config: FakeDeviceConfig): void {
    const { differences, ...rest } = config;
    this.config = { ...this.config, ...rest };
    if (differences) {
      this.device = new Map();
      this.profile = new Map();
      for (const { device, profile, ...location } of differences) {
        const id = locationId(location);
        this.device.set(id, { location, value: device });
        this.profile.set(id, { location, value: profile });
      }
    }
  }

  /** 今の実機の値（テストで確かめる用） */
  deviceValues(): Record<string, string> {
    return Object.fromEntries([...this.device].map(([id, { value }]) => [id, value]));
  }

  handle(message: Message): Promise<void> {
    const isRequest = message.id !== undefined;
    // 取り消しは処理の列に並べずにすぐ受ける
    if (message.method === '$/cancelRequest') {
      const id = (message.params as { id?: number | string } | undefined)?.id;
      if (id !== undefined && this.cancellable.has(id)) this.cancelled.add(id);
      return Promise.resolve();
    }
    if (isRequest && message.id !== null) this.cancellable.add(message.id!);
    this.queue = this.queue.then(() => this.process(message, isRequest)).catch((error: unknown) => this.log(`処理の失敗: ${String(error)}`));
    return this.queue;
  }

  private async process(message: Message, isRequest: boolean): Promise<void> {
    const method = message.method;
    if (typeof method !== 'string') {
      if (isRequest) this.reply(message.id, undefined, new RpcError(ErrorCodes.InvalidRequest, 'method がありません'));
      return;
    }
    if (NOTIFICATIONS.has(method)) {
      if (isRequest) return this.reply(message.id, undefined, new RpcError(ErrorCodes.InvalidRequest, `${method} は通知で送るメソッドです`));
      if (method === 'exit') this.options.onExit?.(this.state === 'shutdown' ? 0 : 1);
      if (method === FAKE_DEVICE_CONFIGURE) this.configure((message.params ?? {}) as FakeDeviceConfig);
      return;
    }
    if (!isRequest) return;
    try {
      if (this.cancelled.has(message.id!)) throw new RpcError(DeviceErrorCodes.RequestCancelled, '取り消しました');
      const result = await this.dispatch(method, (message.params ?? {}) as Record<string, unknown>, message.id!);
      this.reply(message.id, result);
    } catch (error) {
      if (error instanceof RpcError) this.reply(message.id, undefined, error);
      else this.reply(message.id, undefined, new RpcError(ErrorCodes.InternalError, String(error)));
    } finally {
      this.cancellable.delete(message.id!);
      this.cancelled.delete(message.id!);
    }
  }

  private async dispatch(method: string, params: Record<string, unknown>, id: number | string): Promise<unknown> {
    if (this.state === 'uninitialized' && method !== 'initialize') throw new RpcError(ErrorCodes.ServerNotInitialized, 'initialize の前です');
    if (this.state === 'shutdown') throw new RpcError(ErrorCodes.InvalidRequest, 'shutdown の後です');
    switch (method) {
      case 'initialize':
        return this.initialize(params);
      case 'shutdown':
        this.state = 'shutdown';
        return null;
      case 'device/compare':
        return this.compare(params, id);
      case 'device/apply':
        return this.apply(params, id);
      case 'device/backups':
        this.dirParam(params);
        return { backups: this.backups.map(({ table: _table, ...backup }) => backup) };
      case 'device/compareBackup':
        return this.compareBackup(params, id);
      case 'device/restore':
        return this.restore(params, id);
      default:
        throw new RpcError(ErrorCodes.MethodNotFound, `知らないメソッドです: ${method}`);
    }
  }

  private initialize(params: Record<string, unknown>): unknown {
    if (this.state !== 'uninitialized') throw new RpcError(ErrorCodes.InvalidRequest, 'initialize はもう受けています');
    if (params.protocolVersion !== PROTOCOL_VERSION) {
      throw new RpcError(ErrorCodes.ProtocolVersionMismatch, `約束の版が合いません（拡張: ${String(params.protocolVersion)}）`, {
        supported: [PROTOCOL_VERSION],
      });
    }
    this.state = 'running';
    return {
      protocolVersion: PROTOCOL_VERSION,
      serverInfo: { name: 'cornix', version: '0.0.0-fake', implementation: 'fake' },
      capabilities: { semanticValidation: false, keycodeCode: false, device: true, deviceWrites: this.options.allowWrites },
    };
  }

  private async compare(params: Record<string, unknown>, id: number | string): Promise<DeviceCompareResult> {
    const dir = this.dirParam(params);
    this.ensureCompiles();
    this.ensureAvailable();
    await this.read(id);
    return { plan: this.plan(this.profile), source: `${tmpDir(dir)}/build/layout.vil` };
  }

  private async compareBackup(params: Record<string, unknown>, id: number | string): Promise<DeviceCompareResult> {
    this.dirParam(params);
    const backup = this.backupParam(params);
    this.ensureAvailable();
    await this.read(id);
    return { plan: this.plan(backup.table), source: backup.path };
  }

  private async apply(params: Record<string, unknown>, id: number | string): Promise<DeviceApplyResult> {
    const dir = this.dirParam(params);
    const token = this.tokenParam(params);
    this.ensureWritable();
    this.ensureCompiles();
    this.ensureAvailable();
    return this.write(dir, this.profile, token, 'pre-apply', id);
  }

  private async restore(params: Record<string, unknown>, id: number | string): Promise<DeviceApplyResult> {
    const dir = this.dirParam(params);
    const backup = this.backupParam(params);
    const token = this.tokenParam(params);
    this.ensureWritable();
    this.ensureAvailable();
    return this.write(dir, backup.table, token, 'pre-restore', id);
  }

  /** 読む → 計画し直して token を確かめる → バックアップ → 書く → 読み直す */
  private async write(dir: string, target: Table, token: string, kind: 'pre-apply' | 'pre-restore', id: number | string): Promise<DeviceApplyResult> {
    await this.read(id);
    const plan = this.plan(target);
    if (plan.token !== token) throw new RpcError(DeviceErrorCodes.PlanChanged, '比べたあとでファイルか実機が変わりました。もう一度比べてください');
    if (plan.empty) return { applied: 0, backup: null, remaining: [] };

    const backup = this.saveBackup(dir, kind);
    const ids = this.diffIds(target);
    let applied = 0;
    for (const changeId of ids) {
      if (this.config.failWriteAfter !== null && applied >= this.config.failWriteAfter) {
        throw new RpcError(DeviceErrorCodes.WriteIncomplete, `${applied} 件を書いたところで切れました`, { applied, backup: backup.path });
      }
      await this.step('write', applied + 1, ids.length);
      const entry = target.get(changeId);
      if (applied >= this.config.remaining) {
        if (entry) this.device.set(changeId, { location: entry.location, value: entry.value });
        else this.device.delete(changeId);
      }
      applied += 1;
    }
    for (let i = 1; i <= ids.length; i += 1) await this.step('verify', i, ids.length);
    return { applied, backup: backup.path, remaining: this.plan(target).changes };
  }

  private async read(id: number | string): Promise<void> {
    const total = 4;
    try {
      for (let done = 1; done <= total; done += 1) {
        if (this.cancelled.has(id)) throw new RpcError(DeviceErrorCodes.RequestCancelled, '取り消しました');
        await this.step('read', done, total);
      }
      if (this.cancelled.has(id)) throw new RpcError(DeviceErrorCodes.RequestCancelled, '取り消しました');
    } finally {
      // 読み終えたら取り消せない（書き始めたら続ける）
      this.cancellable.delete(id);
    }
  }

  private async step(phase: DevicePhase, done: number, total: number): Promise<void> {
    if (this.config.stepMs > 0) await new Promise((resolve) => setTimeout(resolve, this.config.stepMs));
    this.send({ jsonrpc: '2.0', method: 'device/progress', params: { phase, done, total } });
  }

  private plan(target: Table): DevicePlan {
    if (this.config.rejected) {
      throw new RpcError(DeviceErrorCodes.PlanRejected, `${this.config.rejected.join(', ')} は安全のため書き込めません`, {
        keycodes: this.config.rejected,
      });
    }
    const changes = this.diffIds(target).map((id) => {
      const location = (target.get(id) ?? this.device.get(id))!.location;
      const device = this.device.get(id)?.value ?? '(なし)';
      const profile = target.get(id)?.value ?? '(なし)';
      return { ...location, device, profile, text: `${describe(location)}: ${device} → ${profile}` };
    });
    const token = crypto.createHash('sha256').update(JSON.stringify(changes)).digest('hex').slice(0, 16);
    return { token, empty: changes.length === 0, changes, warnings: [...this.config.warnings], keyboard: FAKE_KEYBOARD };
  }

  private diffIds(target: Table): string[] {
    const ids = new Set([...this.device.keys(), ...target.keys()]);
    return [...ids].filter((id) => this.device.get(id)?.value !== target.get(id)?.value).sort();
  }

  private saveBackup(dir: string, kind: 'pre-apply' | 'pre-restore'): Backup {
    const now = (this.options.now ?? (() => new Date()))();
    const stamp = now.toISOString().replace(/[-:]/g, '').replace('T', '-').slice(0, 15);
    const seq = this.backups.filter((b) => b.name.startsWith(`${stamp}-${kind}`)).length;
    const name = `${stamp}-${kind}${seq > 0 ? `-${seq + 1}` : ''}`;
    const table: Table = new Map([...this.device].map(([id, entry]) => [id, { ...entry }]));
    const backup: Backup = { name, path: `${tmpDir(dir)}/snapshots/${name}/layout.vil`, createdAt: now.toISOString(), kind, table };
    this.backups.unshift(backup);
    return backup;
  }

  private dirParam(params: Record<string, unknown>): string {
    if (typeof params.dir !== 'string') throw new RpcError(ErrorCodes.InvalidParams, 'params の dir がありません', { field: 'dir' });
    return params.dir;
  }

  private tokenParam(params: Record<string, unknown>): string {
    if (typeof params.token !== 'string') throw new RpcError(ErrorCodes.InvalidParams, 'params の token がありません', { field: 'token' });
    return params.token;
  }

  private backupParam(params: Record<string, unknown>): Backup {
    const name = params.backup;
    const backup = typeof name === 'string' ? this.backups.find((b) => b.name === name) : undefined;
    if (!backup) throw new RpcError(ErrorCodes.InvalidParams, `バックアップが見つかりません: ${String(name)}`, { field: 'backup' });
    return backup;
  }

  private ensureWritable(): void {
    if (!this.options.allowWrites) throw new RpcError(DeviceErrorCodes.WritesNotAllowed, '書き込みが許可されていません（--allow-writes なしで起動）');
  }

  private ensureCompiles(): void {
    if (!this.config.compileFailed) return;
    throw new RpcError(DeviceErrorCodes.CompileFailed, 'プロファイルに検証のエラーがあるので compile できません', {
      diagnostics: [{ severity: 'error', message: '知らないキーコードです: KC_FOO', source: 'structure', file: 'layers/0_base.yml' }],
    });
  }

  private ensureAvailable(): void {
    const reason = this.config.unavailable;
    if (reason) throw new RpcError(DeviceErrorCodes.DeviceUnavailable, `実機が使えません（${reason}）`, { reason });
  }

  private reply(id: Message['id'], result: unknown, error?: RpcError): void {
    if (error) {
      const body: Record<string, unknown> = { code: error.code, message: error.message };
      if (error.data !== undefined) body.data = error.data;
      this.send({ jsonrpc: '2.0', id: id ?? null, error: body });
    } else {
      this.send({ jsonrpc: '2.0', id, result: result ?? null });
    }
  }

  private log(line: string): void {
    this.options.log?.(`[fake-cornix-device] ${line}`);
  }
}

/** プロファイルの tmp（Application::Workspace の決まり。profiles/<名前> は tmp/profiles/<名前>） */
function tmpDir(dir: string): string {
  return dir.startsWith('profiles/') ? `tmp/${dir}` : 'tmp';
}

function locationId(location: FakeLocation): string {
  const parts: (string | number | undefined)[] = [location.kind, location.layer, location.index, location.name];
  if (location.key) parts.push(location.key.hand, location.key.row, location.key.col);
  if (location.encoder) parts.push(location.encoder.side, location.encoder.direction);
  return parts.map((part) => (part === undefined ? '' : String(part))).join('/');
}

function describe(location: FakeLocation): string {
  switch (location.kind) {
    case 'key':
      return `レイヤー${location.layer ?? 0} ${location.position ?? ''}`;
    case 'encoder':
      return `レイヤー${location.layer ?? 0} エンコーダ ${location.encoder?.side ?? ''} ${location.encoder?.direction ?? ''}`;
    case 'macro':
      return `マクロ M${location.index ?? 0}`;
    case 'tapDance':
      return `タップダンス${location.index ?? 0}`;
    case 'combo':
      return `コンボ${location.index ?? 0}`;
    case 'setting':
      return `設定 ${location.name ?? ''}`;
    default:
      return location.name ?? 'その他';
  }
}
