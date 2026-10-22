// 実機の操作（v0.4。tasks-v0.4.md の D2）の VS Code の部分: device のサーバー・コマンド・状態バー・確認のダイアログ・進み具合・設定。
// 流れそのものは deviceFlow.ts、文は deviceTexts.ts、状態は deviceStates.ts（どれも vscode に依存しない）。
import * as path from 'node:path';
import * as vscode from 'vscode';
import type { ProfileDocument } from '../editor/profileDocument';
import type { ProfileEditorProvider } from '../editor/profileEditorProvider';
import { profileDirOf } from '../editor/profileUri';
import { pickProfile } from '../profiles/openProfile';
import type { CornixServer } from '../server/cornixServer';
import { DeviceServer } from '../server/deviceServer';
import { ALLOW_WRITES_SETTING } from './deviceSettings';
import type { DeviceAction } from '../webviewMessages';
import { DeviceFlow, type DeviceClient, type DeviceHost, type DeviceOutcome, type DevicePrompts, type ProgressTask } from './deviceFlow';
import { DeviceStates, filesKey } from './deviceStates';
import { ACTION_NAMES, COMMANDS, statusText, statusTooltip, type Notice } from './deviceTexts';

export const vscodeDevicePrompts: DevicePrompts = {
  async confirmSaveFirst(profile, pending) {
    const save = '保存して続ける';
    const choice = await vscode.window.showWarningMessage(
      `${profile}: 未保存の変更が ${pending} 件あります。`,
      { modal: true, detail: '実機と比べるのは保存済みの設定ファイルなので、先に未保存の変更を保存します。' },
      save,
    );
    return choice === save;
  },

  async confirmWrite(text) {
    const choice = await vscode.window.showWarningMessage(text.message, { modal: true, detail: text.detail }, text.button);
    return choice === text.button;
  },

  async pickBackup(items) {
    const chosen = await vscode.window.showQuickPick(items, {
      title: 'Cornix: 実機をバックアップから戻す',
      placeHolder: '戻す先のバックアップを選んでください（新しい順）',
      ignoreFocusOut: true,
    });
    return chosen?.backup;
  },

  notify(notice) {
    showNotice(notice);
  },
};

function showNotice(notice: Notice): void {
  const show =
    notice.level === 'error'
      ? vscode.window.showErrorMessage
      : notice.level === 'warning'
        ? vscode.window.showWarningMessage
        : vscode.window.showInformationMessage;
  void show(notice.message, ...notice.actions.map((action) => action.label)).then((label) => {
    const action = notice.actions.find((candidate) => candidate.label === label);
    if (action) void vscode.commands.executeCommand(action.command, ...(action.args ?? []));
  });
}

function readAllowWrites(): boolean {
  return vscode.workspace.getConfiguration().get<boolean>(ALLOW_WRITES_SETTING, false) === true;
}

export class DeviceController implements vscode.Disposable {
  readonly server: DeviceServer;
  readonly states: DeviceStates;
  readonly flow: DeviceFlow;
  /** 聞くこと・知らせること（統合テストが差し替える） */
  prompts: DevicePrompts = vscodeDevicePrompts;

  private readonly onDidChangeStateEmitter = new vscode.EventEmitter<string | undefined>();
  readonly onDidChangeState = this.onDidChangeStateEmitter.event;
  private readonly statusBar: vscode.StatusBarItem;
  private readonly disposables: vscode.Disposable[] = [];
  /** 操作の最中に設定が変わった（終わってから起動し直す） */
  private restartPending = false;

