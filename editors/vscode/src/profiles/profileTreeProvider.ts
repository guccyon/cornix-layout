// アクティビティバーの「プロファイル」の一覧（ADR 008）。項目を選ぶとそのプロファイルを開く。
import * as vscode from 'vscode';
import type { CornixServer } from '../server/cornixServer';
import { profileItems, type ProfileItem } from './profileItems';

export class ProfileTreeProvider implements vscode.TreeDataProvider<ProfileItem>, vscode.Disposable {
  static readonly viewId = 'cornix.profiles';

  private readonly onDidChangeEmitter = new vscode.EventEmitter<void>();
  readonly onDidChangeTreeData = this.onDidChangeEmitter.event;
  private readonly disposables: vscode.Disposable[];

  constructor(private readonly server: CornixServer) {
    this.disposables = [server.onDidRestart(() => this.refresh())];
  }

  refresh(): void {
    this.onDidChangeEmitter.fire();
  }

  getTreeItem(item: ProfileItem): vscode.TreeItem {
    const treeItem = new vscode.TreeItem(item.name, vscode.TreeItemCollapsibleState.None);
    treeItem.description = item.description;
    treeItem.tooltip = item.dir;
    treeItem.iconPath = new vscode.ThemeIcon(item.isDefault ? 'star-full' : 'folder');
    treeItem.contextValue = 'cornix.profile';
    treeItem.command = { command: 'cornix.openProfile', title: 'プロファイルを開く', arguments: [{ dir: item.dir, name: item.name }] };
    return treeItem;
  }

  async getChildren(element?: ProfileItem): Promise<ProfileItem[]> {
    if (element) return [];
    await setState('loading');
    try {
      const items = profileItems(await this.server.request('profile/list', {}));
      await setState('loaded');
      return items;
    } catch {
      await setState('error');
      return []; // 空のときの案内（viewsWelcome）を出す。エラーの知らせはサーバーの側で出している
    }
  }

  dispose(): void {
    for (const disposable of this.disposables) disposable.dispose();
    this.onDidChangeEmitter.dispose();
  }
}

function setState(state: 'loading' | 'loaded' | 'error'): Thenable<unknown> {
  return vscode.commands.executeCommand('setContext', 'cornix.profileList', state);
}
