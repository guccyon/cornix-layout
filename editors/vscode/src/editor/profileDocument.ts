// プロファイル 1 つ分の仮想ドキュメント（ADR 015）。サーバーの ProfileSnapshot と未保存の変更（AnyChange の当てる順の並び）を持つ。
// 変更は VS Code の編集（CustomDocumentEditEvent）として渡すので、dirty の印・元に戻す・やり直し・閉じるときの確認は VS Code が面倒をみる。
// 保存は protocol.md の 6.2（profile/planEdits → WorkspaceEdit → TextDocument#save → profile/saved）、
// 外での変更は 7.3・12.3（未保存がなければ黙って描き直す。あればどちらを残すか聞き、画面の変更を残すなら Change を当て直す。
// 並びを指す Change のあるファイルが外で変わったら、そのファイルの Change は当て直せないもの）、
// 項目の追加・削除・名前の変更は 12.5（確認のダイアログのあと、ファイルの作成・削除・改名を含む WorkspaceEdit をすぐ当てて保存する）。
// 方針: 利用者の変更を黙って捨てない（問いを閉じたら捨てずに残す側に倒す）。
import * as vscode from 'vscode';
import {
  ErrorCodes,
  type Address,
  type AnyChange,
  type Diagnostic,
  type DraftParams,
  type FileEdits,
  type FileVersion,
  type ItemEdit,
  type ItemFileEdits,
  type PlanEditsResult,
  type PlanItemEditResult,
  type ProfileDidChangeParams,
  type ProfileSnapshot,
} from '../protocol';
import type { CornixServer } from '../server/cornixServer';
import { describeItemEdit, itemEditErrorMessage, itemEditTitle } from './itemEdits';
import {
  PendingChanges,
  fieldOf,
  isAnyChange,
  isSequential,
  snapshotValueAt,
  valueKey,
  type ChangeField,
  type ChangeValue,
  type SavedValue,
} from './pendingChanges';
import { openProfileFile, profileDirPath, profileFileUri } from './profileFiles';
import { PROFILE_EDITOR_VIEW_TYPE } from './profileUri';
import { ProfileWatcher } from './profileWatcher';
import type { ProfilePrompts } from './prompts';
import {
  backupBefore,
  changedFiles,
  describeAddress,
  describeChange,
  describeValue,
  fileVersionOf,
  inverseOf,
  rebaseChanges,
  sameFiles,
  screenValue,
  structureErrors,
  unrebaseableFiles,
  type ValueBefore,
} from './rebase';

/**
 * ホットエグジットのときに書き出す中身。files は変更を作ったときのファイルの版（snapshot.files）で、
 * 戻したときに閉じている間の外での変更を見分ける。changes は当てる順の並び（12.3 の AnyChange）。
 * saved は変更を作ったときの並びの外の場所の値（valueKey → 値）で、外で同じ場所も変わったかを見分ける
 * （ない古いバックアップでは、版の違うファイルの変更はすべて選ばせる）
 */
type Backup = {
  version: 1;
  dir: string;
  files: Record<string, FileVersion>;
  changes: AnyChange[];
  saved?: Record<string, ChangeValue | null>;
};

/** 項目の操作を途中でやめる（message を利用者に知らせる。file があれば「ファイルを開く」） */
class ItemEditStop extends Error {
  constructor(
    message: string,
    readonly file?: string,
  ) {
    super(message);
  }
}

