// 実機への反映（プレビュー → 確定。tasks-v0.4.md の決めたこと 3〜7）で、VS Code の通知に出す文。vscode に依存しない（単体テストのため）。
// プレビューのモーダルの文は画面（webview/deviceView.ts）が持つ。
import { DeviceErrorCodes, type DeviceApplyResult, type DeviceErrorData, type DeviceUnavailableReason } from '../deviceProtocol';
import type { DeviceAction } from '../webviewMessages';

/** 知らせに付けるボタン（押すと VS Code のコマンドを動かす） */
export type NoticeAction = { label: string; command: string; args?: unknown[] };

/** 通知 1 つ */
export type Notice = { level: 'info' | 'warning' | 'error'; message: string; actions: NoticeAction[] };

/** コマンド「Cornix: 実機に反映…」（編集画面を開いてプレビューを出す） */
export const APPLY_COMMAND = 'cornix.device.apply';

/** 画面から来た操作のうち、失敗を知らせるもの（読む・書く） */
export type FailedStep = 'preview' | 'confirm';

export const OPEN_WRITE_SETTING: NoticeAction = { label: '設定を開く', command: 'workbench.action.openSettings', args: ['cornix.device.allowWrites'] };
const SHOW_OUTPUT: NoticeAction = { label: '出力を表示', command: 'cornix.showOutput' };
const SHOW_PROBLEMS: NoticeAction = { label: '問題を表示', command: 'workbench.actions.view.problems' };

/** 「もう一度」: プレビューからやり直す */
function previewAgain(dir: string, label = 'もう一度プレビュー'): NoticeAction {
  return { label, command: APPLY_COMMAND, args: [dir] };
}

// ---------------------------------------------------------------------------
// 結果
// ---------------------------------------------------------------------------

/** 反映の結果（14.4。remaining があれば警告にする） */
export function writeResultNotice(result: DeviceApplyResult, dir: string): Notice {
  const backupText = result.backup ? `（バックアップ: ${result.backup}）` : '';
  const done = result.applied === 0 ? '実機はすでにこのプロファイルと同じでした。' : `${result.applied} 件を書き込みました${backupText}。`;
  if (result.remaining.length === 0) return { level: 'info', message: done, actions: [] };
  return {
    level: 'warning',
    message: `${done}ただし、読み直すと ${result.remaining.length} 件が違ったままです（${result.remaining[0]?.text ?? ''}${result.remaining.length > 1 ? ' など' : ''}）。もう一度プレビューして確かめてください。`,
    actions: [previewAgain(dir)],
  };
}

// ---------------------------------------------------------------------------
// 書き込みを許していない（ADR 019）
// ---------------------------------------------------------------------------

export function writesDisabledNotice(): Notice {
  return {
    level: 'warning',
    message: '実機に書き込むには、設定 cornix.device.allowWrites を有効にしてください（既定は無効。プレビューはいつでもできます）。',
    actions: [OPEN_WRITE_SETTING],
  };
}

/** 検証のエラーがあるあいだは反映させない（実機を読む前と、確定のとき） */
export function validationErrorNotice(errors: number): Notice {
  return {
    level: 'warning',
    message: `プロファイルに検証のエラーが ${errors} 件あるので、実機に反映できません。先にエラーを直して保存してから、もう一度反映してください。`,
    actions: [SHOW_PROBLEMS],
  };
}

// ---------------------------------------------------------------------------
// エラー（14.7）
// ---------------------------------------------------------------------------

type RpcErrorLike = { code?: unknown; message?: unknown; data?: unknown };

/** 実機が使えない理由ごとの文。keyboard はキーボードの表示名（KeyboardSpec の displayName） */
const UNAVAILABLE_TEXT: Record<DeviceUnavailableReason, (keyboard: string) => string> = {
  platform: () => '実機の操作は macOS でだけ使えます（キーボードとの通信に macOS の IOKit を使うため）。Mac で開いて試してください。',
  bridge: () =>
    'キーボードと通信するブリッジ（tmp/cornix-hid）を用意できませんでした。初めて使うときに ext/cornix_hid/main.swift を swiftc でビルドします。' +
    'Xcode Command Line Tools を入れて（xcode-select --install）からもう一度試してください。手でビルドするなら、リポジトリで swiftc -O ext/cornix_hid/main.swift -o tmp/cornix-hid。',
  notConnected: (keyboard) => `キーボードが見つかりません。${keyboard} を USB か Bluetooth でつないでから、もう一度試してください。`,
  timeout: () => 'キーボードが応答しません（Bluetooth が切れたか、スリープしているかもしれません）。キーを押して起こすか、つなぎ直してから、もう一度試してください。',
};

