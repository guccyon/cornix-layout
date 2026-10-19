// プロファイル 1 つ分の仮想ドキュメント（ADR 015）。サーバーの ProfileSnapshot と未保存の変更（Change の並び）を持つ。
// 変更は VS Code の編集（CustomDocumentEditEvent）として渡すので、dirty の印・元に戻す・やり直し・閉じるときの確認は VS Code が面倒をみる。
// 保存は protocol.md の 6.2（profile/planEdits → WorkspaceEdit → TextDocument#save → profile/saved）、
// 外での変更は 7.3（未保存がなければ黙って描き直す。あればどちらを残すか聞き、画面の変更を残すなら Change を当て直す）。
// 方針: 利用者の変更を黙って捨てない（問いを閉じたら捨てずに残す側に倒す）。
import * as vscode from 'vscode';
import {
  ErrorCodes,
  type Address,
  type Change,
  type Diagnostic,
  type DraftParams,
  type FileEdits,
  type FileVersion,
  type PlanEditsResult,
  type ProfileDidChangeParams,
  type ProfileSnapshot,
} from '../protocol';
import type { CornixServer } from '../server/cornixServer';
import { PendingChanges, addressKey, snapshotValueAt, type ChangeValue } from './pendingChanges';
import { openProfileFile, profileDirPath, profileFileUri } from './profileFiles';
import { PROFILE_EDITOR_VIEW_TYPE } from './profileUri';
import { ProfileWatcher } from './profileWatcher';
import type { ProfilePrompts } from './prompts';
import {
  backupBefore,
  changedFiles,
  describeAddress,
  describeValue,
  fileVersionOf,
  rebaseChanges,
  sameFiles,
  structureErrors,
} from './rebase';

/**
 * ホットエグジットのときに書き出す中身。files は変更を作ったときのファイルの版（snapshot.files）で、
 * 戻したときに閉じている間の外での変更を見分ける。saved は変更を作ったときのその場所の値（addressKey → 値）で、
 * 外で同じ場所も変わったかを見分ける（ない古いバックアップでは、版の違うファイルの変更はすべて選ばせる）
 */
type Backup = {
  version: 1;
  dir: string;
  files: Record<string, FileVersion>;
  changes: Change[];
  saved?: Record<string, ChangeValue | null>;
};

/** ドキュメントが使うもの（prompts はテストが差し替えるので、そのときのものを取る） */
export type DocumentEnv = {
  server: CornixServer;
  workspaceRoot: vscode.Uri;
  prompts: () => ProfilePrompts;
};

/** 外での変更で、どちらを残すか聞いているもの（聞いている間に次の知らせが来れば snapshot だけを新しくする） */
type ExternalChange = {
  snapshot: ProfileSnapshot;
  reason: 'external' | 'backup';
  /** 外の変更の前の値。省けば当て直すときの snapshotValue（未保存の変更を作ったときの snapshot）から取る */
  before?: (address: Address) => ChangeValue | null | undefined;
};

export class ProfileDocument implements vscode.CustomDocument {
  readonly changes = new PendingChanges();
  private readonly onDidEditEmitter = new vscode.EventEmitter<vscode.CustomDocumentEditEvent<ProfileDocument>>();
  private readonly onDidChangeContentEmitter = new vscode.EventEmitter<void>();
  private readonly onDidDisposeEmitter = new vscode.EventEmitter<void>();
  private readonly disposables: vscode.Disposable[] = [];
  private readonly server: CornixServer;
  private closed = false;

  /** 未保存の変更を当てた状態の検証の結果（profile/validate）。変更がなければ undefined（snapshot の diagnostics を使う） */
  private draftDiagnostics: Diagnostic[] | undefined;
  private validateGeneration = 0;
  /** 保存の途中（その間の profile/didChange は deferred に溜め、終わってから扱う） */
  private saving: Promise<void> | undefined;
  private deferred: ProfileSnapshot | undefined;
  /** どちらを残すか聞いている外での変更と、聞いている流れ */
  private external: ExternalChange | undefined;
  private resolving: Promise<void> | undefined;
  /**
   * 未保存の変更があるのに外の変更でプロファイルが読めなくなった（status: invalid）とき、変更を作ったときの snapshot。
   * 読めない間は聞かずに待ち、読めるようになったらこれを「外の変更の前」として 7.3 の扱いをする
   */
  private changeBase: ProfileSnapshot | undefined;
  /** ホットエグジットから戻したときにプロファイルが読めなかった。読めるようになったらこのバックアップの版と値で 7.3 の扱いをする */
  private waitingBackup: Pick<Backup, 'files' | 'saved'> | undefined;
  /** 「外の変更を残す」で revert を通すときに、読み直さずに使う snapshot */
  private revertSnapshot: ProfileSnapshot | undefined;
  /** revert のたびに増やす（聞いている間に revert されたら当て直さない） */
  private revertGeneration = 0;
  private reverting: Promise<void> | undefined;
  /** 外の変更を取り込むたびに増やす（そのあとの undo の扱いを変える。applyChange） */
  private epoch = 0;

