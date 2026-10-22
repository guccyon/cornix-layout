// 実機の操作の流れ（比べる・反映・戻す。tasks-v0.4.md の決めたこと 3〜7、protocol.md の 14.）。
// vscode に依存しない（VS Code の部分は DeviceHost と DevicePrompts に分け、単体テストで偽の device のサーバーとつないで確かめる）。
import { CancellationTokenSource, type CancellationToken } from 'vscode-jsonrpc';
import {
  DeviceErrorCodes,
  type DeviceBackup,
  type DevicePhase,
  type DeviceProgressParams,
  type DeviceRequestMap,
  type DeviceRequestMethod,
} from '../deviceProtocol';
import type { DeviceAction } from '../webviewMessages';
import type { DeviceStates } from './deviceStates';
import {
  backupLabel,
  backupPickItems,
  confirmApplyText,
  confirmRestoreText,
  deviceFailure,
  differentNotice,
  progressMessage,
  sameNotice,
  writeResultNotice,
  writesDisabledNotice,
  type BackupPickItem,
  type ConfirmText,
  type Notice,
} from './deviceTexts';

/** device のサーバーへのリクエスト（DeviceServer） */
export interface DeviceClient {
  request<M extends DeviceRequestMethod>(
    method: M,
    params: DeviceRequestMap[M]['params'],
    token?: CancellationToken,
  ): Promise<DeviceRequestMap[M]['result']>;
  /** 書き込みの前に、サーバーが --allow-writes 付きで動いているか確かめる（設定と違えば起動し直す） */
  prepareWrites(): Promise<void>;
}

/** 利用者に聞くこと・知らせること（統合テストが差し替える） */
export interface DevicePrompts {
  /** 未保存の変更を保存して続けるか（やめる・閉じたら false） */
  confirmSaveFirst(profile: string, pending: number): PromiseLike<boolean>;
  /** 書き込みの確認（モーダル。「次から聞かない」は付けない） */
  confirmWrite(text: ConfirmText): PromiseLike<boolean>;
  /** 戻す先のバックアップ（items は新しい順、先頭が既定） */
  pickBackup(items: BackupPickItem[]): PromiseLike<DeviceBackup | undefined>;
  notify(notice: Notice): void;
}

export type ProgressTask<T> = (report: (message: string) => void, token: CancellationToken) => Promise<T>;

/** VS Code の側（プロファイルの保存・進み具合の表示） */
export interface DeviceHost {
  readonly prompts: DevicePrompts;
  /** 未保存の変更があれば保存を促して保存する。続けてよければ true */
  ensureSaved(dir: string): Promise<boolean>;
  /** 開いているプロファイルの設定ファイルの版（deviceStates.ts の filesKey）。開いていなければ undefined */
  filesKey(dir: string): string | undefined;
  /** 確認の文に出すプロファイルの名前 */
  profileName(dir: string): string;
  /** 進み具合を出しながら task を動かす（取り消しのボタン付き） */
  withProgress<T>(title: string, task: ProgressTask<T>): Promise<T>;
}

/** 操作の終わり方（テストと統合テストで確かめる） */
export type DeviceOutcome = 'same' | 'different' | 'written' | 'declined' | 'blocked' | 'cancelled' | 'failed';

export class DeviceFlow {
  /** そのとき進み具合を出している先（device/progress の通知を流す） */
  private sink: ((progress: DeviceProgressParams) => void) | undefined;

  constructor(
    private readonly client: DeviceClient,
    private readonly host: DeviceHost,
    private readonly states: DeviceStates,
  ) {}

  /** device/progress の通知（サーバー → 拡張） */
  handleProgress(progress: DeviceProgressParams): void {
    this.sink?.(progress);
  }

  run(action: DeviceAction, dir: string): Promise<DeviceOutcome> {
    switch (action) {
      case 'compare':
        return this.compare(dir);
      case 'apply':
        return this.apply(dir);
      case 'restore':
        return this.restore(dir);
    }
  }

  /** 比べる（読むだけ。14.3）。保存済みのファイルと実機を比べる */
  compare(dir: string): Promise<DeviceOutcome> {
    return this.exclusive(dir, 'compare', async () => {
      if (!(await this.host.ensureSaved(dir))) return 'declined';
      const files = this.host.filesKey(dir);
      const { plan } = await this.progress('Cornix: 実機と比べています', (token) => this.client.request('device/compare', { dir }, token));
      this.states.setCompared(dir, plan.changes, files);
      this.notify(plan.empty ? sameNotice(plan) : differentNotice(plan, dir, this.states.writesAllowed));
      return plan.empty ? 'same' : 'different';
    });
  }

