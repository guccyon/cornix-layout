// `cornix serve ...` を子プロセスとして起動し、つなぎ、落ちたら知らせて再起動できるようにする（protocol.md の 1.）。
// 編集のサーバー（cornixServer.ts）と device のサーバー（deviceServer.ts。protocol.md の 14.1）で共通の部分。
// 最初にリクエストを送るときに起動する。標準エラー出力は出力パネル「Cornix」に流す。
import { spawn, type ChildProcess } from 'node:child_process';
import * as vscode from 'vscode';
import type { InitializeResult } from '../protocol';
import { CornixConnection, type RequestShape, type TraceLevel } from './connection';
import { locateCornix } from './locateCornix';

const CLIENT_NAME = 'cornix-vscode';

/** cornix が見つからない・起動できないなど、利用者に知らせ済みのエラー */
export class CornixUnavailableError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'CornixUnavailableError';
  }
}

export type ServerProcessOptions<N> = {
  /** 出力パネルと知らせに出す名前（「サーバー」「実機のサーバー」） */
  label: string;
  /** cornix serve に渡す引数（--root の後ろに足すもの）。起動のたびに呼ぶ（設定はそのときの値を使う） */
  extraArgs: (config: vscode.WorkspaceConfiguration) => string[];
  /** サーバーから来る通知。onNotification はつなぐ前でも後でも登録できる */
  notifications: readonly (keyof N & string)[];
  /** 動いている間に落ちたら、再起動のボタン付きで知らせる */
  notifyExit: boolean;
};

type Running<R extends RequestShape<R>, N, I extends InitializeResult> = { process: ChildProcess; connection: CornixConnection<R, N, I> };

export class ServerProcess<R extends RequestShape<R>, N, I extends InitializeResult> implements vscode.Disposable {
  private starting: Promise<Running<R, N, I>> | undefined;
  private running: Running<R, N, I> | undefined;
  private generation = 0;
  private disposed = false;
  private readonly handlers = new Map<string, Set<(params: never) => void>>();
  private readonly onDidRestartEmitter = new vscode.EventEmitter<void>();
  private readonly onDidStopEmitter = new vscode.EventEmitter<void>();

  /** 再起動してつながった（開いていたプロファイルは profile/open からやり直す） */
  readonly onDidRestart = this.onDidRestartEmitter.event;
  /** サーバーが止まった（落ちた・止めた） */
  readonly onDidStop = this.onDidStopEmitter.event;

  constructor(
    protected readonly output: vscode.OutputChannel,
    private readonly clientVersion: string,
    private readonly options: ServerProcessOptions<N>,
  ) {}

  get isRunning(): boolean {
    return this.running !== undefined;
  }

  /** 動いているか、起動の途中（設定が変わったときに起動し直すかどうかに使う） */
  get isStartingOrRunning(): boolean {
    return this.running !== undefined || this.starting !== undefined;
  }

  async request<M extends keyof R & string>(
    method: M,
    params: R[M]['params'],
    token?: vscode.CancellationToken,
  ): Promise<R[M]['result']> {
    const { connection } = await this.ensureStarted();
    return connection.request(method, params, token);
  }

  /** つないで initialize の結果を返す（動いていなければ起動する） */
  async initializeResult(): Promise<I> {
    return (await this.ensureStarted()).connection.initializeResult;
  }

  /** 動いていなければ送らない（profile/close などは、サーバーが止まっていれば意味がない） */
  protected notifyRunning(send: (connection: CornixConnection<R, N, I>) => Promise<void>, what: string): void {
    const connection = this.running?.connection;
    if (connection) send(connection).catch((error: unknown) => this.log(`${what} を送れませんでした: ${String(error)}`));
  }

  onNotification<M extends keyof N & string>(method: M, handler: (params: N[M]) => void): vscode.Disposable {
    let set = this.handlers.get(method);
    if (!set) this.handlers.set(method, (set = new Set()));
    const entry = handler as (params: never) => void;
    set.add(entry);
    return new vscode.Disposable(() => set.delete(entry));
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
    this.log(`${this.options.label}を止めます`);
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

  private ensureStarted(): Promise<Running<R, N, I>> {
    if (this.running) return Promise.resolve(this.running);
    if (this.disposed) return Promise.reject(new CornixUnavailableError('拡張が止まっています'));
    this.starting ??= this.start().finally(() => {
      this.starting = undefined;
    });
    return this.starting;
  }

  private async start(): Promise<Running<R, N, I>> {
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
    const args = ['serve', '--root', root.fsPath, ...this.options.extraArgs(config)];
    this.log(`${this.options.label}を起動します: ${command} ${args.join(' ')}`);

    const child = spawn(command, args, { cwd: root.fsPath, stdio: ['pipe', 'pipe', 'pipe'], env: process.env });
    child.stderr.setEncoding('utf-8');
    child.stderr.on('data', (chunk: string) => this.output.append(chunk));
    // 落ちたあとに書こうとしたとき（EPIPE）などで拡張ごと止まらないように、エラーは記録だけする
    child.stdin.on('error', (error) => this.log(`${this.options.label}に書けませんでした: ${error.message}`));
    child.on('error', (error) => this.log(`${this.options.label}のプロセスのエラー: ${error.message}`));

    const exited = new Promise<never>((_, reject) => {
      child.once('error', (error) => reject(error));
      child.once('exit', (code, signal) => reject(new Error(exitText(code, signal))));
    });

    let connection: CornixConnection<R, N, I>;
    try {
      connection = await Promise.race([
        CornixConnection.connect<R, N, I>(
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
      throw this.unavailable(`cornix の${this.options.label}を起動できませんでした（${reason}）。出力パネル「Cornix」を見てください。`, true);
    }
    exited.catch(() => undefined);

    const running: Running<R, N, I> = { process: child, connection };
    const { serverInfo } = connection.initializeResult;
    this.log(`${this.options.label}につながりました: ${serverInfo.name} ${serverInfo.version}（${serverInfo.implementation}）`);

    for (const method of this.options.notifications) {
      connection.onNotification(method, (params) => {
        for (const handler of this.handlers.get(method) ?? []) (handler as (params: N[typeof method]) => void)(params);
      });
    }
    child.on('exit', (code, signal) => this.handleExit(running, code, signal));

    this.running = running;
    this.generation += 1;
    if (this.generation > 1) this.onDidRestartEmitter.fire();
    return running;
  }

  private handleExit(running: Running<R, N, I>, code: number | null, signal: NodeJS.Signals | null): void {
    if (this.running !== running) return;
    this.running = undefined;
    running.connection.dispose();
    this.log(`${this.options.label}が止まりました（${exitText(code, signal)}）`);
    this.onDidStopEmitter.fire();
    if (this.disposed || !this.options.notifyExit) return;
    void vscode.window
      .showErrorMessage(`Cornix の${this.options.label}が止まりました（${exitText(code, signal)}）。`, '再起動', '出力を表示')
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

  protected log(message: string): void {
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