  /** 設定ディレクトリの見張り。保存の間（6.2 の 5）は watcher.hold() で知らせを溜める */
  readonly watcher: ProfileWatcher;
  /**
   * バックアップから戻したとき、その変更を作ったときのファイルの版（戻していなければ undefined）。
   * 今の snapshot.files と違えば閉じている間に外で変わっているので、7.3 と同じく聞く
   */
  backupFiles: Record<string, FileVersion> | undefined;

  /** 変更を足した（VS Code の編集の履歴に載せる。プロバイダーが onDidChangeCustomDocument に流す） */
  readonly onDidEdit = this.onDidEditEmitter.event;
  /** 描き直しが要る（snapshot・未保存の変更・検証の結果が変わった） */
  readonly onDidChangeContent = this.onDidChangeContentEmitter.event;
  /** VS Code がドキュメントを閉じた */
  readonly onDidDispose = this.onDidDisposeEmitter.event;

  private constructor(
    readonly uri: vscode.Uri,
    readonly dir: string,
    private snapshotValue: ProfileSnapshot,
    private readonly env: DocumentEnv,
  ) {
    this.server = env.server;
    this.watcher = new ProfileWatcher(env.workspaceRoot, dir, (params) => this.server.notify('workspace/didChangeFiles', params));
    this.disposables.push(this.watcher, this.server.onDidRestart(() => void this.reopen(false)));
  }

  static async open(uri: vscode.Uri, dir: string, env: DocumentEnv, backupId: string | undefined): Promise<ProfileDocument> {
    const snapshot = await env.server.request('profile/open', { dir });
    const document = new ProfileDocument(uri, dir, snapshot, env);
    if (backupId) {
      const backup = await readBackup(vscode.Uri.parse(backupId));
      if (backup) document.restoreBackup(backup);
    }
    return document;
  }

  get snapshot(): ProfileSnapshot {
    return this.snapshotValue;
  }

  /** 画面に送る snapshot。未保存の変更があれば diagnostics をその状態の検証の結果にする（ほかの項目にかかる問題も参照している側に出る） */
  get viewSnapshot(): ProfileSnapshot {
    if (!this.draftDiagnostics || this.snapshotValue.status !== 'ok') return this.snapshotValue;
    return { ...this.snapshotValue, diagnostics: this.draftDiagnostics };
  }

  get profileId(): string {
    return this.snapshotValue.profileId;
  }

  /** 保存の途中か（テスト用） */
  get isSaving(): boolean {
    return this.saving !== undefined;
  }

  /** 保存・revert の途中か、外での変更の扱いが終わるまで待つ（テスト用） */
  async settled(): Promise<void> {
    while (this.saving || this.resolving || this.reverting) await (this.saving ?? this.resolving ?? this.reverting)?.catch(() => undefined);
  }

  /**
   * 画面での変更を 1 つ足す。元に戻す・やり直しもここで作る。
   * 編集ごとに「前の値（そのときの未保存の値か snapshot の値）」と「新しい値」を持ち、undo では前の値を当てる。
   * 当てた値が snapshot の値と同じなら未保存の変更から外すので、保存や外での変更で snapshot が変わったあとに戻しても、
   * 画面の値と未保存の変更が食い違わない（保存のあとに戻すと、ディスクの値に対する変更として残る）。
   * ただし前の値が snapshot の値だった（未保存の変更がなかった）編集を、外の変更を取り込んだあとに戻すときは、
   * 外の変更の前の値ではなく今の snapshot の値に戻す（変更を外す）。利用者が見ていない値で外の変更を黙って戻さないため。
   * 前の値がない（割り当てのない位置）ときの undo は変更を外すだけ（v0.1 には割り当てを消す操作がない。protocol.md の 11. の 7）
   */
  applyChange(change: Change, label = '値の変更'): void {
    const hadChange = this.changes.get(change.address) !== undefined;
    const before = this.currentValue(change.address);
    const epoch = this.epoch;
    this.setValue(change.address, change.value);
    this.onDidEditEmitter.fire({
      document: this,
      label,
      undo: () => this.setValue(change.address, !hadChange && this.epoch !== epoch ? null : before),
      redo: () => this.setValue(change.address, change.value),
    });
  }

