// 未保存の変更（protocol.md の 2. の Change）。同じ Address は最後の値だけを持つ。
// 元に戻す・やり直しは、set が返す「前の値」を使って VS Code の編集の履歴に載せる（profileDocument.ts）。vscode に依存しない。
import type { Address, Change, FileVersion } from '../protocol';

export function addressKey(address: Address): string {
  return JSON.stringify([address.file, ...address.path]);
}

export class PendingChanges {
  private readonly changes = new Map<string, Change>();

  get size(): number {
    return this.changes.size;
  }

  get(address: Address): Change | undefined {
    return this.changes.get(addressKey(address));
  }

  /** 変更を足す。戻り値はその Address の前の変更（なければ undefined）で、元に戻すときに restore に渡す */
  set(change: Change): Change | undefined {
    const key = addressKey(change.address);
    const previous = this.changes.get(key);
    this.changes.delete(key); // 並びを「最後に変えた順」にする
    this.changes.set(key, change);
    return previous;
  }

  /** address の変更を previous に戻す（previous が undefined なら変更をなくす） */
  restore(address: Address, previous: Change | undefined): void {
    const key = addressKey(address);
    if (previous) this.changes.set(key, previous);
    else this.changes.delete(key);
  }

  list(): Change[] {
    return [...this.changes.values()];
  }

  clear(): void {
    this.changes.clear();
  }

  replaceAll(changes: Change[]): void {
    this.clear();
    for (const change of changes) this.set(change);
  }

  /** profile/validate・profile/planEdits に渡す baseVersions（変更のあるファイルだけ。版は snapshot の files から） */
  baseVersions(files: Record<string, FileVersion>): Record<string, FileVersion> {
    const result: Record<string, FileVersion> = {};
    for (const change of this.changes.values()) result[change.address.file] = files[change.address.file] ?? null;
    return result;
  }
}
