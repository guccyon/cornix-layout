// 実機への反映の流れ（プレビュー → 確定。tasks-v0.4.md の決めたこと 3〜7、protocol.md の 14.）。
// 編集フォームの節「デバイス転送」かコマンドで始め、実機を読んで違いを編集画面のモーダルに出し（DeviceStates の transfer）、
// 「確定」でその token のまま書く。「やめる」・読む間の取り消しは何も書かない。
// vscode に依存しない（VS Code の部分は DeviceHost と DevicePrompts に分け、単体テストで偽の device のサーバーとつないで確かめる）。
import { CancellationTokenSource, type CancellationToken } from 'vscode-jsonrpc';
import { DeviceErrorCodes, type DeviceProgressParams, type DeviceRequestMap, type DeviceRequestMethod } from '../deviceProtocol';
import { keyboardSpecFor } from '../keyboard';
import type { DeviceAction } from '../webviewMessages';
import type { DeviceStates } from './deviceStates';
import { deviceFailure, validationErrorNotice, writeResultNotice, writesDisabledNotice, type FailedStep, type Notice } from './deviceTexts';

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
  notify(notice: Notice): void;
  /** 設定 cornix.device.allowWrites を開く（モーダルの「設定を開く」） */
  openWriteSetting(): void;
}

/** VS Code の側（プロファイルの保存） */
export interface DeviceHost {
  readonly prompts: DevicePrompts;
  /** 未保存の変更があれば保存を促して保存する。続けてよければ true */
  ensureSaved(dir: string): Promise<boolean>;
  /** 開いているプロファイルの設定ファイルの版（deviceStates.ts の filesKey）。開いていなければ undefined */
  filesKey(dir: string): string | undefined;
  /** モーダルに出すプロファイルの名前 */
  profileName(dir: string): string;
  /** 保存済みのプロファイルの検証のエラーの数（あれば実機を読まず、確定もさせない） */
  errorCount(dir: string): number;
}

/**
 * 操作の終わり方（テストと統合テストで確かめる）。
 * preview: same（違いなし）・different（プレビューを出した）。confirm: written・same（書くものがなかった）。
 * declined は保存しなかった・やめた、blocked はできない状態（ほかの反映の途中・書き込みを許していない・検証のエラーがある・プレビューが古い）
 */
export type DeviceOutcome = 'same' | 'different' | 'written' | 'declined' | 'blocked' | 'cancelled' | 'failed';

export class DeviceFlow {
  /** そのとき進み具合を流す先（device/progress の通知） */
  private sink: ((progress: DeviceProgressParams) => void) | undefined;
  /** 読んでいる間の取り消し（「やめる」） */
  private reading: { dir: string; source: CancellationTokenSource } | undefined;

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
      case 'preview':
        return this.preview(dir);
      case 'confirm':
        return this.confirm(dir);
      case 'cancel':
        return Promise.resolve(this.cancel(dir));
      case 'openSettings':
        this.host.prompts.openWriteSetting();
        return Promise.resolve('declined');
    }
  }

  /** 反映のプレビュー（14.3）。保存済みのファイルと実機を比べ、違いをモーダルに出す（書き込みは許していなくてもできる） */
  async preview(dir: string): Promise<DeviceOutcome> {
    // プレビューを出している（古くなった）ときの「もう一度比べる」は、そのプレビューを閉じてから読み直す
    if (this.states.transferOf(dir)?.step === 'preview') this.states.finish(dir);
    if (this.states.busy) return this.blocked();
    if (!(await this.host.ensureSaved(dir))) return 'declined';
    // 保存を促している間に、ほかの反映が始まったかもしれない
    if (this.states.busy) return this.blocked();
    // 検証のエラーがあれば、実機を読む前に止める（読む 10 秒を無駄にしない。画面の節のボタンも押せない）
    const errors = this.host.errorCount(dir);
    if (errors > 0) {
      this.notify(validationErrorNotice(errors));
      return 'blocked';
    }
    this.states.start(dir, this.host.filesKey(dir));
    const source = new CancellationTokenSource();
    this.reading = { dir, source };
    this.sink = (progress) => this.states.update(dir, { step: 'reading', progress: { done: progress.done, total: progress.total } });
    try {
      const { plan } = await this.client.request('device/compare', { dir }, source.token);
      this.states.update(dir, { step: 'preview', plan, profile: this.host.profileName(dir), stale: false });
      return plan.empty ? 'same' : 'different';
    } catch (error) {
      this.states.finish(dir);
      return this.failed(error, 'preview', dir);
    } finally {
      this.sink = undefined;
      this.reading = undefined;
      source.dispose();
    }
  }

  /** 確定（14.4）。プレビューの token のまま書く。サーバーは比べ直し、違えば何も書かずに -32071 */
  async confirm(dir: string): Promise<DeviceOutcome> {
    const transfer = this.states.transferOf(dir);
    if (transfer?.step !== 'preview' || transfer.plan.empty || transfer.stale) return 'blocked';
    if (!this.states.writesAllowed) {
      this.notify(writesDisabledNotice());
      return 'blocked';
    }
    const errors = this.host.errorCount(dir);
    if (errors > 0) {
      this.notify(validationErrorNotice(errors));
      return 'blocked';
    }
    const { plan, profile } = transfer;
    this.states.update(dir, { step: 'writing', plan, profile, progress: null });
    this.sink = (progress) => this.states.update(dir, { step: 'writing', plan, profile, progress });
    try {
      await this.client.prepareWrites();
      const result = await this.client.request('device/apply', { dir, token: plan.token });
      this.notify(writeResultNotice(result, dir));
      return result.applied === 0 ? 'same' : 'written';
    } catch (error) {
      return this.failed(error, 'confirm', dir);
    } finally {
      this.sink = undefined;
      this.states.finish(dir);
    }
  }

  /** やめる。読んでいる間は取り消し（14.6）、プレビューなら閉じる。書いている間は何もしない（取り消せない） */
  cancel(dir: string): DeviceOutcome {
    const transfer = this.states.transferOf(dir);
    switch (transfer?.step) {
      case 'reading':
        if (this.reading?.dir === dir) this.reading.source.cancel();
        return 'cancelled';
      case 'preview':
        this.states.finish(dir);
        return 'declined';
      case 'writing':
        return 'blocked';
      default:
        return 'declined';
    }
  }

  private failed(error: unknown, step: FailedStep, dir: string): DeviceOutcome {
    // 文のキーボードの表示名は、そのプロファイルの KeyboardSpec から取る
    const notice = deviceFailure(error, step, dir, keyboardSpecFor(dir).displayName);
    if (notice) this.notify(notice);
    return (error as { code?: unknown } | null)?.code === DeviceErrorCodes.RequestCancelled ? 'cancelled' : 'failed';
  }

  private blocked(): DeviceOutcome {
    this.notify({ level: 'info', message: '実機への反映の途中です。終わってから、もう一度試してください。', actions: [] });
    return 'blocked';
  }

  private notify(notice: Notice): void {
    this.host.prompts.notify(notice);
  }
}
