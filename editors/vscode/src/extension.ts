// 拡張の入口。サーバー（cornix serve）・プロファイルの一覧・編集画面・コマンド・実機の操作（cornix serve --device）をつなぐ。
import * as vscode from 'vscode';
import { DeviceController } from './device/deviceController';
import { ProfileEditorProvider } from './editor/profileEditorProvider';
import { openProfile } from './profiles/openProfile';
import { ProfileTreeProvider } from './profiles/profileTreeProvider';
import { CornixServer } from './server/cornixServer';

/** activate の戻り値（統合テストと、ほかの拡張からの利用のため） */
export type CornixExtensionApi = {
  server: CornixServer;
  profileEditor: ProfileEditorProvider;
  /** v0.4: 実機の操作（device のサーバー・状態・流れ） */
  device: DeviceController;
};

let server: CornixServer | undefined;

export function activate(context: vscode.ExtensionContext): CornixExtensionApi {
  const output = vscode.window.createOutputChannel('Cornix');
  const version = (context.extension.packageJSON as { version?: string }).version ?? '0.0.0';
  server = new CornixServer(output, version);
  const current = server;
  const tree = new ProfileTreeProvider(current);
  const profileEditor = ProfileEditorProvider.register(context, current);
  const device = new DeviceController(output, version, current, profileEditor);

  context.subscriptions.push(
    output,
    current,
    device,
    tree,
    vscode.window.registerTreeDataProvider(ProfileTreeProvider.viewId, tree),
    vscode.commands.registerCommand('cornix.openProfile', (arg?: string | { dir: string; name?: string }) => openProfile(current, arg)),
    vscode.commands.registerCommand('cornix.refreshProfiles', () => tree.refresh()),
    vscode.commands.registerCommand('cornix.restartServer', async () => {
      await current.restart().catch(() => undefined);
      tree.refresh();
    }),
    vscode.commands.registerCommand('cornix.showOutput', () => output.show(true)),
    vscode.workspace.onDidChangeConfiguration((event) => {
      if (!event.affectsConfiguration('cornix.path') && !event.affectsConfiguration('cornix.trace.server')) return;
      // 場所が変わったら、動いていれば起動し直す（動いていなければ次のリクエストで新しい設定を使う）
      if (current.isStartingOrRunning) void current.restart().catch(() => undefined);
      tree.refresh();
    }),
  );

  return { server: current, profileEditor, device };
}

export async function deactivate(): Promise<void> {
  await server?.stop();
  server = undefined;
}