  /** 画面に出す値（未保存の変更があればその値、なければ snapshot の値。どちらもなければ null） */
  currentValue(address: Address): ChangeValue | null {
    return this.changes.get(address)?.value ?? snapshotValueAt(this.snapshotValue, address) ?? null;
  }

  private setValue(address: Address, value: ChangeValue | null): void {
    this.changes.assign(address, value, snapshotValueAt(this.snapshotValue, address));
    this.fire();
    this.validate();
  }

  // ---------------------------------------------------------------------------
  // 保存前の検証（ADR 012 の onchange）
  // ---------------------------------------------------------------------------

  /** 未保存の変更を当てた状態で検証する（profile/validate）。古い要求の結果は捨てる */
  private validate(): void {
    const generation = ++this.validateGeneration;
    if (this.changes.size === 0 || this.snapshotValue.status !== 'ok') {
      if (this.draftDiagnostics) {
        this.draftDiagnostics = undefined;
        this.fire();
      }
      return;
    }
    this.server.request('profile/validate', this.draftParams()).then(
      (result) => {
        if (generation !== this.validateGeneration || this.closed) return;
        this.draftDiagnostics = result.diagnostics;
        this.fire();
      },
      // 版の食い違い（-32060）は外での変更の知らせが来れば当て直してから検証し直す。ほかの失敗は前の結果のまま
      () => undefined,
    );
  }

  /** 今の未保存の変更の profile/validate・profile/planEdits の params */
  private draftParams(): DraftParams {
    return { profileId: this.profileId, baseVersions: this.changes.baseVersions(this.snapshotValue.files), changes: this.changes.list() };
  }

  // ---------------------------------------------------------------------------
  // 保存（protocol.md の 6.2）
  // ---------------------------------------------------------------------------

  /**
   * 保存する。保存できなければ利用者に知らせて CancellationError を投げる（VS Code は dirty のまま残す）。
   * 続けて保存されたら前の保存が終わるのを待ってから始める
   */
  async save(cancellation: vscode.CancellationToken): Promise<void> {
    const previous = this.saving;
    const run = (async () => {
      await previous?.catch(() => undefined);
      await this.runSave(cancellation);
    })();
    this.saving = run;
    let saved = false;
    try {
      await run;
      saved = true;
    } finally {
      if (this.saving === run) {
        this.saving = undefined;
        this.flushDeferred();
      }
      // VS Code は保存の Promise が解決したあとに、そのときの編集の位置を保存点にする。保存の間に画面で足した変更（と undo・redo）も
      // 保存点の手前に入るので、変更が残っていれば保存点を置いたあと（次のタスク）に編集を 1 つ足して dirty に戻す
      if (saved) setTimeout(() => this.markRemainingDirty(), 0);
    }
  }

  /** 保存のあとに残った未保存の変更を、1 つの編集として VS Code の履歴に載せる（undo で外し、redo で戻す） */
  private markRemainingDirty(): void {
    const remaining = this.changes.list();
    if (this.closed || remaining.length === 0 || this.saving) return;
    const apply = (values: ReadonlyMap<string, Change>, restore: boolean) => {
      for (const change of remaining) {
        if (values.get(addressKey(change.address)) === undefined) continue;
        this.changes.assign(change.address, restore ? change.value : null, snapshotValueAt(this.snapshotValue, change.address));
      }
      this.fire();
      this.validate();
    };
    const byKey = new Map(remaining.map((change) => [addressKey(change.address), change]));
    this.onDidEditEmitter.fire({
      document: this,
      label: '保存の間の変更',
      undo: () => apply(byKey, false),
      redo: () => apply(byKey, true),
    });
  }

