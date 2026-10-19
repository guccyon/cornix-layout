// プロファイル 1 つ分の仮想ドキュメント（ADR 015）。サーバーの ProfileSnapshot と未保存の変更（Change の並び）を持つ。
// 変更は VS Code の編集（CustomDocumentEditEvent）として渡すので、dirty の印・元に戻す・やり直し・閉じるときの確認は VS Code が面倒をみる。
// 保存（profile/planEdits → WorkspaceEdit → profile/saved）と外での変更の扱い（7.3）は段 3 の作業で中身を入れる。
import * as vscode from 'vscode';
import type { Address, Change, FileVersion, ProfileDidChangeParams, ProfileSnapshot } from '../protocol';
import type { CornixServer } from '../server/cornixServer';
import { PendingChanges, snapshotValueAt, type ChangeValue } from './pendingChanges';
import { ProfileWatcher } from './profileWatcher';

/**
 * ホットエグジットのときに書き出す中身。files は変更を作ったときのファイルの版（snapshot.files）で、
 * 戻したときに閉じている間の外での変更を見分ける（段 3 で 7.3 と同じ扱いにする）
 */
type Backup = { version: 1; dir: string; files: Record<string, FileVersion>; changes: Change[] };

export class ProfileDocument implements vscode.CustomDocument {
  readonly changes = new PendingChanges();
  private readonly onDidEditEmitter = new vscode.EventEmitter<vscode.CustomDocumentEditEvent<ProfileDocument>>();
  private readonly onDidChangeContentEmitter = new vscode.EventEmitter<void>();
  private readonly onDidDisposeEmitter = new vscode.EventEmitter<void>();
  private readonly disposables: vscode.Disposable[] = [];
  private closed = false;

  /** 設定ディレクトリの見張り。保存の間（6.2 の 5）は watcher.hold() で知らせを溜める */
  readonly watcher: ProfileWatcher;
  /**
   * バックアップから戻したとき、その変更を作ったときのファイルの版（戻していなければ undefined）。
   * 今の snapshot.files と違えば閉じている間に外で変わっている。TODO(段 3): 7.3 と同じく当て直すか選ばせる
   */
  backupFiles: Record<string, FileVersion> | undefined;

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
    this.watcher = new ProfileWatcher(workspaceRoot, dir, (params) => server.notify('workspace/didChangeFiles', params));
    this.disposables.push(this.watcher, server.onDidRestart(() => void this.reopen(false)));
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
      const backup = await readBackup(vscode.Uri.parse(backupId));
      if (backup) {
        document.changes.replaceAll(backup.changes);
        document.backupFiles = backup.files;
      }
    }
    return document;
  }

  get snapshot(): ProfileSnapshot {
    return this.snapshotValue;
  }

  get profileId(): string {
    return this.snapshotValue.profileId;
  }

  /**
   * 画面での変更を 1 つ足す。元に戻す・やり直しもここで作る。
   * 編集ごとに「前の値（そのときの未保存の値か snapshot の値）」と「新しい値」を持ち、undo では前の値を当てる。
   * 当てた値が snapshot の値と同じなら未保存の変更から外すので、保存や外での変更で snapshot が変わったあとに戻しても、
   * 画面の値と未保存の変更が食い違わない（保存のあとに戻すと、ディスクの値に対する変更として残る）。
   * 前の値がない（割り当てのない位置）ときの undo は変更を外すだけ（v0.1 には割り当てを消す操作がない。protocol.md の 11. の 7）
   */
  applyChange(change: Change, label = '値の変更'): void {
    const before = this.currentValue(change.address);
    this.setValue(change.address, change.value);
    this.onDidEditEmitter.fire({
      document: this,
      label,
      undo: () => this.setValue(change.address, before),
      redo: () => this.setValue(change.address, change.value),
    });
  }

  /** 画面に出す値（未保存の変更があればその値、なければ snapshot の値。どちらもなければ null） */
  currentValue(address: Address): ChangeValue | null {
    return this.changes.get(address)?.value ?? snapshotValueAt(this.snapshotValue, address) ?? null;
  }

  private setValue(address: Address, value: ChangeValue | null): void {
    this.changes.assign(address, value, snapshotValueAt(this.snapshotValue, address));
    this.onDidChangeContentEmitter.fire();
  }

  /** 保存（段 3 で profile/planEdits を使って作る） */
  async save(_cancellation: vscode.CancellationToken): Promise<void> {
    throw new Error('Cornix の編集画面の保存はまだ作っていません（v0.1 の段 3 で入れます）。');
  }

  /**
   * 未保存の変更を捨てて読み直す。
   * TODO(段 3): 7.3 の「外の変更を残す」もここを通す（CustomEditor の dirty は保存か revert でしか消えないので、
   * changes.clear() だけではタブが dirty のまま残る）。そのときは profile/didChange の snapshot を渡して読み直しを省く
   */
  async revert(): Promise<void> {
    this.changes.clear();
    await this.reopen(true);
  }

  async backup(destination: vscode.Uri): Promise<vscode.CustomDocumentBackup> {
    const backup: Backup = { version: 1, dir: this.dir, files: this.snapshotValue.files, changes: this.changes.list() };
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
      // TODO(段 3): どちらを残すか聞き、Change を当て直す。「外の変更を残す」は revert を通す（revert の注釈）
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
    const old = this.profileId;
    try {
      this.snapshotValue = await this.server.request('profile/open', { dir: this.dir });
    } catch {
      return; // 知らせはサーバーの側で出している。開き直せなければ前の profileId のまま
    }
    // 開き直せてから前の profileId を閉じる
    if (closeOld) this.server.notify('profile/close', { profileId: old });
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

/** バックアップを読む。形が違う（版が違う・壊れている）ときは undefined（変更なしで開く） */
async function readBackup(uri: vscode.Uri): Promise<Backup | undefined> {
  try {
    const data = JSON.parse(new TextDecoder().decode(await vscode.workspace.fs.readFile(uri))) as Partial<Backup>;
    if (data.version !== 1 || !Array.isArray(data.changes) || typeof data.files !== 'object' || data.files === null) return undefined;
    return data as Backup;
  } catch {
    return undefined;
  }
}
