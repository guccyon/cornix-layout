// 開いているプロファイルの設定ディレクトリを見張り、変わったファイルを workspace/didChangeFiles でサーバーに知らせる（protocol.md の 7.1）。
// 続けて来た知らせは少し待ってまとめる。保存の間（6.2 の 5）は hold で溜めておき、離したら送る。
import * as path from 'node:path';
import * as vscode from 'vscode';
import type { DidChangeFilesParams, FileChangeType } from '../protocol';

export class ProfileWatcher implements vscode.Disposable {
  private readonly watcher: vscode.FileSystemWatcher;
  private readonly pending = new Map<string, FileChangeType>();
  private timer: ReturnType<typeof setTimeout> | undefined;
  private holds = 0;

  constructor(
    private readonly workspaceRoot: vscode.Uri,
    dir: string,
    private readonly send: (params: DidChangeFilesParams) => void,
    private readonly delayMs = 100,
  ) {
    const base = path.isAbsolute(dir) ? vscode.Uri.file(dir) : vscode.Uri.joinPath(workspaceRoot, dir);
    this.watcher = vscode.workspace.createFileSystemWatcher(new vscode.RelativePattern(base, '**/*'));
    this.watcher.onDidCreate((uri) => this.record(uri, 'created'));
    this.watcher.onDidChange((uri) => this.record(uri, 'changed'));
    this.watcher.onDidDelete((uri) => this.record(uri, 'deleted'));
  }

  /** 離すまで知らせを溜める（保存の流れの 3〜4 の間） */
  hold(): vscode.Disposable {
    this.holds += 1;
    let released = false;
    return new vscode.Disposable(() => {
      if (released) return;
      released = true;
      this.holds -= 1;
      if (this.holds === 0) this.schedule();
    });
  }

  dispose(): void {
    if (this.timer) clearTimeout(this.timer);
    this.watcher.dispose();
  }

  private record(uri: vscode.Uri, type: FileChangeType): void {
    const rel = path.relative(this.workspaceRoot.fsPath, uri.fsPath);
    const key = rel.startsWith('..') || path.isAbsolute(rel) ? uri.fsPath : rel.split(path.sep).join('/');
    const before = this.pending.get(key);
    // 作ってすぐ変えたものは「作った」のまま
    this.pending.set(key, before === 'created' && type === 'changed' ? 'created' : type);
    this.schedule();
  }

  private schedule(): void {
    if (this.holds > 0 || this.pending.size === 0) return;
    if (this.timer) clearTimeout(this.timer);
    this.timer = setTimeout(() => this.flush(), this.delayMs);
  }

  private flush(): void {
    this.timer = undefined;
    if (this.holds > 0 || this.pending.size === 0) return;
    const changes = [...this.pending].map(([p, type]) => ({ path: p, type }));
    this.pending.clear();
    this.send({ changes });
  }
}