  private async runSave(cancellation: vscode.CancellationToken): Promise<void> {
    if (this.changes.size === 0) return;
    if (this.snapshotValue.status !== 'ok') this.stop('プロファイルが読めない状態なので保存しません。設定ファイルをテキストで直してください。');
    if (this.external || this.resolving) this.stop('設定ファイルが外で変わっています。どちらの変更を残すか選んでから、もう一度保存してください。');

    // 場所が見つからない変更（外での変更で当て直せず、捨てなかったもの）があれば、捨てるか聞き直す
    const lost = this.changes.list().filter((change) => snapshotValueAt(this.snapshotValue, change.address) === undefined);
    if (lost.length > 0) {
      const answer = await this.env.prompts().confirmLost(this.snapshotValue.name, this.lostItems(lost, this.snapshotValue));
      if (answer !== 'discard') {
        this.stop('場所が見つからない未保存の変更があるので保存しませんでした。捨てるか、テキストで直してください。');
      }
      for (const change of lost) this.changes.delete(change.address);
      this.fire();
      this.validate();
      if (this.changes.size === 0) return;
    }

    // 1. 書き換える対象のファイルがテキストエディタで未保存なら止める
    const changes = this.changes.list();
    const files = [...new Set(changes.map((change) => change.address.file))];
    const dirty = files.filter((file) => {
      const uri = profileFileUri(this.dir, file)?.toString();
      return vscode.workspace.textDocuments.some((document) => document.isDirty && document.uri.toString() === uri);
    });
    if (dirty.length > 0) {
      this.stop(`${dirty.join('、')} がテキストエディタで未保存です。テキストの変更を先に保存するか戻してください。`, dirty[0]);
    }

    // 2. 書き換えを作る。構造の error があれば保存しない（意味検証の error と warning は止めない）
    let plan: PlanEditsResult;
    try {
      plan = await this.server.request('profile/planEdits', this.draftParams());
    } catch (error) {
      return this.planFailed(error);
    }
    const errors = structureErrors(plan.diagnostics);
    if (errors.length > 0) {
      this.draftDiagnostics = plan.diagnostics;
      this.fire();
      this.stop(`読めない値があるので保存しませんでした（${errors[0]?.message}）。値を直してから保存してください。`);
    }
    if (cancellation.isCancellationRequested) throw new vscode.CancellationError();

    // 3〜5. 当てて保存し、profile/saved で知らせる。その間は見張りの知らせを溜める
    let snapshot: ProfileSnapshot | undefined;
    if (plan.files.length > 0) {
      const hold = this.watcher.hold();
      try {
        const versions = await this.applyPlan(plan.files);
        snapshot = await this.server.request('profile/saved', { profileId: this.profileId, files: versions });
      } catch (error) {
        if (error instanceof vscode.CancellationError) throw error;
        this.stop(`保存できませんでした（${errorMessage(error)}）。未保存の変更はそのまま残しています。`);
      } finally {
        hold.dispose();
      }
    }

    // 保存した変更を外す（保存の間に足した変更は、新しい snapshot に対する変更として残す）
    if (snapshot) this.snapshotValue = snapshot;
    for (const change of changes) {
      if (this.changes.get(change.address)?.value === change.value) this.changes.delete(change.address);
    }
    for (const change of this.changes.list()) this.changes.assign(change.address, change.value, snapshotValueAt(this.snapshotValue, change.address));
    this.draftDiagnostics = undefined;
    this.backupFiles = undefined;
    this.fire();
    this.validate();
  }

  /** WorkspaceEdit にして当て、TextDocument を保存する。保存したあとのファイルの版を返す */
  private async applyPlan(files: FileEdits[]): Promise<Record<string, FileVersion>> {
    const edit = new vscode.WorkspaceEdit();
    const uris = new Map<string, vscode.Uri>();
    for (const file of files) {
      const uri = profileFileUri(this.dir, file.file);
      if (!uri) this.stop(`設定ディレクトリの外のファイルは書き換えません: ${file.file}`);
      uris.set(file.file, uri);
      // サーバーが書き換えを作ったあとに外で変わった（作るはずのファイルが外でできた場合も）
      if ((await readVersion(uri)) !== file.baseVersion) {
        this.reportExternal([file.file]);
        this.stop(`${file.file} が外で変わったので保存しませんでした。外の変更の扱いを選んでから、もう一度保存してください。`);
      }
      // 開いている TextDocument がまだ外の変更を読み込んでいなければ（VS Code の読み直しは少し遅れる）、待ってから当てる。
      // 古い中身に当てると、保存が「ファイルが変更されています」で失敗する
      if (!file.create && !(await this.waitTextInSync(uri))) {
        this.stop(`${file.file} をテキストエディタが読み直していないので保存しませんでした。少し待ってから、もう一度保存してください。`, file.file);
      }
      if (file.create) edit.createFile(uri, { ignoreIfExists: true });
      for (const text of file.edits) {
        const { start, end } = text.range;
        edit.replace(uri, new vscode.Range(start.line, start.character, end.line, end.character), text.newText);
      }
    }
    if (!(await vscode.workspace.applyEdit(edit))) throw new Error('書き換えを当てられませんでした');
    const versions: Record<string, FileVersion> = {};
    for (const [file, uri] of uris) {
      const document = await vscode.workspace.openTextDocument(uri);
      if (document.isDirty && !(await document.save())) throw new Error(`${file} を保存できませんでした`);
      // 保存時の整形（files.insertFinalNewline など）のあとの中身の版（6.2 の 4）。BOM なども含めてサーバーが読むのと同じ、
      // 保存したあとのディスクのバイト列から作る
      versions[file] = await readVersion(uri);
    }
    return versions;
  }

