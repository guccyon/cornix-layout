// 実機の操作（比べる・反映・戻す。tasks-v0.4.md の決めたこと 3〜7）で利用者に見せる文。vscode に依存しない（単体テストのため）。
import {
  DeviceErrorCodes,
  type DeviceApplyResult,
  type DeviceBackup,
  type DeviceBackupKind,
  type DeviceErrorData,
  type DevicePlan,
  type DeviceProgressParams,
  type DeviceUnavailableReason,
} from '../deviceProtocol';
import type { DeviceAction, DeviceViewState } from '../webviewMessages';

/** 知らせに付けるボタン（押すと VS Code のコマンドを動かす） */
export type NoticeAction = { label: string; command: string; args?: unknown[] };

/** 通知 1 つ */
export type Notice = { level: 'info' | 'warning' | 'error'; message: string; actions: NoticeAction[] };

export const COMMANDS: Record<DeviceAction, string> = {
  compare: 'cornix.device.compare',
  apply: 'cornix.device.apply',
  restore: 'cornix.device.restore',
};

export const ACTION_NAMES: Record<DeviceAction, string> = { compare: '比べる', apply: '反映', restore: '戻す' };

const OPEN_WRITE_SETTING: NoticeAction = { label: '設定を開く', command: 'workbench.action.openSettings', args: ['cornix.device.allowWrites'] };
const SHOW_OUTPUT: NoticeAction = { label: '出力を表示', command: 'cornix.showOutput' };
const SHOW_PROBLEMS: NoticeAction = { label: '問題を表示', command: 'workbench.actions.view.problems' };

function retry(action: DeviceAction, dir: string): NoticeAction {
  return { label: 'もう一度', command: COMMANDS[action], args: [dir] };
}

function compareAgain(dir: string): NoticeAction {
  return { label: '比べる', command: COMMANDS.compare, args: [dir] };
}

// ---------------------------------------------------------------------------
// 状態の印（状態バー）
// ---------------------------------------------------------------------------

/** 「実機: 同じ／違う N 件／未確認」（操作の最中はそれを出す） */
export function statusText(state: DeviceViewState): string {
  if (state.busy) return `実機: ${BUSY_TEXT[state.busy]}…`;
  switch (state.status) {
    case 'same':
      return '実機: 同じ';
    case 'different':
      return `実機: 違う ${state.changes.length} 件`;
    case 'unknown':
      return '実機: 未確認';
  }
}

const BUSY_TEXT: Record<DeviceAction, string> = { compare: '比べています', apply: '反映しています', restore: '戻しています' };

export function statusTooltip(state: DeviceViewState): string {
  const lines = [
    state.status === 'unknown'
      ? 'まだ実機と比べていないか、保存したあとです。押すと実機を読んで比べます（読むだけ）。'
      : '押すと実機をもう一度読んで比べます（読むだけ）。',
  ];
  if (!state.allowWrites) lines.push('書き込みは設定 cornix.device.allowWrites で許したときだけできます。');
  return lines.join('\n');
}

// ---------------------------------------------------------------------------
// 進み具合（device/progress。14.6）
// ---------------------------------------------------------------------------

const PHASE_TEXT: Record<DeviceProgressParams['phase'], string> = {
  read: '実機を読んでいます',
  write: '書き込んでいます',
  verify: '読み直して確かめています',
};

export function progressMessage(progress: DeviceProgressParams): string {
  const count = `${PHASE_TEXT[progress.phase]}（${progress.done}/${progress.total}）`;
  return progress.phase === 'write' ? `${count}。書き始めたら取り消せません` : count;
}

// ---------------------------------------------------------------------------
// 確認のダイアログ（件数・警告・keyboard.name。「次から聞かない」は付けない）
// ---------------------------------------------------------------------------

/** 確認のダイアログの detail に並べる違いの行の上限（多いと画面からはみ出す。全部は画面の「実機との差分」に出る） */
export const MAX_DETAIL_LINES = 15;

export type ConfirmText = { message: string; detail: string; button: string };

export function confirmApplyText(plan: DevicePlan, profile: string): ConfirmText {
  return {
    message: `実機（${plan.keyboard.name}）に、プロファイル ${profile} との違い ${plan.changes.length} 件を書き込みます。`,
    detail: confirmDetail(plan, '書く前に今の実機の状態をバックアップし、書いたあと読み直して確かめます。'),
    button: `${plan.changes.length} 件を書き込む`,
  };
}

export function confirmRestoreText(plan: DevicePlan, backup: DeviceBackup): ConfirmText {
  return {
    message: `実機（${plan.keyboard.name}）を、バックアップ ${backupLabel(backup)}（${BACKUP_KIND_NAMES[backup.kind]}）に戻します。${plan.changes.length} 件を書き込みます。`,
    detail: confirmDetail(plan, '戻す前にも今の実機の状態をバックアップします（続けてそれを選んで戻すと、戻す前に戻せます）。'),
    button: `${plan.changes.length} 件を書き込んで戻す`,
  };
}

