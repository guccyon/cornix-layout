// 保存と外での変更（protocol.md の 6.2・7.3）で利用者に聞くこと・知らせること。
// 統合テストは通知のボタンを押せないので、ProfileEditorProvider#prompts を差し替えて答える。
import * as vscode from 'vscode';

export type KeepChoice = 'screen' | 'external';

/** 項目ごとに選ばせる 1 件（label は場所の名前、screen と external は値の見せ方） */
export type ConflictItem = { label: string; screen: string; external: string };
export type LostItem = { label: string; value: string };

export interface ProfilePrompts {
  /**
   * 外でファイルが変わり、未保存の変更がある。どちらを残すか。
   * reason は、開いている間に変わった（external）か、ホットエグジットから戻したら変わっていた（backup）か。閉じたら undefined
   */
  chooseSide(profile: string, pending: number, reason: 'external' | 'backup'): Thenable<KeepChoice | undefined>;
  /** 同じ場所が外でも変わった。画面の値を残す項目の添字を返す（閉じたら undefined） */
  resolveConflicts(profile: string, items: ConflictItem[]): Thenable<number[] | undefined>;
  /** 当て直せない変更（場所がなくなった）。捨てて続けるか、外の変更を残す（画面の変更をすべて捨てる）か（閉じたら undefined） */
  confirmLost(profile: string, items: LostItem[]): Thenable<'discard' | 'external' | undefined>;
  /** 保存できなかった。openFile があれば「ファイルを開く」のボタンを付け、押されたら呼ぶ */
  saveFailed(message: string, openFile?: () => void): void;
}

export const KEEP_SCREEN = '画面の変更を残す';
export const KEEP_EXTERNAL = '外の変更を残す';

export const vscodePrompts: ProfilePrompts = {
  async chooseSide(profile, pending, reason) {
    const what =
      reason === 'backup'
        ? `プロファイル ${profile} の未保存の変更（${pending} 件）を戻しましたが、閉じている間に設定ファイルが変わっていました。`
        : `プロファイル ${profile} の設定ファイルが外で変わりました。画面には未保存の変更が ${pending} 件あります。`;
    const choice = await vscode.window.showWarningMessage(
      `${what}どちらを残しますか？（画面の変更を残すと、外の変更のうち同じ場所でないものも取り込みます）`,
      KEEP_SCREEN,
      KEEP_EXTERNAL,
    );
    if (choice === KEEP_SCREEN) return 'screen';
    if (choice === KEEP_EXTERNAL) return 'external';
    return undefined;
  },

  async resolveConflicts(profile, items) {
    const picks = items.map((item, index) => ({
      label: item.label,
      description: `画面: ${item.screen}　／　外: ${item.external}`,
      picked: true,
      index,
    }));
    const chosen = await vscode.window.showQuickPick(picks, {
      canPickMany: true,
      ignoreFocusOut: true,
      title: `${profile}: 同じ場所が外でも変わりました`,
      placeHolder: '画面の値を残す項目に印を付けてください（印のない項目は外の値になります）',
    });
    return chosen?.map((pick) => pick.index);
  },

  async confirmLost(profile, items) {
    const discard = '捨てて続ける';
    const external = '外の変更を残す（画面の変更をすべて捨てる）';
    const choice = await vscode.window.showWarningMessage(
      `${profile}: 次の未保存の変更は、場所が見つからないので当て直せません。`,
      { modal: true, detail: items.map((item) => `${item.label}: ${item.value}`).join('\n') },
      discard,
      external,
    );
    if (choice === discard) return 'discard';
    if (choice === external) return 'external';
    return undefined;
  },

  saveFailed(message, openFile) {
    const open = 'ファイルを開く';
    const buttons = openFile ? [open] : [];
    void vscode.window.showErrorMessage(message, ...buttons).then((choice) => {
      if (choice === open) openFile?.();
    });
  },
};
