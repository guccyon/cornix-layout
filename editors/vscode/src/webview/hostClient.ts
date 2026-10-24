// 画面からホスト（拡張）への口。Webview はサーバーと直接話せないので、keycode/candidates・keycode/inspect・keycode/shortcutTree は
// ホストに中継してもらう（profileId はホストが入れる。webviewMessages.ts の WebviewRequest）。
import type { AnyChange, Change, ItemEdit, Range } from '../protocol';
import type { DeviceAction, HostMessage, WebviewMessage, WebviewRequest, WebviewRequestMap, WebviewRequestMethod } from '../webviewMessages';

export interface HostClient {
  request<M extends WebviewRequestMethod>(method: M, params: WebviewRequestMap[M]['params']): Promise<WebviewRequestMap[M]['result']>;
  /** 値を変えた（ホストが未保存の変更に足す） */
  change(change: Change): void;
  /** v0.2: 並びの操作・行の削除・注記（ホストが未保存の変更の末尾に足す） */
  edit(change: AnyChange): void;
  /** v0.2: 項目の追加・削除・名前の変更（ホストが確認してすぐ書く） */
  itemEdit(edit: ItemEdit): void;
  /** そのファイルをテキストで開く（構造の問題の一覧から） */
  openFile(file: string, range?: Range): void;
  /** v0.4: 実機の操作のボタンを押した（ホストがコマンドと同じことをする） */
  deviceAction(action: DeviceAction): void;
}

type Pending = { method: WebviewRequestMethod; resolve: (result: unknown) => void; reject: (error: Error) => void };

/** postMessage でホストと話す HostClient。応答は handle に渡す */
export class MessageHostClient implements HostClient {
  private nextId = 1;
  private readonly pending = new Map<number, Pending>();

  constructor(private readonly post: (message: WebviewMessage) => void) {}

  request<M extends WebviewRequestMethod>(method: M, params: WebviewRequestMap[M]['params']): Promise<WebviewRequestMap[M]['result']> {
    const id = this.nextId++;
    // M は中継するメソッドのどれかなので、組にした形は WebviewRequest のどれかになる（TypeScript は総称のままでは絞れない）
    const message = { type: 'request', id, method, params } as WebviewRequest;
    return new Promise<WebviewRequestMap[M]['result']>((resolve, reject) => {
      this.pending.set(id, { method, resolve: (result) => resolve(result as WebviewRequestMap[M]['result']), reject });
      this.post(message);
    });
  }

  change(change: Change): void {
    this.post({ type: 'change', change });
  }

  edit(change: AnyChange): void {
    this.post({ type: 'edit', change });
  }

  itemEdit(edit: ItemEdit): void {
    this.post({ type: 'itemEdit', edit });
  }

  openFile(file: string, range?: Range): void {
    this.post({ type: 'openFile', file, ...(range ? { range } : {}) });
  }

  deviceAction(action: DeviceAction): void {
    this.post({ type: 'deviceAction', action });
  }

  /** ホストからの応答を受ける。応答だったら true。要求と method が違えば取り違えとして失敗にする */
  handle(message: HostMessage): boolean {
    if (message.type !== 'response') return false;
    const entry = this.pending.get(message.id);
    if (!entry) return true;
    this.pending.delete(message.id);
    if (message.method !== entry.method) entry.reject(new Error(`応答の取り違え: ${entry.method} に ${message.method} の応答が来ました`));
    else if ('error' in message) entry.reject(new Error(message.error));
    else entry.resolve(message.result);
    return true;
  }
}