  constructor(
    output: vscode.OutputChannel,
    clientVersion: string,
    private readonly editorServer: CornixServer,
    private readonly provider: ProfileEditorProvider,
  ) {
    this.server = new DeviceServer(output, clientVersion);
    this.states = new DeviceStates(readAllowWrites(), (dir) => {
      this.onDidChangeStateEmitter.fire(dir);
      this.updateStatusBar();
    });

    const client: DeviceClient = {
      request: (method, params, token) => this.server.request(method, params, token),
      prepareWrites: async () => {
        // 設定は許しているのに、前の設定のまま --allow-writes なしで動いていれば起動し直す
        if (this.server.isStartingOrRunning && !(await this.server.writesAllowed())) await this.server.stop();
      },
    };
    const controller = this;
    const host: DeviceHost = {
      get prompts() {
        return controller.prompts;
      },
      ensureSaved: (dir) => this.ensureSaved(dir),
      filesKey: (dir) => {
        const document = this.documentOf(dir);
        return document ? filesKey(document.snapshot.files) : undefined;
      },
      profileName: (dir) => this.documentOf(dir)?.snapshot.name ?? path.basename(dir),
      withProgress: <T>(title: string, task: ProgressTask<T>) =>
        Promise.resolve(
          vscode.window.withProgress({ location: vscode.ProgressLocation.Notification, title, cancellable: true }, (progress, token) =>
            task((message) => progress.report({ message }), token),
          ),
        ),
    };
    this.flow = new DeviceFlow(client, host, this.states);

    this.statusBar = vscode.window.createStatusBarItem('cornix.device', vscode.StatusBarAlignment.Left, 50);
    this.statusBar.name = 'Cornix: 実機';

    provider.attachDevice({
      stateOf: (dir) => this.states.get(dir),
      onDidChangeState: this.onDidChangeState,
      run: (action, dir) => void this.run(action, dir),
    });

    this.disposables.push(
      this.server,
      this.statusBar,
      this.onDidChangeStateEmitter,
      this.server.onNotification('device/progress', (params) => this.flow.handleProgress(params)),
      // 保存・外での変更で設定ファイルの版が変わったら「未確認」に戻す（profile/saved のあとの snapshot もここに来る）
      provider.onDidChangeDocument((document) => this.states.checkFiles(document.dir, filesKey(document.snapshot.files))),
      provider.onDidCloseDocument((document) => {
        if (!this.provider.openDocuments.some((other) => other !== document && other.dir === document.dir)) this.states.forget(document.dir);
      }),
      vscode.window.tabGroups.onDidChangeTabs(() => this.updateStatusBar()),
      vscode.window.tabGroups.onDidChangeTabGroups(() => this.updateStatusBar()),
      vscode.workspace.onDidChangeConfiguration((event) => {
        if (event.affectsConfiguration(ALLOW_WRITES_SETTING)) this.states.setAllowWrites(readAllowWrites());
        if (['cornix.path', 'cornix.trace.server', ALLOW_WRITES_SETTING].some((name) => event.affectsConfiguration(name))) this.restartServer();
      }),
      ...(Object.keys(COMMANDS) as DeviceAction[]).map((action) =>
        vscode.commands.registerCommand(COMMANDS[action], (arg?: unknown) => this.command(action, arg)),
      ),
    );
    this.updateStatusBar();
  }

  /** 画面のボタン・コマンドから。対象のプロファイルは dir */
  async run(action: DeviceAction, dir: string): Promise<DeviceOutcome> {
    try {
      return await this.flow.run(action, dir);
    } finally {
      if (this.restartPending && !this.states.busy) {
        this.restartPending = false;
        this.restartServer();
      }
    }
  }

  /** コマンド。arg は dir（文字列）か、プロファイルの URI。なければアクティブな編集画面、それもなければ選ばせる */
  private async command(action: DeviceAction, arg: unknown): Promise<DeviceOutcome | undefined> {
    const dir = await this.targetDir(action, arg).catch(() => undefined);
    if (!dir) return undefined;
    return this.run(action, dir);
  }

  private async targetDir(action: DeviceAction, arg: unknown): Promise<string | undefined> {
    if (typeof arg === 'string' && arg !== '') return arg;
    if (arg instanceof vscode.Uri) return profileDirOf(arg);
    const active = activeProfileDir();
    if (active) return active;
    const picked = await pickProfile(this.editorServer, `Cornix: 実機と${ACTION_NAMES[action]}`, '対象のプロファイルを選んでください');
    return picked?.dir;
  }

  private documentOf(dir: string): ProfileDocument | undefined {
    return this.provider.openDocuments.find((document) => document.dir === dir);
  }

  /** 未保存の変更があれば保存を促す（保存しないなら止める。tasks-v0.4.md の決めたこと 3） */
  private async ensureSaved(dir: string): Promise<boolean> {
    const document = this.documentOf(dir);
    if (!document) return true;
    await document.settled();
    if (document.changes.size === 0) return true;
    if (!(await this.prompts.confirmSaveFirst(document.snapshot.name, document.changes.size))) return false;
    await document.saveWithVsCode();
    // 保存できなかった（理由は保存の流れが知らせている）
    return document.changes.size === 0;
  }

  /** 設定が変わった。操作の最中なら終わってから */
  private restartServer(): void {
    if (this.states.busy) {
      this.restartPending = true;
      return;
    }
    // 止めるだけにして、次の操作で新しい設定で起動する（cornix.path を誤ったときに、編集のサーバーと二重に知らせないため）
    if (this.server.isStartingOrRunning) void this.server.stop().catch(() => undefined);
  }

  private updateStatusBar(): void {
    const dir = activeProfileDir();
    if (!dir) {
      this.statusBar.hide();
      return;
    }
    const state = this.states.get(dir);
    this.statusBar.text = `${state.busy ? '$(sync~spin)' : '$(plug)'} ${statusText(state)}`;
    this.statusBar.tooltip = statusTooltip(state);
    this.statusBar.command = { title: '実機と比べる', command: COMMANDS.compare, arguments: [dir] };
    this.statusBar.backgroundColor =
      state.status === 'different' && !state.busy ? new vscode.ThemeColor('statusBarItem.warningBackground') : undefined;
    this.statusBar.show();
  }

  dispose(): void {
    for (const disposable of this.disposables) disposable.dispose();
  }
}

/** アクティブなタブがプロファイルの編集画面なら、その dir */
export function activeProfileDir(): string | undefined {
  const input = vscode.window.tabGroups.activeTabGroup.activeTab?.input;
  if (input instanceof vscode.TabInputCustom) return profileDirOf(input.uri);
  return undefined;
}
