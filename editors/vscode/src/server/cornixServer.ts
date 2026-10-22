// 編集のサーバー `cornix serve --root <ワークスペース>`（protocol.md の 1.）。起動・接続・再起動は serverProcess.ts。
import type * as vscode from 'vscode';
import type {
  ClientNotificationMap,
  ClientNotificationMethod,
  InitializeResult,
  PlanItemEditParams,
  PlanItemEditResult,
  RequestMap,
  ServerNotificationMap,
} from '../protocol';
import { ServerProcess } from './serverProcess';

export { CornixUnavailableError } from './serverProcess';

export class CornixServer extends ServerProcess<RequestMap, ServerNotificationMap, InitializeResult> {
  constructor(output: vscode.OutputChannel, clientVersion: string) {
    super(output, clientVersion, {
      label: 'サーバー',
      extraArgs: () => [],
      notifications: ['profile/didChange'],
      notifyExit: true,
    });
  }

  /** 項目の追加・削除・名前の変更を、ファイルの作成・削除・改名と書き換えにしてもらう（protocol.md の 12.5） */
  planItemEdit(params: PlanItemEditParams): Promise<PlanItemEditResult> {
    return this.request('profile/planItemEdit', params);
  }

  /** 動いていなければ送らない（profile/close などは、サーバーが止まっていれば意味がない） */
  notify<M extends ClientNotificationMethod>(method: M, params: ClientNotificationMap[M]): void {
    this.notifyRunning((connection) => connection.notify(method, params), method);
  }
}
