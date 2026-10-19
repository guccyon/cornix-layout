// 拡張の入口。サーバー（cornix serve）・プロファイルの一覧・編集画面・コマンドをつなぐ。
import * as vscode from 'vscode';
import { ProfileEditorProvider } from './editor/profileEditorProvider';
import { openProfile } from './profiles/openProfile';
import { ProfileTreeProvider } from './profiles/profileTreeProvider';
import { CornixServer } from './server/cornixServer';

/** activate の戻り値（統合テストと、ほかの拡張からの利用のため） */
export type CornixExtensionApi = {
  server: CornixServer;
  profileEditor: ProfileEditorProvider;
};

let server: CornixServer | undefined;

export function activate(context: vscode.ExtensionContext): CornixExtensionApi {
  const output = vscode.window.createOutputChannel('Cornix');
  const version = (context.extension.packageJSON as { version?: string }).version ?? '0.0.0';
  server = new CornixServer(output, version);
  const current = server;
  const tree = new ProfileTreeProvider(current);
  const profileEditor = ProfileEditorProvider.register(context, current);

  context.subscriptions.push(
    output,
    current,
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
      if (current.isRunning) void current.restart().catch(() => undefined);
      tree.refresh();
    }),
  );

  return { server: current, profileEditor };
}

export async function deactivate(): Promise<void> {
  await server?.stop();
  server = undefined;
}
