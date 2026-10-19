// 画面からホスト（拡張）への口。Webview はサーバーと直接話せないので、keycode/candidates・keycode/inspect は
// ホストに中継してもらう（profileId はホストが入れる。webviewMessages.ts の WebviewRequest）。
import type { Change, Range } from '../protocol';
import type { HostMessage, WebviewMessage, WebviewRequestMap, WebviewRequestMethod } from '../webviewMessages';

export interface HostClient {
  request<M extends WebviewRequestMethod>(method: M, params: WebviewRequestMap[M]['params']): Promise<WebviewRequestMap[M]['result']>;
  /** 値を変えた（ホストが未保存の変更に足す） */
  change(change: Change): void;
  /** そのファイルをテキストで開く（構造の問題の一覧から） */
  openFile(file: string, range?: Range): void;
}

/** postMessage でホストと話す HostClient。応答は handle に渡す */
export class MessageHostClient implements HostClient {
  private nextId = 1;
  private readonly pending = new Map<number, { resolve: (value: never) => void; reject: (error: Error) => void }>();

  constructor(private readonly post: (message: WebviewMessage) => void) {}

  request<M extends WebviewRequestMethod>(method: M, params: WebviewRequestMap[M]['params']): Promise<WebviewRequestMap[M]['result']> {
    const id = this.nextId++;
    return new Promise((resolve, reject) => {
      this.pending.set(id, { resolve: resolve as (value: never) => void, reject });
      this.post({ type: 'request', id, method, params } as WebviewMessage);
    });
  }

  change(change: Change): void {
    this.post({ type: 'change', change });
  }

  openFile(file: string, range?: Range): void {
    this.post({ type: 'openFile', file, ...(range ? { range } : {}) });
  }

  /** ホストからの応答を受ける。応答だったら true */
  handle(message: HostMessage): boolean {
    if (message.type !== 'response') return false;
    const entry = this.pending.get(message.id);
    if (!entry) return true;
    this.pending.delete(message.id);
    if ('error' in message) entry.reject(new Error(message.error));
    else entry.resolve(message.result as never);
    return true;
  }
}
