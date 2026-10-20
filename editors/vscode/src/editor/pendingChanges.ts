// 未保存の変更（protocol.md の 2. の Change）。同じ Address は最後の値だけを持つ。
// 元に戻す・やり直しは profileDocument.ts が「前の値」と「新しい値」で作る。vscode に依存しない。
import type { Address, Change, FileVersion, ProfileSnapshot } from '../protocol';

export type ChangeValue = Change['value'];

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

  /** 変更を足す（同じ Address の前の変更は置き換える） */
  set(change: Change): void {
    const key = addressKey(change.address);
    this.changes.delete(key); // 並びを「最後に変えた順」にする
    this.changes.set(key, change);
  }

  /**
   * address の値を value にする。value が保存済みの値（saved）と同じか null なら未保存の変更から外す。
   * 元に戻す・やり直しはこれで「前の値」「新しい値」を当てる
   */
  assign(address: Address, value: ChangeValue | null, saved: ChangeValue | null | undefined): void {
    if (value === null || value === saved) this.delete(address);
    else this.set({ address, value });
  }

  delete(address: Address): void {
    this.changes.delete(addressKey(address));
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

/** snapshot の中の、その Address の今の値（キーは表記の文字列、QMK 設定は数値か真偽値）。割り当てや設定がなければ null、Address がなければ undefined */
export function snapshotValueAt(snapshot: ProfileSnapshot, address: Address): ChangeValue | null | undefined {
  const key = addressKey(address);
  for (const layer of snapshot.layers) {
    if (layer.file !== address.file) continue;
    for (const slot of layer.keys) if (addressKey(slot.address) === key) return slot.value?.text ?? null;
    for (const encoder of [layer.encoders.left, layer.encoders.right]) {
      for (const action of [encoder.push, encoder.ccw, encoder.cw]) {
        if (addressKey(action.address) === key) return action.value?.text ?? null;
      }
    }
  }
  for (const setting of snapshot.settings) if (addressKey(setting.address) === key) return setting.value;
  return undefined;
}
