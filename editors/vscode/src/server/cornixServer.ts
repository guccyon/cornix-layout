// `cornix serve --root <ワークスペース>` を子プロセスとして起動し、つなぎ、落ちたら知らせて再起動できるようにする（protocol.md の 1.）。
// 最初にリクエストを送るときに起動する。標準エラー出力は出力パネル「Cornix」に流す。
import { spawn, type ChildProcess } from 'node:child_process';
import * as vscode from 'vscode';
import type {
  ClientNotificationMap,
  ClientNotificationMethod,
  RequestMap,
  RequestMethod,
  ServerNotificationMap,
  ServerNotificationMethod,
} from '../protocol';
import { CornixConnection, type TraceLevel } from './connection';
import { locateCornix } from './locateCornix';

const CLIENT_NAME = 'cornix-vscode';

/** サーバーから来る通知（protocol.md の 3.）。onNotification はつなぐ前でも後でも登録できる */
const SERVER_NOTIFICATIONS: readonly ServerNotificationMethod[] = ['profile/didChange'];

/** cornix が見つからない・起動できないなど、利用者に知らせ済みのエラー */
export class CornixUnavailableError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'CornixUnavailableError';
  }
}

type Running = { process: ChildProcess; connection: CornixConnection };

type NotificationHandlers = {
  [M in ServerNotificationMethod]?: Set<(params: ServerNotificationMap[M]) => void>;
};

export class CornixServer implements vscode.Disposable {
  private starting: Promise<Running> | undefined;
  private running: Running | undefined;
  private generation = 0;
  private disposed = false;
  private readonly handlers: NotificationHandlers = {};
  private readonly onDidRestartEmitter = new vscode.EventEmitter<void>();
  private readonly onDidStopEmitter = new vscode.EventEmitter<void>();

  /** 再起動してつながった（開いていたプロファイルは profile/open からやり直す） */
  readonly onDidRestart = this.onDidRestartEmitter.event;
  /** サーバーが止まった（落ちた・止めた） */
  readonly onDidStop = this.onDidStopEmitter.event;

  constructor(
    private readonly output: vscode.OutputChannel,
    private readonly clientVersion: string,
  ) {}

  get isRunning(): boolean {
    return this.running !== undefined;
  }

  /** 動いているか、起動の途中（設定が変わったときに起動し直すかどうかに使う） */
  get isStartingOrRunning(): boolean {
    return this.running !== undefined || this.starting !== undefined;
  }

  async request<M extends RequestMethod>(method: M, params: RequestMap[M]['params']): Promise<RequestMap[M]['result']> {
    const { connection } = await this.ensureStarted();
    return connection.request(method, params);
  }

  /** 動いていなければ送らない（profile/close などは、サーバーが止まっていれば意味がない） */
  notify<M extends ClientNotificationMethod>(method: M, params: ClientNotificationMap[M]): void {
    this.running?.connection.notify(method, params).catch((error: unknown) => this.log(`${method} を送れませんでした: ${String(error)}`));
  }

  onNotification<M extends ServerNotificationMethod>(
    method: M,
    handler: (params: ServerNotificationMap[M]) => void,
  ): vscode.Disposable {
    const set = (this.handlers[method] ??= new Set()) as Set<(params: ServerNotificationMap[M]) => void>;
    set.add(handler);
    return new vscode.Disposable(() => set.delete(handler));
  }

  async restart(): Promise<void> {
    await this.stop();
    await this.ensureStarted();
  }

  async stop(): Promise<void> {
    const starting = this.starting;
    this.starting = undefined;
    const running = this.running ?? (await starting?.catch(() => undefined));
    this.running = undefined;
    if (!running) return;
    this.log('サーバーを止めます');
    running.process.removeAllListeners('exit');
    const exited = waitForExit(running.process, EXIT_GRACE_MS);
    await running.connection.shutdown();
    // exit を受けたサーバーが自分で終わるのを少し待ち（終わりぎわのログを出力パネルに残すため）、終わらなければ止める
    if (!(await exited)) running.process.kill();
    this.onDidStopEmitter.fire();
  }

  dispose(): void {
    this.disposed = true;
    void this.stop();
    this.onDidRestartEmitter.dispose();
    this.onDidStopEmitter.dispose();
  }

  private ensureStarted(): Promise<Running> {
    if (this.running) return Promise.resolve(this.running);
    if (this.disposed) return Promise.reject(new CornixUnavailableError('拡張が止まっています'));
    this.starting ??= this.start().finally(() => {
      this.starting = undefined;
    });
    return this.starting;
  }