/**
 * device/* の失敗を知らせの文にする。step は読んでいた（preview）か書いていた（confirm）か。
 * keyboard はキーボードの表示名（プロファイルの KeyboardSpec の displayName。「Cornix を USB か Bluetooth でつないで」など）。
 * 取り消し（-32800）と、知らせ済みのエラー（cornix が見つからないなど。name が CornixUnavailableError）は知らせない（undefined）
 */
export function deviceFailure(error: unknown, step: FailedStep, dir: string, keyboard: string): Notice | undefined {
  if (error instanceof Error && error.name === 'CornixUnavailableError') return undefined;
  const { code, message, data } = (typeof error === 'object' && error !== null ? error : {}) as RpcErrorLike;
  const text = typeof message === 'string' ? message : String(error);
  switch (code) {
    case DeviceErrorCodes.RequestCancelled:
      return undefined;
    case DeviceErrorCodes.DeviceUnavailable: {
      const reason = (data as Partial<DeviceErrorData['DeviceUnavailable']> | undefined)?.reason;
      const body = reason && reason in UNAVAILABLE_TEXT ? UNAVAILABLE_TEXT[reason](keyboard) : `実機が使えません（${text}）。`;
      const actions = reason === 'notConnected' || reason === 'timeout' ? [previewAgain(dir, 'もう一度')] : reason === 'bridge' ? [SHOW_OUTPUT] : [];
      return { level: 'error', message: body, actions };
    }
    case DeviceErrorCodes.PlanChanged:
      return {
        level: 'warning',
        message: 'プレビューのあとで設定ファイルか実機が変わったので、何も書き込みませんでした。もう一度プレビューしてから確定してください。',
        actions: [previewAgain(dir)],
      };
    case DeviceErrorCodes.WriteIncomplete: {
      const detail = (data ?? {}) as Partial<DeviceErrorData['WriteIncomplete']>;
      const backup = detail.backup ? `書く前の状態はバックアップ ${detail.backup} にあります。` : '';
      return {
        level: 'error',
        message: `${detail.applied ?? 0} 件を書いたところで止まりました（${text}）。${backup}つなぎ直してもう一度反映すると、続きからそろいます。`,
        actions: [previewAgain(dir)],
      };
    }
    case DeviceErrorCodes.PlanRejected: {
      const keycodes = (data as Partial<DeviceErrorData['PlanRejected']> | undefined)?.keycodes ?? [];
      const list = keycodes.length > 0 ? keycodes.join('、') : '書き込めないキーコード';
      return {
        level: 'error',
        message: `${list} は安全のため実機に書き込めないので、反映をやめました。プロファイルから外してください。`,
        actions: [],
      };
    }
    case DeviceErrorCodes.WritesNotAllowed:
      return {
        level: 'warning',
        message: '実機のサーバーが書き込みを許さずに起動しています。設定 cornix.device.allowWrites を有効にしてから、もう一度試してください。',
        actions: [OPEN_WRITE_SETTING],
      };
    case DeviceErrorCodes.CompileFailed: {
      const diagnostics = (data as Partial<DeviceErrorData['CompileFailed']> | undefined)?.diagnostics ?? [];
      const first = diagnostics.find((diagnostic) => diagnostic.severity === 'error') ?? diagnostics[0];
      const where = first ? `（${first.file ? `${first.file}: ` : ''}${first.message}）` : `（${text}）`;
      return {
        level: 'error',
        message: `プロファイルに検証のエラーがあるので compile できず、実機を読みませんでした${where}。エラーを直して保存してから、もう一度試してください。`,
        actions: [SHOW_PROBLEMS],
      };
    }
    default:
      return {
        level: 'error',
        message: `実機${step === 'preview' ? 'を読んで比べるの' : 'への書き込み'}に失敗しました: ${text}`,
        actions: [SHOW_OUTPUT],
      };
  }
}

/** Webview から来たものが DeviceAction か */
export function isDeviceAction(value: unknown): value is DeviceAction {
  return value === 'preview' || value === 'confirm' || value === 'cancel' || value === 'openSettings';
}
