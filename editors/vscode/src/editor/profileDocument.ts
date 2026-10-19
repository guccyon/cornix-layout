// プロファイル 1 つ分の仮想ドキュメント（ADR 015）。サーバーの ProfileSnapshot と未保存の変更（Change の並び）を持つ。
// 変更は VS Code の編集（CustomDocumentEditEvent）として渡すので、dirty の印・元に戻す・やり直し・閉じるときの確認は VS Code が面倒をみる。
// 保存（profile/planEdits → WorkspaceEdit → profile/saved）と外での変更の扱い（7.3）は段 3 の作業で中身を入れる。
import * as vscode from 'vscode';
import type { Change, ProfileDidChangeParams, ProfileSnapshot } from '../protocol';
import type { CornixServer } from '../server/cornixServer';
import { PendingChanges } from './pendingChanges';
import { ProfileWatcher } from './profileWatcher';

/** ホットエグジットのときに書き出す中身 */
type Backup = { version: 1; dir: string; changes: Change[] };

export class ProfileDocument implements vscode.CustomDocument {
  readonly changes = new PendingChanges();
  private readonly onDidEditEmitter = new vscode.EventEmitter<vscode.CustomDocumentEditEvent<ProfileDocument>>();
  private readonly onDidChangeContentEmitter = new vscode.EventEmitter<void>();
  private readonly onDidDisposeEmitter = new vscode.EventEmitter<void>();
  private readonly disposables: vscode.Disposable[] = [];
  private closed = false;

  /** 変更を足した（VS Code の編集の履歴に載せる。プロバイダーが onDidChangeCustomDocument に流す） */
  readonly onDidEdit = this.onDidEditEmitter.event;
  /** 描き直しが要る（snapshot か未保存の変更が変わった） */
  readonly onDidChangeContent = this.onDidChangeContentEmitter.event;
  /** VS Code がドキュメントを閉じた */
  readonly onDidDispose = this.onDidDisposeEmitter.event;

  private constructor(
    readonly uri: vscode.Uri,
    readonly dir: string,
    private snapshotValue: ProfileSnapshot,
    private readonly server: CornixServer,
    workspaceRoot: vscode.Uri,
  ) {
    this.disposables.push(
      new ProfileWatcher(workspaceRoot, dir, (params) => server.notify('workspace/didChangeFiles', params)),
      server.onDidRestart(() => void this.reopen(false)),
    );
  }

  static async open(
    uri: vscode.Uri,
    dir: string,
    server: CornixServer,
    workspaceRoot: vscode.Uri,
    backupId: string | undefined,
  ): Promise<ProfileDocument> {
    const snapshot = await server.request('profile/open', { dir });
    const document = new ProfileDocument(uri, dir, snapshot, server, workspaceRoot);
    if (backupId) {
      const backup = JSON.parse(new TextDecoder().decode(await vscode.workspace.fs.readFile(vscode.Uri.parse(backupId)))) as Backup;
      document.changes.replaceAll(backup.changes);
    }
    return document;
  }

  get snapshot(): ProfileSnapshot {
    return this.snapshotValue;
  }

  get profileId(): string {
    return this.snapshotValue.profileId;
  }

  /** 画面での変更を 1 つ足す。元に戻す・やり直しもここで作る */
  applyChange(change: Change, label = '値の変更'): void {
    const previous = this.changes.set(change);
    this.onDidEditEmitter.fire({
      document: this,
      label,
      undo: () => {
        this.changes.restore(change.address, previous);
        this.onDidChangeContentEmitter.fire();
      },
      redo: () => {
        this.changes.set(change);
        this.onDidChangeContentEmitter.fire();
      },
    });
    this.onDidChangeContentEmitter.fire();
  }

  /** 保存（段 3 で profile/planEdits を使って作る） */
  async save(_cancellation: vscode.CancellationToken): Promise<void> {
    throw new Error('Cornix の編集画面の保存はまだ作っていません（v0.1 の段 3 で入れます）。');
  }

  /** 未保存の変更を捨てて読み直す */
  async revert(): Promise<void> {
    this.changes.clear();
    await this.reopen(true);
  }

  async backup(destination: vscode.Uri): Promise<vscode.CustomDocumentBackup> {
    const backup: Backup = { version: 1, dir: this.dir, changes: this.changes.list() };
    await vscode.workspace.fs.writeFile(destination, new TextEncoder().encode(JSON.stringify(backup)));
    return {
      id: destination.toString(),
      delete: () => void vscode.workspace.fs.delete(destination).then(undefined, () => undefined),
    };
  }

  /** 外での変更（protocol.md の 7.2）。未保存の変更がなければ黙って描き直す。あるときの扱い（7.3）は段 3 */
  handleExternalChange(params: ProfileDidChangeParams): void {
    if (params.profileId !== this.profileId) return;
    if (this.changes.size > 0) {
      // TODO(段 3): どちらを残すか聞き、Change を当て直す
      return;
    }
    this.snapshotValue = params.snapshot;
    this.onDidChangeContentEmitter.fire();
  }

  /**
   * profile/open からやり直す（profileId は変わる）。closeOld は同じサーバーに前の profileId を閉じさせるとき
   * （再起動したあとの新しいサーバーは前の profileId を知らないので送らない）
   */
  private async reopen(closeOld: boolean): Promise<void> {
    if (closeOld) this.server.notify('profile/close', { profileId: this.profileId });
    try {
      this.snapshotValue = await this.server.request('profile/open', { dir: this.dir });
    } catch {
      return; // 知らせはサーバーの側で出している
    }
    if (this.closed) {
      this.server.notify('profile/close', { profileId: this.profileId });
      return;
    }
    this.onDidChangeContentEmitter.fire();
  }

  dispose(): void {
    this.closed = true;
    this.server.notify('profile/close', { profileId: this.profileId });
    for (const disposable of this.disposables) disposable.dispose();
    this.onDidDisposeEmitter.fire();
    this.onDidDisposeEmitter.dispose();
    this.onDidEditEmitter.dispose();
    this.onDidChangeContentEmitter.dispose();
  }
}