function confirmDetail(plan: DevicePlan, note: string): string {
  const lines = plan.changes.slice(0, MAX_DETAIL_LINES).map((change) => change.text);
  const rest = plan.changes.length - lines.length;
  if (rest > 0) lines.push(`ほか ${rest} 件`);
  const sections = [lines.join('\n')];
  if (plan.warnings.length > 0) sections.push(['注意:', ...plan.warnings.map((warning) => `・${warning}`)].join('\n'));
  sections.push(note);
  return sections.join('\n\n');
}

// ---------------------------------------------------------------------------
// バックアップの選択（QuickPick。既定は最新）
// ---------------------------------------------------------------------------

export const BACKUP_KIND_NAMES: Record<DeviceBackupKind, string> = {
  'pre-apply': '反映の前',
  'pre-restore': '戻す前',
  backup: 'バックアップ',
  legacy: '前の版のバックアップ',
};

/** 日時（createdAt の時差の前の部分。サーバーの時刻のまま）。読めなければ名前 */
export function backupLabel(backup: DeviceBackup): string {
  const match = /^(\d{4}-\d{2}-\d{2})T(\d{2}:\d{2}(?::\d{2})?)/.exec(backup.createdAt);
  return match ? `${match[1]} ${match[2]}` : backup.name;
}

export type BackupPickItem = { label: string; description: string; detail: string; backup: DeviceBackup };

/** 新しい順（device/backups の並びのまま）。先頭を既定にする */
export function backupPickItems(backups: readonly DeviceBackup[]): BackupPickItem[] {
  return backups.map((backup, index) => ({
    label: backupLabel(backup),
    description: index === 0 ? `${BACKUP_KIND_NAMES[backup.kind]}・最新` : BACKUP_KIND_NAMES[backup.kind],
    detail: backup.name,
    backup,
  }));
}

// ---------------------------------------------------------------------------
// 結果
// ---------------------------------------------------------------------------

export function sameNotice(plan: Pick<DevicePlan, 'keyboard'>, what = 'このプロファイル'): Notice {
  return { level: 'info', message: `実機（${plan.keyboard.name}）は${what}と同じです。`, actions: [] };
}

export function differentNotice(plan: DevicePlan, dir: string, allowWrites: boolean): Notice {
  const actions: NoticeAction[] = allowWrites ? [{ label: '反映…', command: COMMANDS.apply, args: [dir] }] : [];
  return { level: 'info', message: `実機（${plan.keyboard.name}）とこのプロファイルは ${plan.changes.length} 件違います。`, actions };
}

/** 反映・戻すの結果（14.4。remaining があれば警告にする） */
export function writeResultNotice(result: DeviceApplyResult, action: 'apply' | 'restore', dir: string, backup?: DeviceBackup): Notice {
  const backupText = result.backup ? `（バックアップ: ${result.backup}）` : '';
  const done =
    action === 'apply'
      ? `${result.applied} 件を書き込みました${backupText}。`
      : `${result.applied} 件を書き込んで、バックアップ ${backup ? backupLabel(backup) : ''} に戻しました${backupText}。`;
  if (result.remaining.length === 0) return { level: 'info', message: done, actions: [] };
  return {
    level: 'warning',
    message: `${done}ただし、読み直すと ${result.remaining.length} 件が違ったままです（${result.remaining[0]?.text ?? ''}${result.remaining.length > 1 ? ' など' : ''}）。もう一度比べて確かめてください。`,
    actions: [compareAgain(dir)],
  };
}

// ---------------------------------------------------------------------------
// 書き込みを許していない（ADR 019）
// ---------------------------------------------------------------------------

export function writesDisabledNotice(action: 'apply' | 'restore'): Notice {
  return {
    level: 'warning',
    message: `実機に${action === 'apply' ? '反映' : '戻す'}には、設定 cornix.device.allowWrites を有効にしてください（既定は無効。比べるのはいつでもできます）。`,
    actions: [OPEN_WRITE_SETTING],
  };
}

// ---------------------------------------------------------------------------
// エラー（14.7）
// ---------------------------------------------------------------------------

type RpcErrorLike = { code?: unknown; message?: unknown; data?: unknown };

/** 結果の分類（状態をどうするかに使う） */
export type DeviceFailure = {
  notice: Notice | undefined;
  /** 実機の状態が分からなくなった（途中で切れた・比べたあとで変わった）。印を「未確認」に戻す */
  resetState: boolean;
};

