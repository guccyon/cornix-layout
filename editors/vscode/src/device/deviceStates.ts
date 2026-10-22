// プロファイルごとの「実機と比べた状態」（webviewMessages.ts の DeviceViewState）。vscode に依存しない（単体テストのため）。
// 自動では読まない（tasks-v0.4.md の決めたこと 6）。比べる・反映・戻すのあとだけ変え、設定ファイルが変わったら（保存・外での変更）「未確認」に戻す。
import type { DeviceChange } from '../deviceProtocol';
import type { DeviceAction, DeviceViewState } from '../webviewMessages';

type Entry = {
  status: DeviceViewState['status'];
  changes: DeviceChange[];
  busy: DeviceAction | null;
  /**
   * 比べたときの設定ファイルの版（filesKey）。これと違う版の snapshot が来たら「未確認」に戻す。
   * 比べたときにプロファイルを開いていなかったら undefined（開いたときに、閉じている間に変わったかが分からないので「未確認」に戻す）
   */
  files: string | undefined;
};

/** snapshot.files（ファイル → 版）を比べられる 1 つの文字列にする（キーの順によらない） */
export function filesKey(files: Readonly<Record<string, unknown>>): string {
  return JSON.stringify(Object.keys(files).sort().map((file) => [file, files[file]]));
}

export class DeviceStates {
  private readonly entries = new Map<string, Entry>();

  /**
   * @param onChange 状態が変わった dir（undefined はすべて。allowWrites が変わったとき）
   */
  constructor(
    private allowWrites: boolean,
    private readonly onChange: (dir: string | undefined) => void,
  ) {}

  get(dir: string): DeviceViewState {
    const entry = this.entries.get(dir);
    return {
      status: entry?.status ?? 'unknown',
      changes: entry?.status === 'different' ? [...entry.changes] : [],
      busy: entry?.busy ?? null,
      allowWrites: this.allowWrites,
    };
  }

  get writesAllowed(): boolean {
    return this.allowWrites;
  }

  /** いずれかのプロファイルで操作の最中か */
  get busy(): boolean {
    return [...this.entries.values()].some((entry) => entry.busy !== null);
  }

  setAllowWrites(allowWrites: boolean): void {
    if (this.allowWrites === allowWrites) return;
    this.allowWrites = allowWrites;
    this.onChange(undefined);
  }

  setBusy(dir: string, busy: DeviceAction | null): void {
    const entry = this.entry(dir);
    if (entry.busy === busy) return;
    entry.busy = busy;
    this.onChange(dir);
  }

  /** 比べた・反映した（changes は違い。反映のあとは読み直しで残った違い）。files は比べたときの filesKey */
  setCompared(dir: string, changes: readonly DeviceChange[], files: string | undefined): void {
    const entry = this.entry(dir);
    entry.status = changes.length === 0 ? 'same' : 'different';
    entry.changes = [...changes];
    entry.files = files;
    this.onChange(dir);
  }

  setUnknown(dir: string): void {
    const entry = this.entries.get(dir);
    if (!entry || entry.status === 'unknown') return;
    entry.status = 'unknown';
    entry.changes = [];
    entry.files = undefined;
    this.onChange(dir);
  }

  /** プロファイルの snapshot が来た（開いた・保存した・外で変わった）。比べたときと版が違えば「未確認」に戻す */
  checkFiles(dir: string, files: string): void {
    const entry = this.entries.get(dir);
    if (!entry || entry.status === 'unknown') return;
    if (entry.files !== files) this.setUnknown(dir);
  }

  /** プロファイルを閉じた（操作の最中でなければ忘れる） */
  forget(dir: string): void {
    const entry = this.entries.get(dir);
    if (entry && entry.busy === null) this.entries.delete(dir);
  }

  private entry(dir: string): Entry {
    let entry = this.entries.get(dir);
    if (!entry) this.entries.set(dir, (entry = { status: 'unknown', changes: [], busy: null, files: undefined }));
    return entry;
  }
}
