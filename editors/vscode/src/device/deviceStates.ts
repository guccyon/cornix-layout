// プロファイルごとの「実機への反映の途中の状態」（webviewMessages.ts の DeviceViewState）。vscode に依存しない（単体テストのため）。
// 反映は一度に 1 つ（実機は 1 台）。プレビューを出している間に設定ファイルが変わったら（保存・外での変更）、そのプレビューは古い（stale）にする。
import type { DeviceTransfer, DeviceViewState } from '../webviewMessages';

type Entry = {
  transfer: DeviceTransfer;
  /** 読み始めたときの設定ファイルの版（filesKey）。開いていなければ undefined（そのときは古いかを見ない。最後はサーバーが token で確かめる） */
  files: string | undefined;
  /** 読み始めたあとで設定ファイルが変わった */
  changed: boolean;
};

/** snapshot.files（ファイル → 版）を比べられる 1 つの文字列にする（キーの順によらない） */
export function filesKey(files: Readonly<Record<string, unknown>>): string {
  return JSON.stringify(Object.keys(files).sort().map((file) => [file, files[file]]));
}

export class DeviceStates {
  private readonly entries = new Map<string, Entry>();

  /**
   * @param onChange 状態が変わった dir（undefined はすべて。反映を始めた・終えた・allowWrites が変わったとき）
   */
  constructor(
    private allowWrites: boolean,
    private readonly onChange: (dir: string | undefined) => void,
  ) {}

  get(dir: string): DeviceViewState {
    return {
      transfer: this.entries.get(dir)?.transfer ?? null,
      busyElsewhere: [...this.entries.keys()].some((other) => other !== dir),
      allowWrites: this.allowWrites,
    };
  }

  get writesAllowed(): boolean {
    return this.allowWrites;
  }

  /** いずれかのプロファイルで反映の途中か */
  get busy(): boolean {
    return this.entries.size > 0;
  }

  transferOf(dir: string): DeviceTransfer | null {
    return this.entries.get(dir)?.transfer ?? null;
  }

  setAllowWrites(allowWrites: boolean): void {
    if (this.allowWrites === allowWrites) return;
    this.allowWrites = allowWrites;
    this.onChange(undefined);
  }

  /** 反映を始めた（読み始めた）。files は読み始めたときの filesKey */
  start(dir: string, files: string | undefined): void {
    this.entries.set(dir, { transfer: { step: 'reading', progress: null }, files, changed: false });
    this.onChange(undefined);
  }

  /** 途中の状態を変える（進み具合・プレビュー・書き込み）。始めていなければ何もしない */
  update(dir: string, transfer: DeviceTransfer): void {
    const entry = this.entries.get(dir);
    if (!entry) return;
    entry.transfer = transfer.step === 'preview' && entry.changed && !transfer.plan.empty ? { ...transfer, stale: true } : transfer;
    this.onChange(dir);
  }

  /** 反映を終えた（書いた・やめた・失敗した） */
  finish(dir: string): void {
    if (!this.entries.delete(dir)) return;
    this.onChange(undefined);
  }

  /** プロファイルの snapshot が来た（保存した・外で変わった）。読み始めたときと版が違えば、プレビューを古いにする（読んでいる間なら、読み終えたときに） */
  checkFiles(dir: string, files: string): void {
    const entry = this.entries.get(dir);
    if (!entry || entry.files === undefined || entry.files === files || entry.changed) return;
    entry.changed = true;
    const transfer = entry.transfer;
    if (transfer.step === 'preview') this.update(dir, transfer);
  }
}
