// コマンド「Cornix: プロファイルを開く」（spec.md の「画面」）。
// profile/list で一覧を取り、1 つならそれを、複数なら QuickPick で選ばせて（既定を初期値に）、カスタムエディタで開く。
import * as path from 'node:path';
import * as vscode from 'vscode';
import { ProfileEditorProvider } from '../editor/profileEditorProvider';
import { profileUriParts } from '../editor/profileUri';
import { CornixUnavailableError, type CornixServer } from '../server/cornixServer';
import { profileItems, type ProfileItem } from './profileItems';

/** arg: 一覧から開くときの dir（なければ選ばせる） */
export async function openProfile(server: CornixServer, arg?: string | { dir: string; name?: string }): Promise<void> {
  try {
    const target = typeof arg === 'string' ? { dir: arg } : arg;
    const chosen = target ?? (await pickProfile(server));
    if (!chosen) return;
    const name = chosen.name ?? path.basename(chosen.dir);
    await vscode.commands.executeCommand('vscode.openWith', vscode.Uri.from(profileUriParts(chosen.dir, name)), ProfileEditorProvider.viewType);
  } catch (error) {
    if (error instanceof CornixUnavailableError) return; // 知らせは出してある
    void vscode.window.showErrorMessage(`プロファイルを開けませんでした: ${error instanceof Error ? error.message : String(error)}`);
  }
}

async function pickProfile(server: CornixServer): Promise<ProfileItem | undefined> {
  const items = profileItems(await server.request('profile/list', {}));
  if (items.length === 0) {
    void vscode.window.showInformationMessage('プロファイルが見つかりません。cornix init で作ってください。');
    return undefined;
  }
  if (items.length === 1) return items[0];

  type Pick = vscode.QuickPickItem & { item: ProfileItem };
  const quickPick = vscode.window.createQuickPick<Pick>();
  quickPick.title = 'Cornix: プロファイルを開く';
  quickPick.placeholder = '開くプロファイルを選んでください';
  quickPick.items = items.map((item) => ({ label: item.name, description: item.description, detail: item.dir, item }));
  const initial = quickPick.items.find((pick) => pick.item.isDefault);
  if (initial) quickPick.activeItems = [initial];
  return new Promise((resolve) => {
    let picked: ProfileItem | undefined;
    quickPick.onDidAccept(() => {
      picked = quickPick.selectedItems[0]?.item ?? quickPick.activeItems[0]?.item;
      quickPick.hide();
    });
    quickPick.onDidHide(() => {
      quickPick.dispose();
      resolve(picked);
    });
    quickPick.show();
  });
}
