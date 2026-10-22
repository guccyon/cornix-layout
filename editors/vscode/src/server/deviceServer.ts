// device のサーバー `cornix serve --device --root <ワークスペース> [--allow-writes]`（protocol.md の 14.1、ADR 018・019）。
// 必要になったとき（最初の device/* のリクエスト）に起動し、使い終わっても残す。
// --allow-writes は設定 cornix.device.allowWrites が true のときだけ付ける。設定や cornix.path が変わったら呼ぶ側（DeviceController）が止め、次のリクエストで起動し直す。
import type * as vscode from 'vscode';
import type { DeviceInitializeResult, DeviceRequestMap, DeviceServerNotificationMap } from '../deviceProtocol';
import { deviceServerArgs } from '../device/deviceSettings';
import { ServerProcess } from './serverProcess';

export class DeviceServer extends ServerProcess<DeviceRequestMap, DeviceServerNotificationMap, DeviceInitializeResult> {
  constructor(output: vscode.OutputChannel, clientVersion: string) {
    super(output, clientVersion, {
      label: '実機のサーバー',
      extraArgs: (config) => deviceServerArgs(config.get<boolean>('device.allowWrites', false) === true),
      notifications: ['device/progress'],
      // 落ちたときは、そのとき動いていた操作が失敗として知らせる（次の操作で起動し直す）
      notifyExit: false,
    });
  }

  /** 書き込みを許して起動したか（initialize の capabilities.deviceWrites。動いていなければ起動する） */
  async writesAllowed(): Promise<boolean> {
    return (await this.initializeResult()).capabilities.deviceWrites === true;
  }
}
