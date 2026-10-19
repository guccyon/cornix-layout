// サーバーとの JSON-RPC の接続（protocol.md の 1. と 4.）。標準入出力の Content-Length の枠は vscode-jsonrpc に任せる。
// vscode に依存しない（vitest で偽のサーバーとつないで確かめる）。プロセスの起動と再起動は cornixServer.ts。
import type { Readable, Writable } from 'node:stream';
import {
  createMessageConnection,
  ResponseError,
  StreamMessageReader,
  StreamMessageWriter,
  Trace,
  type MessageConnection,
} from 'vscode-jsonrpc/node';
import {
  ErrorCodes,
  PROTOCOL_VERSION,
  type ClientNotificationMap,
  type ClientNotificationMethod,
  type InitializeResult,
  type RequestMap,
  type RequestMethod,
  type ServerNotificationMap,
  type ServerNotificationMethod,
} from '../protocol';

export type TraceLevel = 'off' | 'messages' | 'verbose';

export type ConnectOptions = {
  clientName: string;
  clientVersion: string;
  trace?: TraceLevel;
  /** やりとりの記録（trace が off 以外のとき）を書く先 */
  log?: (line: string) => void;
  /** initialize の応答を待つ上限（ミリ秒）。既定は 10 秒 */
  initializeTimeoutMs?: number;
};

const DEFAULT_INITIALIZE_TIMEOUT_MS = 10_000;

export type Disposable = { dispose(): void };

/** 約束の版が合わない（サーバーが -32051 で断った、または違う版を返した） */
export class ProtocolVersionError extends Error {
  constructor(
    readonly serverVersion: string | undefined,
    readonly supported: string[] | undefined,
  ) {
    const detail = serverVersion ? `サーバーの版 ${serverVersion}` : `サーバーが使える版 ${supported?.join(', ') ?? '不明'}`;
    super(`cornix のサーバーと拡張の約束の版が合いません（拡張の版 ${PROTOCOL_VERSION}、${detail}）。拡張か cornix を新しくしてください。`);
    this.name = 'ProtocolVersionError';
  }
}

export class CornixConnection {
  private constructor(
    private readonly connection: MessageConnection,
    /** initialize の結果。capabilities で画面に出す機能を決める（serverInfo.implementation で分岐しない） */
    readonly initializeResult: InitializeResult,
  ) {}

  /** 接続して initialize と initialized まで済ませる */
  static async connect(
    streams: { input: Readable; output: Writable },
    options: ConnectOptions,
  ): Promise<CornixConnection> {
    const connection = createMessageConnection(
      new StreamMessageReader(streams.input, 'utf-8'),
      new StreamMessageWriter(streams.output, 'utf-8'),
    );
    connection.listen();
    if (options.trace && options.trace !== 'off' && options.log) {
      const log = options.log;
      await connection.trace(options.trace === 'verbose' ? Trace.Verbose : Trace.Messages, {
        log: (message: unknown, data?: string) => {
          const text = typeof message === 'string' ? message : JSON.stringify(message);
          log(data ? `${text}\n${data}` : text);
        },
      });
    }

    let result: InitializeResult;
    try {
      const timeoutMs = options.initializeTimeoutMs ?? DEFAULT_INITIALIZE_TIMEOUT_MS;
      result = await withTimeout(
        connection.sendRequest<InitializeResult>('initialize', {
          protocolVersion: PROTOCOL_VERSION,
          clientInfo: { name: options.clientName, version: options.clientVersion },
        } satisfies RequestMap['initialize']['params']),
        timeoutMs,
        `initialize に応答がありません（${timeoutMs / 1000} 秒待ちました）`,
      );
    } catch (error) {
      connection.dispose();
      if (error instanceof ResponseError && error.code === ErrorCodes.ProtocolVersionMismatch) {
        const data = error.data as { supported?: string[] } | undefined;
        throw new ProtocolVersionError(undefined, data?.supported);
      }
      throw error;
    }
    if (result.protocolVersion !== PROTOCOL_VERSION) {
      connection.dispose();
      throw new ProtocolVersionError(result.protocolVersion, undefined);
    }
    await connection.sendNotification('initialized', {} satisfies ClientNotificationMap['initialized']);
    return new CornixConnection(connection, result);
  }

  request<M extends RequestMethod>(method: M, params: RequestMap[M]['params']): Promise<RequestMap[M]['result']> {
    if (params === undefined) return this.connection.sendRequest(method);
    return this.connection.sendRequest(method, params);
  }

  notify<M extends ClientNotificationMethod>(method: M, params: ClientNotificationMap[M]): Promise<void> {
    if (params === undefined) return this.connection.sendNotification(method);
    return this.connection.sendNotification(method, params);
  }

  onNotification<M extends ServerNotificationMethod>(
    method: M,
    handler: (params: ServerNotificationMap[M]) => void,
  ): Disposable {
    return this.connection.onNotification(method, (params: ServerNotificationMap[M]) => handler(params));
  }

  /** 枠が読めない・流れが切れたとき */
  onClose(handler: () => void): Disposable {
    return this.connection.onClose(handler);
  }

  /** shutdown のあと exit を送る。待ち切れなければあきらめる（プロセスを止めるのは呼ぶ側） */
  async shutdown(timeoutMs = 2000): Promise<void> {
    try {
      await withTimeout(this.request('shutdown', undefined), timeoutMs, 'shutdown に応答がありません');
      await this.notify('exit', undefined);
    } catch {
      // サーバーがもう止まっている・応えないときは何もしない
    } finally {
      this.connection.dispose();
    }
  }

  dispose(): void {
    this.connection.dispose();
  }
}

function withTimeout<T>(promise: Promise<T>, ms: number, message: string): Promise<T> {
  return new Promise<T>((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error(message)), ms);
    promise.then(
      (value) => {
        clearTimeout(timer);
        resolve(value);
      },
      (error: unknown) => {
        clearTimeout(timer);
        reject(error);
      },
    );
  });
}