  private async start(): Promise<Running> {
    const root = vscode.workspace.workspaceFolders?.[0]?.uri;
    if (!root || root.scheme !== 'file') {
      throw this.unavailable('Cornix を使うには、cornix-layout のフォルダをワークスペースとして開いてください。');
    }
    const config = vscode.workspace.getConfiguration('cornix', root);
    const located = locateCornix({
      configured: config.get<string>('path'),
      workspaceRoot: root.fsPath,
      envPath: process.env.PATH,
    });
    if (!located.found) throw this.unavailable(located.message, true);

    const { command } = located.location;
    const args = ['serve', '--root', root.fsPath];
    this.log(`起動します: ${command} ${args.join(' ')}`);

    const child = spawn(command, args, { cwd: root.fsPath, stdio: ['pipe', 'pipe', 'pipe'], env: process.env });
    child.stderr.setEncoding('utf-8');
    child.stderr.on('data', (chunk: string) => this.output.append(chunk));
    // 落ちたあとに書こうとしたとき（EPIPE）などで拡張ごと止まらないように、エラーは記録だけする
    child.stdin.on('error', (error) => this.log(`サーバーに書けませんでした: ${error.message}`));
    child.on('error', (error) => this.log(`サーバーのプロセスのエラー: ${error.message}`));

    const exited = new Promise<never>((_, reject) => {
      child.once('error', (error) => reject(error));
      child.once('exit', (code, signal) => reject(new Error(exitText(code, signal))));
    });

    let connection: CornixConnection;
    try {
      connection = await Promise.race([
        CornixConnection.connect(
          { input: child.stdout, output: child.stdin },
          {
            clientName: CLIENT_NAME,
            clientVersion: this.clientVersion,
            trace: config.get<TraceLevel>('trace.server', 'off'),
            log: (line) => this.output.appendLine(line),
          },
        ),
        exited,
      ]);
    } catch (error) {
      if (child.exitCode === null) child.kill();
      const reason = error instanceof Error ? error.message : String(error);
      throw this.unavailable(`cornix のサーバーを起動できませんでした（${reason}）。出力パネル「Cornix」を見てください。`, true);
    }
    exited.catch(() => undefined);

    const running: Running = { process: child, connection };
    const { serverInfo } = connection.initializeResult;
    this.log(`つながりました: ${serverInfo.name} ${serverInfo.version}（${serverInfo.implementation}）`);

    for (const method of SERVER_NOTIFICATIONS) {
      connection.onNotification(method, (params) => {
        for (const handler of this.handlers[method] ?? []) handler(params);
      });
    }
    child.on('exit', (code, signal) => this.handleExit(running, code, signal));

    this.running = running;
    this.generation += 1;
    if (this.generation > 1) this.onDidRestartEmitter.fire();
    return running;
  }

  private handleExit(running: Running, code: number | null, signal: NodeJS.Signals | null): void {
    if (this.running !== running) return;
    this.running = undefined;
    running.connection.dispose();
    this.log(`サーバーが止まりました（${exitText(code, signal)}）`);
    this.onDidStopEmitter.fire();
    if (this.disposed) return;
    void vscode.window
      .showErrorMessage(`Cornix のサーバーが止まりました（${exitText(code, signal)}）。`, '再起動', '出力を表示')
      .then((choice) => {
        if (choice === '再起動') void this.ensureStarted().catch(() => undefined);
        if (choice === '出力を表示') this.output.show(true);
      });
  }

  private unavailable(message: string, offerSettings = false): CornixUnavailableError {
    this.log(message);
    const buttons = offerSettings ? ['設定を開く', '出力を表示'] : ['出力を表示'];
    void vscode.window.showErrorMessage(message, ...buttons).then((choice) => {
      if (choice === '設定を開く') void vscode.commands.executeCommand('workbench.action.openSettings', 'cornix.path');
      if (choice === '出力を表示') this.output.show(true);
    });
    return new CornixUnavailableError(message);
  }

  private log(message: string): void {
    this.output.appendLine(`[拡張] ${message}`);
  }
}

/** shutdown / exit を送ってからプロセスが終わるのを待つ時間 */
const EXIT_GRACE_MS = 1000;

/** プロセスが終われば true、ms のうちに終わらなければ false */
function waitForExit(child: ChildProcess, ms: number): Promise<boolean> {
  if (child.exitCode !== null || child.signalCode !== null) return Promise.resolve(true);
  return new Promise((resolve) => {
    const timer = setTimeout(() => resolve(false), ms);
    child.once('exit', () => {
      clearTimeout(timer);
      resolve(true);
    });
  });
}

function exitText(code: number | null, signal: NodeJS.Signals | null): string {
  return signal ? `シグナル ${signal}` : `終了コード ${code ?? '不明'}`;
}