  /** 開いている TextDocument の中身がディスクと同じになるまで待つ（開いていなければすぐ true。dirty は手前で止めている） */
  private async waitTextInSync(uri: vscode.Uri, timeoutMs = 2000): Promise<boolean> {
    const deadline = Date.now() + timeoutMs;
    for (;;) {
      const document = vscode.workspace.textDocuments.find((d) => d.uri.toString() === uri.toString());
      if (!document) return true;
      const disk = new TextDecoder().decode(await vscode.workspace.fs.readFile(uri)); // TextDecoder は BOM を除く
      if (document.getText() === disk) return true;
      if (Date.now() > deadline) return false;
      await new Promise((resolve) => setTimeout(resolve, 100));
    }
  }

  /** profile/planEdits の失敗を知らせて止める */
  private async planFailed(error: unknown): Promise<never> {
    const { code, data } = error as { code?: unknown; data?: unknown };
    if (code === ErrorCodes.VersionConflict) {
      const files = Object.keys((data as { files?: Record<string, FileVersion> } | undefined)?.files ?? {});
      // サーバーに読み直させる（知っている版と違えば profile/didChange が来て、保存のあとに 7.3 の扱いになる）
      this.reportExternal(files);
      // サーバーは届いた順に処理するので、次のリクエストの応答より前に profile/didChange が届く。
      // 届かなければ（サーバーはもう新しい版を知っているのに、拡張がその知らせを取りこぼした）、開き直して同じ扱いにする
      await this.server.request('profile/list', {}).catch(() => undefined);
      if (!this.deferred) await this.resync();
      this.stop(`${files.join('、') || '設定ファイル'} が外で変わっています。外の変更の扱いを選んでから、もう一度保存してください。`);
    }
    if (code === ErrorCodes.EditNotLocal) {
      const { address, reason } = (data ?? {}) as { address?: Address; reason?: string };
      const where = address ? describeAddress(this.snapshotValue, address) : '値';
      this.stop(
        `${where} は値の部分だけでは書き換えられないので保存しませんでした（${EDIT_NOT_LOCAL_REASONS[reason ?? ''] ?? reason ?? '理由不明'}）。テキストで直してください。`,
        address?.file,
      );
    }
    this.stop(`保存の書き換えを作れませんでした（${errorMessage(error)}）。`);
  }

  /** profile/open で開き直し、その snapshot を外での変更として扱う（保存の途中なら保存のあとに） */
  private async resync(): Promise<void> {
    const old = this.profileId;
    let fresh: ProfileSnapshot;
    try {
      fresh = await this.server.request('profile/open', { dir: this.dir });
    } catch {
      return;
    }
    if (this.closed) {
      this.server.notify('profile/close', { profileId: fresh.profileId });
      return;
    }
    this.server.notify('profile/close', { profileId: old });
    if (this.saving) this.deferred = fresh;
    else this.acceptExternal(fresh);
  }

  /** 利用者に知らせて保存をやめる（file があれば「ファイルを開く」のボタンを付ける） */
  private stop(message: string, file?: string): never {
    this.env.prompts().saveFailed(message, file ? () => void openProfileFile(this.dir, file) : undefined);
    throw new vscode.CancellationError();
  }

  /** 設定ディレクトリのファイルが変わったかもしれないとサーバーに知らせる（読み直して、知っている版と違えば profile/didChange） */
  private reportExternal(files: string[]): void {
    if (!profileDirPath(this.dir) || files.length === 0) return;
    const prefix = this.dir.replace(/\/+$/, '');
    this.server.notify('workspace/didChangeFiles', { changes: files.map((file) => ({ path: `${prefix}/${file}`, type: 'changed' })) });
  }

  // ---------------------------------------------------------------------------
  // 元に戻す（revert）とホットエグジット
  // ---------------------------------------------------------------------------

  /**
   * 未保存の変更を捨てて読み直す。保存の途中なら終わるのを待つ。
   * 「外の変更を残す」もここを通す（そのときは profile/didChange の snapshot を使い、読み直さない。聞いている間に次の知らせが来ていればそちら）
   */
  async revert(): Promise<void> {
    const run = this.runRevert();
    this.reverting = run;
    try {
      await run;
    } finally {
      if (this.reverting === run) this.reverting = undefined;
    }
  }