function labelOf(change: AnyChange): string {
  switch (change.op) {
    case 'insert':
      return '追加';
    case 'remove':
      return fieldOf(change) === 'note' ? '注記の削除' : '削除';
    case 'move':
      return '移動';
    default:
      return fieldOf(change) === 'note' ? '注記の変更' : '値の変更';
  }
}

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
  before?: ValueBefore;
  /** 外の変更の前のファイルの版（並びを指す Change のあるファイルが変わったかを見る）。省けば当て直すときの snapshotValue の files */
  beforeFiles?: Record<string, FileVersion>;
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
  /** 保存が終わってから行うこと（保存の中からは revert を通せないため） */
  private afterSave: (() => Promise<void>) | undefined;
  /** テスト用: 当てる直前（TextDocument を待ったあと、版を確かめ直す前）に呼ぶ */
  onBeforeApply: (() => Promise<void>) | undefined;
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
  /**
   * 当て直せないと見せたのに、問いを閉じて残した Change（並びを指す Change のあるファイルが外で変わったときなど）。
   * 場所が見つからない変更と同じく、保存のときにもう一度聞く
   */
  private readonly lostChanges = new WeakSet<AnyChange>();
  /** 並びの外の場所の保存済みの値（今の snapshot から） */
  private readonly savedValue: SavedValue = (address, field) => snapshotValueAt(this.snapshotValue, address, field);

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
   * 画面での変更を 1 つ足す（Webview の change と edit）。元に戻す・やり直しもここで作る。
   * 並びは PendingChanges が畳む（並びの外の set / remove は同じ場所の前の変更を置き換え、並びを指すものは足した順のまま）。
   * 編集ごとに足す前と後の並び（配列そのもの）を持ち、そのあと並びが変わっていなければ undo・redo はその並びに戻す。
   * 保存や外での変更で並びが変わったあとの undo・redo は、並びの外の変更なら「前の値（そのときの未保存の値か snapshot の値）」と
   * 「新しい値」を今の snapshot に対して当てる（保存のあとに戻すと、ディスクの値に対する変更として残る）。
   * ただし前の値が snapshot の値だった（未保存の変更がなかった）編集を、外の変更を取り込んだあとに戻すときは、
   * 外の変更の前の値ではなく今の snapshot の値に戻す（変更を外す）。利用者が見ていない値で外の変更を黙って戻さないため。
   * 並びを指す変更は、まだ並びにあればそれを外し、保存したあとなら逆の Change（insert は remove、move は戻す move）を足す。
   * 逆の Change を作れないもの（並びの要素の set と remove。前の値が分からない）は戻さない
   */
  applyChange(change: AnyChange, label = labelOf(change)): void {
    if (!isAnyChange(change)) return;
    const sequential = isSequential(change);
    const field = fieldOf(change);
    const hadChange = !sequential && this.changes.pendingValue(change.address, field) !== undefined;
    const beforeValue = sequential ? null : this.currentValue(change.address, field);
    const epoch = this.epoch;
    const before = this.changes.current();
    this.changes.add(change, this.savedValue);
    const after = this.changes.current();
    this.changed();
    let inverse: AnyChange | undefined;
    this.onDidEditEmitter.fire({
      document: this,
      label,
      undo: () => {
        if (this.changes.current() === after) this.changes.restore(before);
        else if (!sequential) this.assignValue(change.address, field, !hadChange && this.epoch !== epoch ? undefined : beforeValue);
        else if (this.changes.current().includes(change)) this.changes.remove(change);
        else if ((inverse = inverseOf(change))) this.changes.add(inverse, this.savedValue);
        this.changed();
      },
      redo: () => {
        if (this.changes.current() === before) this.changes.restore(after);
        else if (!sequential) this.changes.add(change, this.savedValue);
        else if (inverse && this.changes.current().includes(inverse)) this.changes.remove(inverse);
        else if (!this.changes.current().includes(change)) this.changes.add(change, this.savedValue);
        inverse = undefined;
        this.changed();
      },
    });
  }

  /**
   * 画面に出す値（並びの外の場所。未保存の変更があればその値（消したなら null）、なければ snapshot の値。どちらもなければ null）。
   * 並びの要素は前の Change で位置がずれるので、ここでは見ない
   */
  currentValue(address: Address, field: ChangeField = 'key'): ChangeValue | null {
    const pending = this.changes.pendingValue(address, field);
    if (pending !== undefined) return pending;
    return snapshotValueAt(this.snapshotValue, address, field) ?? null;
  }

  /** 並びの外の場所を value にする（null は消す、undefined は未保存の変更を外す）。今の snapshot に対する変更になる */
  private assignValue(address: Address, field: ChangeField, value: ChangeValue | null | undefined): void {
    if (value === undefined) this.changes.discard(address, field);
    else if (value === null) this.changes.add({ op: 'remove', address, ...(field === 'note' ? { field } : {}) }, this.savedValue);
    // v0.1 の形（op を省けば set）のまま作る
    else this.changes.add({ address, value, ...(field === 'note' ? { field } : {}) }, this.savedValue);
  }

  /** 未保存の変更が変わった: 描き直して検証し直す */
  private changed(): void {
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

  /**
   * 今の未保存の変更の profile/validate・profile/planEdits の params。changes は当てる順の並び（12.3 の AnyChange）。
   * protocol.ts の DraftParams.changes は v0.1 の Change[] のままなので、型だけ合わせる
   */
  private draftParams(): DraftParams {
    return {
      profileId: this.profileId,
      baseVersions: this.changes.baseVersions(this.snapshotValue.files),
      changes: this.changes.list() as DraftParams['changes'],
    };
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
        const after = this.afterSave;
        this.afterSave = undefined;
        if (after) void after();
      }
      // VS Code は保存の Promise が解決したあとに、そのときの編集の位置を保存点にする。保存の間に画面で足した変更（と undo・redo）も
      // 保存点の手前に入るので、変更が残っていれば保存点を置いたあと（次のタスク）に編集を 1 つ足して dirty に戻す
      if (saved) setTimeout(() => this.markRemainingDirty(), 0);
    }
  }

  /**
   * 保存のあとに残った未保存の変更を、1 つの編集として VS Code の履歴に載せる。
   * undo はそのときの保存済みの値に戻し（applyChange と同じく、もう一度保存したあとならディスクの値に対する変更として残る）、redo で戻す
   */
  private markRemainingDirty(): void {
    const remaining = this.changes.current();
    if (this.closed || remaining.length === 0 || this.saving) return;
    // 並びの外の場所は、そのときの保存済みの値（なければ未保存の変更を外す）に戻す
    const saved = remaining
      .filter((change) => !isSequential(change))
      .map((change) => [change.address, fieldOf(change), this.savedValue(change.address, fieldOf(change)) ?? undefined] as const);
    this.onDidEditEmitter.fire({
      document: this,
      label: '保存の間の変更',
      undo: () => {
        if (this.changes.current() === remaining) this.changes.restore([]);
        else {
          for (const [address, field, value] of saved) this.assignValue(address, field, value);
          for (const change of remaining) if (isSequential(change)) this.changes.remove(change);
        }
        this.changed();
      },
      redo: () => {
        if (this.changes.size === 0) this.changes.restore(remaining);
        else for (const change of remaining) if (!this.changes.current().includes(change)) this.changes.add(change, this.savedValue);
        this.changed();
      },
    });
  }

  private async runSave(cancellation: vscode.CancellationToken): Promise<void> {
    if (this.changes.size === 0) return;
    if (this.snapshotValue.status !== 'ok') this.stop('プロファイルが読めない状態なので保存しません。設定ファイルをテキストで直してください。');
    if (this.external || this.resolving) this.stop('設定ファイルが外で変わっています。どちらの変更を残すか選んでから、もう一度保存してください。');

    // 場所が見つからない変更・当て直せない変更（外での変更で当て直せず、捨てなかったもの）があれば、捨てるか聞き直す
    const lost = this.changes.list().filter((change) => this.isLost(change));
    if (lost.length > 0) {
      const answer = await this.env.prompts().confirmLost(this.snapshotValue.name, this.lostItems(lost, this.snapshotValue));
      if (answer === 'external') {
        // 画面の変更をすべて捨てる。revert は保存が終わるのを待つので、保存を止めたあとに通す
        const snapshot = this.snapshotValue;
        this.afterSave = () => this.keepExternal(snapshot);
        throw new vscode.CancellationError();
      }
      if (answer !== 'discard') {
        this.stop('場所が見つからない未保存の変更があるので保存しませんでした。捨てるか、テキストで直してください。');
      }
      for (const change of lost) this.changes.remove(change);
      this.changed();
      if (this.changes.size === 0) return;
    }

    // 1. 書き換える対象のファイルがテキストエディタで未保存なら止める
    const sent = this.changes.current();
    const files = [...new Set(sent.map((change) => change.address.file))];
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
        const versions = await this.applyPlan(plan.files, cancellation);
        snapshot = await this.server.request('profile/saved', { profileId: this.profileId, files: versions });
      } catch (error) {
        if (error instanceof vscode.CancellationError) throw error;
        this.stop(`保存できませんでした（${errorMessage(error)}）。未保存の変更はそのまま残しています。`);
      } finally {
        hold.dispose();
      }
    }

    // 保存した並びの外の場所は、今の画面の値（保存の間の変更や undo を含む。古い snapshot で取る）を新しい snapshot に当て直す。
    // 保存した値と同じなら外れ、違えば（保存の間に変えた・戻した）新しい snapshot に対する変更として残る。
    // 並びを指す変更は、保存したものを外し、保存の間に足したものをそのまま残す（保存したものを当てたあとの位置で数えているので）。
    // 保存の間に undo で外した並びの変更はディスクには入ったので、逆の Change を作れれば足す
    const now = this.changes.current();
    const sentSet = new Set(sent);
    const nowSet = new Set(now);
    const places = new Map<string, readonly [Address, ChangeField]>();
    for (const change of sent) if (!isSequential(change)) places.set(valueKey(change.address, fieldOf(change)), [change.address, fieldOf(change)]);
    const screen = [...places.values()].map(([address, field]) => [address, field, this.currentValue(address, field)] as const);
    const undone = sent.filter((change) => isSequential(change) && !nowSet.has(change)).map(inverseOf).reverse();
    const added = now.filter((change) => !sentSet.has(change));
    if (snapshot) this.snapshotValue = snapshot;
    this.changes.clear();
    for (const [address, field, value] of screen) {
      if (value !== null || this.savedValue(address, field) !== undefined) this.assignValue(address, field, value);
    }
    for (const change of undone) if (change) this.changes.add(change, this.savedValue);
    for (const change of added) {
      if (isSequential(change) || this.savedValue(change.address, fieldOf(change)) !== undefined) this.changes.add(change, this.savedValue);
      else this.changes.restore([...this.changes.current(), change]); // 場所が見つからない変更は比べずに残す
    }
    this.draftDiagnostics = undefined;
    this.backupFiles = undefined;
    this.changed();
  }

  /** 保存のときにもう一度聞く変更（当て直せないと見せて残したもの、並びの外で snapshot に場所が見つからないもの） */
  private isLost(change: AnyChange): boolean {
    if (this.lostChanges.has(change)) return true;
    if (isSequential(change)) return !(change.address.file in this.snapshotValue.files) || this.snapshotValue.files[change.address.file] === null;
    return snapshotValueAt(this.snapshotValue, change.address, fieldOf(change)) === undefined;
  }

  /**
   * WorkspaceEdit にして当て、TextDocument を保存する。保存したあとのファイルの版を返す。
   * 当てる前に、ディスクの版が baseVersion と同じか確かめ、開いている TextDocument が外の変更を読み直すのを待ってから、
   * 当てる直前にもう一度、ディスクと TextDocument の中身の両方の版が baseVersion と同じかを確かめる（待っている間に外で書かれても古い書き換えを当てない）
   */
  private async applyPlan(files: FileEdits[], cancellation: vscode.CancellationToken): Promise<Record<string, FileVersion>> {
    const uris = new Map<string, vscode.Uri>();
    for (const file of files) {
      const uri = profileFileUri(this.dir, file.file);
      if (!uri) this.stop(`設定ディレクトリの外のファイルは書き換えません: ${file.file}`);
      uris.set(file.file, uri);
      this.checkDiskVersion(file, await readVersion(uri));
      // 開いている TextDocument がまだ外の変更を読み込んでいなければ（VS Code の読み直しは少し遅れる）、待ってから当てる
      if (!file.create) await this.waitTextInSync(file.file, uri, cancellation);
    }
    await this.onBeforeApply?.();
    const edit = new vscode.WorkspaceEdit();
    for (const file of files) {
      const uri = uris.get(file.file)!;
      this.checkDiskVersion(file, await readVersion(uri));
      if (!file.create && (await textVersion(uri)) !== file.baseVersion) this.changedOutside(file.file);
      if (file.create) edit.createFile(uri, { ignoreIfExists: true });
      for (const text of file.edits) {
        const { start, end } = text.range;
        edit.replace(uri, new vscode.Range(start.line, start.character, end.line, end.character), text.newText);
      }
    }
    if (cancellation.isCancellationRequested) throw new vscode.CancellationError();
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

  /** ディスクの版が書き換えを作ったときの版と違えば（作るはずのファイルが外でできた場合も）止めて、外での変更の扱いへ */
  private checkDiskVersion(file: FileEdits, version: FileVersion): void {
    if (version !== file.baseVersion) this.changedOutside(file.file);
  }

  private changedOutside(file: string): never {
    this.reportExternal([file]);
    this.stop(`${file} が外で変わったので保存しませんでした。外の変更の扱いを選んでから、もう一度保存してください。`);
  }

  /**
   * 開いている TextDocument の中身がディスクと同じになるまで待つ（開いていなければすぐ戻る。dirty は手前で止めている）。
   * 待っても同じにならなければ止める。読み直し（document.version が増える）もないまま違うのは、改行の LF と CRLF の混在や
   * UTF-8 でないエンコーディングで、VS Code が読んだ中身がディスクと一致しないファイル（値の部分だけを書き換えられない）
   */
  private async waitTextInSync(
    file: string,
    uri: vscode.Uri,
    cancellation: vscode.CancellationToken | undefined,
    fail: (message: string, file?: string) => never = (message, at) => this.stop(message, at),
    timeoutMs = 2000,
  ): Promise<void> {
    const deadline = Date.now() + timeoutMs;
    const find = () => vscode.workspace.textDocuments.find((d) => d.uri.toString() === uri.toString());
    const first = find()?.version;
    for (;;) {
      if (cancellation?.isCancellationRequested) throw new vscode.CancellationError();
      const document = find();
      if (!document) return;
      const disk = new TextDecoder().decode(await vscode.workspace.fs.readFile(uri)); // TextDecoder は BOM を除く
      if (document.getText() === disk) return;
      if (Date.now() > deadline) {
        if (document.version === first) {
          fail(
            `${file} はテキストエディタが読んだ中身とディスクの中身が一致しないので保存しませんでした（改行の LF と CRLF の混在や、UTF-8 でないエンコーディングなど）。テキストエディタで開いて改行やエンコーディングをそろえて保存してから、もう一度保存してください。`,
            file,
          );
        }
        fail(`${file} をテキストエディタが読み直していないので保存しませんでした。少し待ってから、もう一度保存してください。`, file);
      }
      await new Promise((resolve) => setTimeout(resolve, 100));
    }
  }

  // ---------------------------------------------------------------------------
  // 項目の追加・削除・名前の変更（protocol.md の 12.5）
  // ---------------------------------------------------------------------------

  /**
   * 項目の操作を確認のダイアログのあとすぐファイルに書く（未保存の変更には積まない。tasks-v0.2.md の決めたことの 2）。
   * 未保存の変更があれば先に保存を促す（保存するか、やめるか）。書けたら true
   */
  async applyItemEdit(edit: ItemEdit): Promise<boolean> {
    const fail = (message: string, file?: string) => {
      this.env.prompts().itemEditFailed(message, file ? () => void openProfileFile(this.dir, file) : undefined);
      return false;
    };
    await this.saving?.catch(() => undefined);
    if (this.snapshotValue.status !== 'ok') return fail('プロファイルが読めない状態なので、項目を変えられません。設定ファイルをテキストで直してください。');
    if (this.external || this.resolving) return fail('設定ファイルが外で変わっています。どちらの変更を残すか選んでから、もう一度試してください。');
    if (this.changes.size > 0) {
      if (!(await this.env.prompts().confirmSaveFirst(this.snapshotValue.name, this.changes.size))) return false;
      await this.saveWithVsCode();
      // 保存できなかった（理由は保存の流れが知らせている）
      if (this.changes.size > 0) return false;
    }
    const previous = this.saving;
    const run = (async () => {
      await previous?.catch(() => undefined);
      return this.runItemEdit(edit);
    })();
    const running = run.then(() => undefined);
    this.saving = running;
    try {
      return await run;
    } catch (error) {
      if (error instanceof ItemEditStop) return fail(error.message, error.file);
      return fail(`${itemEditTitle(edit).replace(/。$/, '')}が、途中で失敗しました（${errorMessage(error)}）。`);
    } finally {
      if (this.saving === running) {
        this.saving = undefined;
        this.flushDeferred();
      }
    }
  }

  /** 編集画面を前に出して、VS Code の保存（dirty の印も消える）を通す */
  private async saveWithVsCode(): Promise<void> {
    try {
      await vscode.commands.executeCommand('vscode.openWith', this.uri, PROFILE_EDITOR_VIEW_TYPE);
      const tab = vscode.window.tabGroups.activeTabGroup.activeTab;
      if (tab?.input instanceof vscode.TabInputCustom && tab.input.uri.toString() === this.uri.toString()) {
        await vscode.commands.executeCommand('workbench.action.files.save');
      }
    } catch {
      // 保存できなければ未保存の変更が残り、呼び出し側がやめる
    }
    await this.settled();
  }

  private async runItemEdit(edit: ItemEdit): Promise<boolean> {
    const stop = (message: string, file?: string): never => {
      throw new ItemEditStop(message, file);
    };
    let plan: PlanItemEditResult;
    try {
      plan = await this.server.planItemEdit({ profileId: this.profileId, baseVersions: { ...this.snapshotValue.files }, edit });
    } catch (error) {
      const { code, data } = error as { code?: unknown; data?: unknown };
      if (code === ErrorCodes.VersionConflict) this.reportExternal(Object.keys((data as { files?: Record<string, FileVersion> } | undefined)?.files ?? {}));
      const address = (data as { address?: Address } | undefined)?.address;
      return stop(itemEditErrorMessage(edit, error), code === ErrorCodes.EditNotLocal ? address?.file : undefined);
    }
    if (plan.files.length === 0) return true;

    // 書き換える・消す・改名するファイルがテキストエディタで未保存なら止める
    const touched = plan.files.flatMap((file) => [file.file, ...(file.renameTo ? [file.renameTo] : [])]);
    const dirty = touched.filter((file) => {
      const uri = profileFileUri(this.dir, file)?.toString();
      return vscode.workspace.textDocuments.some((document) => document.isDirty && document.uri.toString() === uri);
    });
    if (dirty.length > 0) stop(`${dirty.join('、')} がテキストエディタで未保存です。テキストの変更を先に保存するか戻してください。`, dirty[0]);

    const { message, detail } = describeItemEdit(edit, plan);
    if (!(await this.env.prompts().confirmItemEdit(message, detail))) return false;
    if (this.closed) return false;
    if (this.changes.size > 0) stop('確認の間に画面で変更したので、やめました。変更を保存してから、もう一度試してください。');
    if (this.external || this.resolving) stop('確認の間に設定ファイルが外で変わったので、やめました。もう一度試してください。');

    const hold = this.watcher.hold();
    let snapshot: ProfileSnapshot;
    try {
      const versions = await this.applyItemPlan(plan.files, stop);
      snapshot = await this.server.request('profile/saved', { profileId: this.profileId, files: versions });
    } finally {
      hold.dispose();
    }
    this.draftDiagnostics = undefined;
    // 書いている間に画面で足した変更があれば（ダイアログのあとの短い間だけ）、そのまま新しい snapshot に対する変更として残す
    if (this.changes.size === 0) this.adopt(snapshot);
    else {
      this.snapshotValue = snapshot;
      this.epoch += 1;
      this.changed();
    }
    return true;
  }

  /**
   * profile/planItemEdit の files を 1 つの WorkspaceEdit（createFile / deleteFile / renameFile と replace）にして当て、
   * 書き換えたファイルを保存する。保存したあとの版を返す（消したファイルは null、改名は古い名前に null・新しい名前に版）。
   * 当てる前のディスクの版の照合は 6.2 と同じ（作るファイルはないこと、改名の行き先もないこと）
   */
  private async applyItemPlan(files: ItemFileEdits[], stop: (message: string, file?: string) => never): Promise<Record<string, FileVersion>> {
    const entries = files.map((file) => {
      const uri = profileFileUri(this.dir, file.file);
      const target = file.renameTo ? profileFileUri(this.dir, file.renameTo) : undefined;
      if (!uri || (file.renameTo && !target)) stop(`設定ディレクトリの外のファイルは書き換えません: ${file.renameTo ?? file.file}`);
      return { file, uri: uri!, target };
    });
    const outside = (file: string): never => {
      this.reportExternal([file]);
      return stop(`${file} が外で変わったので、やめました。外の変更を取り込んでから、もう一度試してください。`);
    };
    const check = async () => {
      for (const { file, uri, target } of entries) {
        if ((await readVersion(uri)) !== (file.create ? null : file.baseVersion)) outside(file.file);
        if (target && (await readVersion(target)) !== null) stop(`${file.renameTo} がすでにあるので、名前を変えられません。`);
      }
    };
    await check();
    for (const { file, uri } of entries) {
      if (!file.create && !file.delete && file.edits.length > 0) await this.waitTextInSync(file.file, uri, undefined, stop);
    }
    await this.onBeforeApply?.();
    await check();
    for (const { file, uri } of entries) {
      if (!file.create && !file.delete && file.edits.length > 0 && (await textVersion(uri)) !== file.baseVersion) outside(file.file);
    }

    const edit = new vscode.WorkspaceEdit();
    const versions: Record<string, FileVersion> = {};
    /** 書き換えたあとに保存して版を読むファイル（設定ディレクトリからの相対パスと URI） */
    const written: [string, vscode.Uri][] = [];
    for (const { file, uri, target } of entries) {
      const replace = (at: vscode.Uri) => {
        for (const text of file.edits) {
          const { start, end } = text.range;
          edit.replace(at, new vscode.Range(start.line, start.character, end.line, end.character), text.newText);
        }
      };
      if (file.delete) {
        edit.deleteFile(uri, { ignoreIfNotExists: false });
        versions[file.file] = null;
      } else if (file.create) {
        edit.createFile(uri, { ignoreIfExists: false, overwrite: false });
        replace(uri);
        written.push([file.file, uri]);
      } else if (target && file.renameTo) {
        // 改名してから、新しい名前のファイルに書き換えを当てる（範囲は改名の前の中身での位置で、中身は同じ）
        edit.renameFile(uri, target, { overwrite: false });
        replace(target);
        versions[file.file] = null;
        written.push([file.renameTo, target]);
      } else {
        replace(uri);
        written.push([file.file, uri]);
      }
    }
    if (!(await vscode.workspace.applyEdit(edit))) throw new Error('書き換えを当てられませんでした');
    for (const [file, uri] of written) {
      const document = await vscode.workspace.openTextDocument(uri);
      if (document.isDirty && !(await document.save())) throw new Error(`${file} を保存できませんでした`);
      // 保存時の整形のあとの、ディスクのバイト列の版（6.2 の 4 と同じ）
      versions[file] = await readVersion(uri);
    }
    return versions;
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
    // ホットエグジットから戻して読めるのを待っている間は、戻したバックアップの基準（変更を作ったときの版と値）を受け継ぐ
    const backup: Backup = this.waitingBackup
      ? { version: 1, dir: this.dir, files: this.waitingBackup.files, changes, ...(this.waitingBackup.saved ? { saved: this.waitingBackup.saved } : {}) }
      : {
          version: 1,
          dir: this.dir,
          files: base.files,
          changes,
          saved: Object.fromEntries(
            changes
              .filter((change) => !isSequential(change))
              .map((change) => [valueKey(change.address, fieldOf(change)), snapshotValueAt(base, change.address, fieldOf(change)) ?? null]),
          ),
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
    // 当てる順の並びをそのまま戻す（バックアップのときに畳んである。形の違うものは捨てる）
    this.changes.restore(backup.changes.filter(isAnyChange));
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
      this.ask({ snapshot, reason: 'backup', before: backupBefore(snapshot, backup.files, backup.saved), beforeFiles: backup.files });
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

  /**
   * 「画面の変更を残す」: Change を新しい snapshot に当て直す（7.3）。
   * 並びを指す Change のあるファイルが外で変わっていれば、そのファイルの Change はまとめて当て直せないものとして見せる（12.3）
   */
  private async keepScreen(change: ExternalChange): Promise<void> {
    const prompts = this.env.prompts();
    const generation = this.revertGeneration;
    const target = change.snapshot;
    const base = this.snapshotValue;
    const before: ValueBefore = change.before ?? ((address, field) => snapshotValueAt(base, address, field));
    const beforeFiles = change.beforeFiles ?? base.files;
    const original = this.changes.current();
    const { kept, conflicts, lost } = rebaseChanges(original, before, target, beforeFiles);
    const result = [...kept];
    if (conflicts.length > 0) {
      const chosen = await prompts.resolveConflicts(
        target.name,
        conflicts.map((conflict) => ({
          label: this.describePlace(target, conflict.change),
          screen: conflict.change.op === 'remove' ? describeChange(conflict.change) : describeValue(screenValue(conflict.change)),
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
      // 閉じたときは捨てずに残す（画面には出さず、保存のときにもう一度聞く）
      if (answer !== 'discard') {
        for (const c of lost) this.lostChanges.add(c);
        result.push(...lost);
      }
    }
    // 聞いている間の画面の操作を活かす: 足したもの（変えた値は新しい Change になる）は残し、undo などで外したものは当て直さない
    const now = this.changes.current();
    const originalSet = new Set(original);
    const nowSet = new Set(now);
    const added = now.filter((c) => !originalSet.has(c));
    // 聞いている間に足した並びの変更も、そのファイルが外で変わっていれば当て直せない（保存のときに聞く）
    const unrebaseable = unrebaseableFiles([...original, ...added], beforeFiles, target.files);
    for (const c of added) if (unrebaseable.has(c.address.file)) this.lostChanges.add(c);
    this.snapshotValue = target;
    this.epoch += 1;
    this.backupFiles = undefined;
    this.draftDiagnostics = undefined;
    this.changes.clear();
    for (const c of [...result.filter((c) => nowSet.has(c)), ...added]) {
      // 当て直せない変更と場所が見つからない変更は比べずに残す
      if (this.isLost(c)) this.changes.restore([...this.changes.current(), c]);
      else this.changes.add(c, this.savedValue);
    }
    if (this.changes.size === 0) {
      // 残る変更がない: revert を通して dirty を消す
      await this.keepExternal(target);
      return;
    }
    this.changed();
  }

  private lostItems(lost: readonly AnyChange[], snapshot: ProfileSnapshot) {
    return lost.map((c) => ({ label: this.describePlace(snapshot, c), value: describeChange(c) }));
  }

  /** 利用者に見せる Change の場所（注記なら「… の注記」） */
  private describePlace(snapshot: ProfileSnapshot, change: AnyChange): string {
    const place = describeAddress(snapshot, change.address);
    return fieldOf(change) === 'note' ? `${place} の注記` : place;
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
    // 読めるのを待っている・聞いている途中なら、版を比べずに外での変更の扱いに回す（基準は待っている・聞いているものが持つ。
    // 聞いている snapshot も新しいサーバーの profileId のものに差し替わる）
    const pending = this.waitingBackup !== undefined || this.changeBase !== undefined || this.external !== undefined || this.resolving !== undefined;
    if (this.changes.size > 0 && (pending || fresh.status !== 'ok' || changedFiles(this.changes.list(), base.files, fresh.files).length > 0)) {
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

/**
 * 開いている TextDocument の中身の版（BOM はディスクの先頭にあれば補う）。開いていなければディスクの版。
 * 書き換えは TextDocument に当たるので、当てる直前にこれが baseVersion と同じかを確かめる
 */
async function textVersion(uri: vscode.Uri): Promise<FileVersion> {
  const document = vscode.workspace.textDocuments.find((d) => d.uri.toString() === uri.toString());
  if (!document) return readVersion(uri);
  let disk: Uint8Array;
  try {
    disk = await vscode.workspace.fs.readFile(uri);
  } catch {
    return null;
  }
  const bom = disk[0] === 0xef && disk[1] === 0xbb && disk[2] === 0xbf ? new Uint8Array([0xef, 0xbb, 0xbf]) : new Uint8Array();
  const text = new TextEncoder().encode(document.getText());
  const bytes = new Uint8Array(bom.length + text.length);
  bytes.set(bom);
  bytes.set(text, bom.length);
  return fileVersionOf(bytes);
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