const UNAVAILABLE_TEXT: Record<DeviceUnavailableReason, string> = {
  platform: '実機の操作は macOS でだけ使えます（キーボードとの通信に macOS の IOKit を使うため）。Mac で開いて試してください。',
  bridge:
    'キーボードと通信するブリッジ（tmp/cornix-hid）を用意できませんでした。初めて使うときに ext/cornix_hid/main.swift を swiftc でビルドします。' +
    'Xcode Command Line Tools を入れて（xcode-select --install）からもう一度試してください。手でビルドするなら、リポジトリで swiftc -O ext/cornix_hid/main.swift -o tmp/cornix-hid。',
  notConnected: 'キーボードが見つかりません。Cornix を USB か Bluetooth でつないでから、もう一度試してください。',
  timeout: 'キーボードが応答しません（Bluetooth が切れたか、スリープしているかもしれません）。キーを押して起こすか、つなぎ直してから、もう一度試してください。',
};

/**
 * device/* の失敗を知らせの文にする。action は押した操作（「もう一度」に使う）。
 * 取り消し（-32800）と、知らせ済みのエラー（cornix が見つからないなど。name が CornixUnavailableError）は知らせない
 */
export function deviceFailure(error: unknown, action: DeviceAction, dir: string): DeviceFailure {
  if (error instanceof Error && error.name === 'CornixUnavailableError') return { notice: undefined, resetState: false };
  const { code, message, data } = (typeof error === 'object' && error !== null ? error : {}) as RpcErrorLike;
  const text = typeof message === 'string' ? message : String(error);
  const writing = action === 'apply' ? '反映' : '戻す';
  switch (code) {
    case DeviceErrorCodes.RequestCancelled:
      return { notice: undefined, resetState: false };
    case DeviceErrorCodes.DeviceUnavailable: {
      const reason = (data as Partial<DeviceErrorData['DeviceUnavailable']> | undefined)?.reason;
      const body = reason && reason in UNAVAILABLE_TEXT ? UNAVAILABLE_TEXT[reason] : `実機が使えません（${text}）。`;
      const actions =
        reason === 'notConnected' || reason === 'timeout' ? [retry(action, dir)] : reason === 'bridge' ? [SHOW_OUTPUT] : [];
      return { notice: { level: 'error', message: body, actions }, resetState: false };
    }
    case DeviceErrorCodes.PlanChanged:
      return {
        notice: {
          level: 'warning',
          message: '比べたあとで設定ファイルか実機が変わったので、何も書き込みませんでした。もう一度比べてから操作してください。',
          actions: [compareAgain(dir)],
        },
        resetState: true,
      };
    case DeviceErrorCodes.WriteIncomplete: {
      const detail = (data ?? {}) as Partial<DeviceErrorData['WriteIncomplete']>;
      const backup = detail.backup ? `書く前の状態はバックアップ ${detail.backup} にあります。` : '';
      return {
        notice: {
          level: 'error',
          message: `${detail.applied ?? 0} 件を書いたところで止まりました（${text}）。${backup}つなぎ直してもう一度${writing}と、続きからそろいます。`,
          actions: [retry(action, dir)],
        },
        resetState: true,
      };
    }
    case DeviceErrorCodes.PlanRejected: {
      const keycodes = (data as Partial<DeviceErrorData['PlanRejected']> | undefined)?.keycodes ?? [];
      const list = keycodes.length > 0 ? keycodes.join('、') : '書き込めないキーコード';
      return {
        notice: {
          level: 'error',
          message: `${list} は安全のため実機に書き込めないので、${action === 'compare' ? '比べる' : writing}のをやめました。プロファイル（かバックアップ）から外してください。`,
          actions: [],
        },
        resetState: false,
      };
    }
    case DeviceErrorCodes.WritesNotAllowed:
      return {
        notice: {
          level: 'warning',
          message: '実機のサーバーが書き込みを許さずに起動しています。設定 cornix.device.allowWrites を有効にしてから、もう一度試してください。',
          actions: [OPEN_WRITE_SETTING],
        },
        resetState: false,
      };
    case DeviceErrorCodes.CompileFailed: {
      const diagnostics = (data as Partial<DeviceErrorData['CompileFailed']> | undefined)?.diagnostics ?? [];
      const first = diagnostics.find((diagnostic) => diagnostic.severity === 'error') ?? diagnostics[0];
      const where = first ? `（${first.file ? `${first.file}: ` : ''}${first.message}）` : `（${text}）`;
      return {
        notice: {
          level: 'error',
          message: `プロファイルに検証のエラーがあるので compile できず、実機を読みませんでした${where}。エラーを直して保存してから、もう一度試してください。`,
          actions: [SHOW_PROBLEMS],
        },
        resetState: false,
      };
    }
    default:
      return {
        notice: { level: 'error', message: `実機の操作（${ACTION_NAMES[action]}）に失敗しました: ${text}`, actions: [SHOW_OUTPUT] },
        resetState: action !== 'compare',
      };
  }
}


/** Webview から来たものが DeviceAction か */
export function isDeviceAction(value: unknown): value is DeviceAction {
  return value === 'compare' || value === 'apply' || value === 'restore';
}