  private async runRevert(): Promise<void> {
    await this.saving?.catch(() => undefined);
    const snapshot = this.revertSnapshot;
    this.revertSnapshot = undefined;
    this.revertGeneration += 1;
    this.changes.clear();
    this.draftDiagnostics = undefined;
    this.validateGeneration += 1;
    this.changeBase = undefined;
    this.waitingBackup = undefined;
    this.backupFiles = undefined;
    const newer = this.external?.snapshot;
    this.external = undefined;
    if (snapshot) {
      this.adopt(newer ?? snapshot);
      return;
    }
    await this.reopen(true);
  }

  async backup(destination: vscode.Uri): Promise<vscode.CustomDocumentBackup> {
    const base = this.changeBase ?? this.snapshotValue;
    const changes = this.changes.list();
    const backup: Backup = {
      version: 1,
      dir: this.dir,
      files: base.files,
      changes,
      saved: Object.fromEntries(changes.map((change) => [addressKey(change.address), snapshotValueAt(base, change.address) ?? null])),
    };
    await vscode.workspace.fs.writeFile(destination, new TextEncoder().encode(JSON.stringify(backup)));
    return {
      id: destination.toString(),
      delete: () => void vscode.workspace.fs.delete(destination).then(undefined, () => undefined),
    };
  }

  /**
   * バックアップの変更を戻す。変更が触るファイルの版が今と違えば（閉じている間に外で変わった）7.3 と同じく聞く。
   * プロファイルが読めなければ、読めるようになるまで聞かずに待つ（読めない snapshot に当て直すと、すべて当て直せなくなるため）
   */
  private restoreBackup(backup: Backup): void {
    this.changes.replaceAll(backup.changes);
    this.backupFiles = backup.files;
    if (this.changes.size === 0) return;
    if (this.snapshotValue.status !== 'ok') {
      this.waitingBackup = { files: backup.files, saved: backup.saved };
      return;
    }
    this.checkBackup(backup, this.snapshotValue);
  }

  private checkBackup(backup: Pick<Backup, 'files' | 'saved'>, snapshot: ProfileSnapshot): void {
    if (changedFiles(this.changes.list(), backup.files, snapshot.files).length > 0) {
      this.ask({ snapshot, reason: 'backup', before: backupBefore(snapshot, backup.files, backup.saved) });
    } else {
      this.validate();
    }
  }

  // ---------------------------------------------------------------------------
  // 外での変更（protocol.md の 7.2・7.3）
  // ---------------------------------------------------------------------------

  /** profile/didChange。未保存の変更がなければ黙って描き直し、あればどちらを残すか聞く */
  handleExternalChange(params: ProfileDidChangeParams): void {
    if (this.closed) return;
    // 開き直し（resync・再起動）で、聞いている snapshot の profileId が新しくなっていることがある
    if (params.profileId !== this.profileId && params.profileId !== this.external?.snapshot.profileId) return;
    if (this.saving) {
      this.deferred = params.snapshot;
      return;
    }
    this.acceptExternal(params.snapshot);
  }

  private acceptExternal(snapshot: ProfileSnapshot): void {
    if (this.changes.size === 0 && !this.external && !this.resolving) {
      this.changeBase = undefined;
      this.waitingBackup = undefined;
      this.draftDiagnostics = undefined;
      this.adopt(snapshot);
      return;
    }
    if (snapshot.status !== 'ok') {
      // 読めない間は聞かずに待つ（Claude が書きかけのときなど）。画面は読めない表示にし、変更を作ったときの snapshot を覚えておく
      if (this.snapshotValue.status === 'ok') this.changeBase ??= this.snapshotValue;
      if (this.external && this.external.snapshot.status === 'ok') this.changeBase ??= this.external.snapshot;
      this.external = undefined;
      this.snapshotValue = snapshot;
      this.fire();
      return;
    }
    if (this.waitingBackup) {
      // ホットエグジットから戻したときに読めなかったプロファイルが読めるようになった
      const backup = this.waitingBackup;
      this.waitingBackup = undefined;
      this.adopt(snapshot);
      this.checkBackup(backup, snapshot);
      return;
    }
    if (this.changeBase) {
      // 読めるようになった: 変更を作ったときの snapshot に戻して描き、そこから当て直すかを聞く
      this.snapshotValue = this.changeBase;
      this.changeBase = undefined;
      this.fire();
    }
    this.ask({ snapshot, reason: 'external' });
  }

  /** どちらを残すか聞く。聞いている間に次の知らせが来れば、答えたあとにいちばん新しい snapshot で扱う */
  private ask(change: ExternalChange): void {
    if (this.external) this.external.snapshot = change.snapshot;
    else this.external = change;
    this.resolving ??= this.resolveExternal().finally(() => {
      this.resolving = undefined;
    });
  }