  /** 反映（14.4）。比べ直して確認のダイアログのあと、その token で書く */
  apply(dir: string): Promise<DeviceOutcome> {
    if (!this.states.writesAllowed) return this.blocked(writesDisabledNotice('apply'));
    return this.exclusive(dir, 'apply', async () => {
      if (!(await this.host.ensureSaved(dir))) return 'declined';
      await this.client.prepareWrites();
      const files = this.host.filesKey(dir);
      const { plan } = await this.progress('Cornix: 実機と比べています', (token) => this.client.request('device/compare', { dir }, token));
      this.states.setCompared(dir, plan.changes, files);
      if (plan.empty) {
        this.notify(sameNotice(plan));
        return 'same';
      }
      if (!(await this.host.prompts.confirmWrite(confirmApplyText(plan, this.host.profileName(dir))))) return 'declined';
      const result = await this.progress('Cornix: 実機に反映しています', (token) =>
        this.client.request('device/apply', { dir, token: plan.token }, token),
      );
      this.states.setCompared(dir, result.remaining, files);
      this.notify(result.applied === 0 && result.remaining.length === 0 ? sameNotice(plan) : writeResultNotice(result, 'apply', dir));
      return result.applied === 0 ? 'same' : 'written';
    });
  }

  /** 戻す（14.5）。バックアップを選び、比べて確認のダイアログのあと、その token で書く */
  restore(dir: string): Promise<DeviceOutcome> {
    if (!this.states.writesAllowed) return this.blocked(writesDisabledNotice('restore'));
    return this.exclusive(dir, 'restore', async () => {
      await this.client.prepareWrites();
      const { backups } = await this.client.request('device/backups', { dir });
      if (backups.length === 0) {
        this.notify({ level: 'info', message: '戻せるバックアップがありません（反映の前などに取ったものが、ここに並びます）。', actions: [] });
        return 'declined';
      }
      const backup = await this.host.prompts.pickBackup(backupPickItems(backups));
      if (!backup) return 'declined';
      const { plan } = await this.progress('Cornix: 実機とバックアップを比べています', (token) =>
        this.client.request('device/compareBackup', { dir, backup: backup.name }, token),
      );
      if (plan.empty) {
        this.notify(sameNotice(plan, `バックアップ ${backupLabel(backup)}`));
        return 'same';
      }
      if (!(await this.host.prompts.confirmWrite(confirmRestoreText(plan, backup)))) return 'declined';
      const result = await this.progress('Cornix: 実機をバックアップから戻しています', (token) =>
        this.client.request('device/restore', { dir, backup: backup.name, token: plan.token }, token),
      );
      // 実機はバックアップの状態になった。このプロファイルと同じかは分からない（もう一度読むと 10 秒かかるので、比べるのは利用者に任せる）
      this.states.setUnknown(dir);
      this.notify(writeResultNotice(result, 'restore', dir, backup));
      return 'written';
    });
  }

  /** 操作は 1 つずつ（実機は 1 台。device のサーバーも 1 つずつ処理する） */
  private async exclusive(dir: string, action: DeviceAction, run: () => Promise<DeviceOutcome>): Promise<DeviceOutcome> {
    if (this.states.busy) {
      return this.blocked({ level: 'info', message: '実機の操作の最中です。終わってから、もう一度試してください。', actions: [] });
    }
    this.states.setBusy(dir, action);
    try {
      return await run();
    } catch (error) {
      const failure = deviceFailure(error, action, dir);
      if (failure.resetState) this.states.setUnknown(dir);
      if (failure.notice) this.notify(failure.notice);
      return (error as { code?: unknown } | null)?.code === DeviceErrorCodes.RequestCancelled ? 'cancelled' : 'failed';
    } finally {
      this.states.setBusy(dir, null);
    }
  }

  /**
   * 進み具合を出しながら 1 つのリクエストを送る。取り消しのボタンは読む間（phase: read）だけ効かせる（14.6）。
   * 書き始めたあとに押されたら、サーバーには送らず、取り消せないことを出す
   */
  private progress<T>(title: string, send: (token: CancellationToken) => Promise<T>): Promise<T> {
    return this.host.withProgress(title, async (report, outer) => {
      const source = new CancellationTokenSource();
      let phase: DevicePhase = 'read';
      this.sink = (progress) => {
        phase = progress.phase;
        report(progressMessage(progress));
      };
      const cancel = () => {
        if (phase === 'read') source.cancel();
        else report('書き込みを始めたので取り消せません。終わるまでお待ちください。');
      };
      const subscription = outer.onCancellationRequested(cancel);
      if (outer.isCancellationRequested) cancel();
      try {
        return await send(source.token);
      } finally {
        this.sink = undefined;
        subscription.dispose();
        source.dispose();
      }
    });
  }

  private blocked(notice: Notice): Promise<DeviceOutcome> {
    this.notify(notice);
    return Promise.resolve('blocked');
  }

  private notify(notice: Notice): void {
    this.host.prompts.notify(notice);
  }
}