  private async resolveExternal(): Promise<void> {
    const prompts = this.env.prompts();
    while (this.external && !this.closed) {
      if (this.changes.size === 0) {
        // 聞く前に変更がなくなった（undo など）: 黙って描き直す
        const { snapshot } = this.external;
        this.external = undefined;
        this.adopt(snapshot);
        continue;
      }
      const { reason } = this.external;
      // 閉じた（答えなかった）ときは画面の変更を残す（利用者の変更を黙って捨てない。未保存のままなので戻すこともできる）
      const choice = (await prompts.chooseSide(this.snapshotValue.name, this.changes.size, reason)) ?? 'screen';
      const latest = this.external;
      this.external = undefined;
      if (!latest || this.closed) continue; // 聞いている間に revert した
      if (choice === 'external') await this.keepExternal(latest.snapshot);
      else await this.keepScreen(latest);
    }
  }

  /** 「画面の変更を残す」: Change を新しい snapshot に当て直す（7.3） */
  private async keepScreen(change: ExternalChange): Promise<void> {
    const prompts = this.env.prompts();
    const generation = this.revertGeneration;
    const target = change.snapshot;
    const base = this.snapshotValue;
    const before = change.before ?? ((address: Address) => snapshotValueAt(base, address));
    const original = this.changes.list();
    const { kept, conflicts, lost } = rebaseChanges(original, before, target);
    const result = [...kept];
    if (conflicts.length > 0) {
      const chosen = await prompts.resolveConflicts(
        target.name,
        conflicts.map((conflict) => ({
          label: describeAddress(target, conflict.change.address),
          screen: describeValue(conflict.change.value),
          external: describeValue(conflict.external),
        })),
      );
      if (generation !== this.revertGeneration || this.closed) return; // 聞いている間に revert した
      // 閉じたときは画面の値を残す
      const keep = new Set(chosen ?? conflicts.map((_, index) => index));
      conflicts.forEach((conflict, index) => {
        if (keep.has(index)) result.push(conflict.change);
      });
    }
    if (lost.length > 0) {
      const answer = await prompts.confirmLost(target.name, this.lostItems(lost, base));
      if (generation !== this.revertGeneration || this.closed) return;
      if (answer === 'external') {
        await this.keepExternal(target);
        return;
      }
      // 閉じたときは捨てずに残す（場所が見つからないので画面には出ず、保存のときにもう一度聞く）
      if (answer !== 'discard') result.push(...lost);
    }
    // 聞いている間の画面の操作を活かす: 変えた・足したものは画面の新しい値、undo などで外したものは当て直さない
    const originalValues = new Map(original.map((c) => [addressKey(c.address), c.value]));
    const now = this.changes.list();
    const nowKeys = new Set(now.map((c) => addressKey(c.address)));
    const edited = now.filter((c) => originalValues.get(addressKey(c.address)) !== c.value);
    const editedKeys = new Set(edited.map((c) => addressKey(c.address)));
    const removed = new Set(original.map((c) => addressKey(c.address)).filter((key) => !nowKeys.has(key)));
    this.snapshotValue = target;
    this.epoch += 1;
    this.backupFiles = undefined;
    this.draftDiagnostics = undefined;
    this.changes.clear();
    for (const c of [...result.filter((c) => !editedKeys.has(addressKey(c.address)) && !removed.has(addressKey(c.address))), ...edited]) {
      const saved = snapshotValueAt(target, c.address);
      // 場所が見つからない変更は比べずに残す
      if (saved === undefined) this.changes.set(c);
      else this.changes.assign(c.address, c.value, saved);
    }
    if (this.changes.size === 0) {
      // 残る変更がない: revert を通して dirty を消す
      await this.keepExternal(target);
      return;
    }
    this.fire();
    this.validate();
  }

  private lostItems(lost: Change[], snapshot: ProfileSnapshot) {
    return lost.map((c) => ({ label: describeAddress(snapshot, c.address), value: describeValue(c.value) }));
  }

  /**
   * 「外の変更を残す」: 未保存の変更を捨てて snapshot で描き直す。CustomEditor の dirty は保存か revert でしか消えないので、
   * 編集画面を前に出して VS Code の revert を通す（revert が revertSnapshot を使う）。前に出せなければ変更だけを捨てる
   */
  private async keepExternal(snapshot: ProfileSnapshot): Promise<void> {
    this.revertSnapshot = snapshot;
    try {
      await vscode.commands.executeCommand('vscode.openWith', this.uri, PROFILE_EDITOR_VIEW_TYPE);
      const tab = vscode.window.tabGroups.activeTabGroup.activeTab;
      // ほかのエディタを戻さないよう、前に出たのがこのドキュメントのときだけ
      if (tab?.input instanceof vscode.TabInputCustom && tab.input.uri.toString() === this.uri.toString()) {
        await vscode.commands.executeCommand('workbench.action.files.revert');
      }
    } catch {
      // 下で変更だけを捨てる
    }
    if (this.revertSnapshot === undefined) return; // revert を通った
    this.revertSnapshot = undefined;
    this.changes.clear();
    this.draftDiagnostics = undefined;
    this.changeBase = undefined;
    this.backupFiles = undefined;
    const newer = this.external?.snapshot;
    this.external = undefined;
    this.adopt(newer ?? snapshot);
  }

  /** 外の変更（か読み直した中身）の snapshot で描き直す */
  private adopt(snapshot: ProfileSnapshot): void {
    this.snapshotValue = snapshot;
    this.epoch += 1;
    this.fire();
  }

  /** 保存の間に来た profile/didChange を扱う（保存で読み直した版と同じなら何もしない） */
  private flushDeferred(): void {
    const snapshot = this.deferred;
    this.deferred = undefined;
    if (!snapshot || this.closed) return;
    if (snapshot.profileId === this.profileId && sameFiles(snapshot.files, this.snapshotValue.files)) return;
    this.acceptExternal(snapshot);
  }

  /**
   * profile/open からやり直す（profileId は変わる）。closeOld は同じサーバーに前の profileId を閉じさせるとき
   * （再起動したあとの新しいサーバーは前の profileId を知らないので送らない）。
   * 再起動のあとに未保存の変更が触るファイルの版が変わっていれば（落ちている間に外で変わった）、7.3 と同じく聞く
   */
  private async reopen(closeOld: boolean): Promise<void> {
    const old = this.snapshotValue;
    let fresh: ProfileSnapshot;
    try {
      fresh = await this.server.request('profile/open', { dir: this.dir });
    } catch {
      return; // 知らせはサーバーの側で出している。開き直せなければ前の profileId のまま
    }
    // 開き直せてから前の profileId を閉じる
    if (closeOld) this.server.notify('profile/close', { profileId: old.profileId });
    if (this.closed) {
      this.server.notify('profile/close', { profileId: fresh.profileId });
      return;
    }
    const base = this.changeBase ?? old;
    if (this.changes.size > 0 && (fresh.status !== 'ok' || changedFiles(this.changes.list(), base.files, fresh.files).length > 0)) {
      // 前の snapshot の profileId は新しいサーバーにはないので、聞いている間の検証は失敗する（当て直したあとに検証し直す）
      this.acceptExternal(fresh);
      return;
    }
    this.adopt(fresh);
    this.validate();
  }

  private fire(): void {
    if (!this.closed) this.onDidChangeContentEmitter.fire();
  }

  dispose(): void {
    this.closed = true;
    this.validateGeneration += 1;
    const ids = new Set([this.profileId, this.external?.snapshot.profileId].filter((id): id is string => id !== undefined));
    for (const profileId of ids) this.server.notify('profile/close', { profileId });
    for (const disposable of this.disposables) disposable.dispose();
    this.onDidDisposeEmitter.fire();
    this.onDidDisposeEmitter.dispose();
    this.onDidEditEmitter.dispose();
    this.onDidChangeContentEmitter.dispose();
  }
}

const EDIT_NOT_LOCAL_REASONS: Record<string, string> = {
  multiline: '複数行の値',
  anchor: 'アンカーとエイリアス',
  flowInsert: 'フロー表記の中への挿入',
};

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

/** ディスクのファイルの版（なければ null） */
async function readVersion(uri: vscode.Uri): Promise<FileVersion> {
  try {
    return fileVersionOf(await vscode.workspace.fs.readFile(uri));
  } catch {
    return null;
  }
}

/** バックアップを読む。形が違う（版が違う・壊れている）ときは undefined（変更なしで開く） */
async function readBackup(uri: vscode.Uri): Promise<Backup | undefined> {
  try {
    const data = JSON.parse(new TextDecoder().decode(await vscode.workspace.fs.readFile(uri))) as Partial<Backup>;
    if (data.version !== 1 || !Array.isArray(data.changes) || typeof data.files !== 'object' || data.files === null) return undefined;
    if (data.saved !== undefined && (typeof data.saved !== 'object' || data.saved === null)) return undefined;
    return data as Backup;
  } catch {
    return undefined;
  }
}
