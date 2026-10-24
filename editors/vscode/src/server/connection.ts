// サーバーとの JSON-RPC の接続（protocol.md の 1. と 4.）。標準入出力の Content-Length の枠は vscode-jsonrpc に任せる。
// vscode に依存しない（vitest で偽のサーバーとつないで確かめる）。プロセスの起動と再起動は cornixServer.ts。
import type { Readable, Writable } from 'node:stream';
import {
  createMessageConnection,
  ResponseError,
  type CancellationToken,
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
  type ServerNotificationMap,
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

/**
 * 約束の版が合わない（サーバーが -32051 で断った、または違う版を返した）。
 * 古い版のサーバーにはつながない（v0.2 の画面は v0.1 のサーバーが返さない中身を前提にするため）。
 * 古いのがどちらかを版の数で比べ、新しくするほうを言う
 */
export class ProtocolVersionError extends Error {
  constructor(
    readonly serverVersion: string | undefined,
    readonly supported: string[] | undefined,
  ) {
    const versions = serverVersion ? [serverVersion] : supported ?? [];
    const detail = serverVersion ? `サーバーの版 ${serverVersion}` : `サーバーが使える版 ${supported?.join(', ') || '不明'}`;
    super(`cornix のサーバーと拡張の約束の版が合いません（拡張の版 ${PROTOCOL_VERSION}、${detail}）。${updateAdvice(versions)}`);
    this.name = 'ProtocolVersionError';
  }
}

/** サーバーの版がどれも拡張より古ければ cornix を、どれも新しければ拡張を新しくするよう言う。分からなければ両方 */
function updateAdvice(serverVersions: string[]): string {
  const ours = parseVersion(PROTOCOL_VERSION);
  const theirs = serverVersions.map(parseVersion);
  if (ours && theirs.length > 0 && theirs.every((version) => version !== undefined)) {
    const order = theirs.map((version) => compareVersions(version!, ours));
    if (order.every((sign) => sign < 0)) return 'cornix を新しくしてください。';
    if (order.every((sign) => sign > 0)) return '拡張を新しくしてください。';
  }
  return '拡張か cornix を新しくしてください。';
}

function parseVersion(version: string): [number, number] | undefined {
  const match = /^(\d+)\.(\d+)$/.exec(version);
  return match ? [Number(match[1]), Number(match[2])] : undefined;
}

function compareVersions(a: [number, number], b: [number, number]): number {
  return a[0] !== b[0] ? a[0] - b[0] : a[1] - b[1];
}

/** リクエストの一覧の形（protocol.ts の RequestMap、deviceProtocol.ts の DeviceRequestMap） */
export type RequestShape<R> = { [M in keyof R]: { params: unknown; result: unknown } };

/**
 * サーバーとの接続。編集のサーバー（RequestMap）と device のサーバー（DeviceRequestMap。protocol.md の 14.）で同じものを使う。
 * 型の引数はリクエストの一覧・サーバーからの通知の一覧・initialize の結果
 */
export class CornixConnection<
  R extends RequestShape<R> = RequestMap,
  N = ServerNotificationMap,
  I extends InitializeResult = InitializeResult,
> {
  private constructor(
    private readonly connection: MessageConnection,
    /** initialize の結果。capabilities で画面に出す機能を決める（serverInfo.implementation で分岐しない） */
    readonly initializeResult: I,
  ) {}

  /** 接続して initialize と initialized まで済ませる */
  static async connect<R extends RequestShape<R> = RequestMap, N = ServerNotificationMap, I extends InitializeResult = InitializeResult>(
    streams: { input: Readable; output: Writable },
    options: ConnectOptions,
  ): Promise<CornixConnection<R, N, I>> {
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

    let result: I;
    try {
      const timeoutMs = options.initializeTimeoutMs ?? DEFAULT_INITIALIZE_TIMEOUT_MS;
      result = await withTimeout(
        connection.sendRequest<I>('initialize', {
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
    return new CornixConnection<R, N, I>(connection, result);
  }

  /** token を取り消すと $/cancelRequest を送る（vscode-jsonrpc がする。device のサーバーは読む間だけ受け付ける。14.6） */
  request<M extends keyof R & string>(method: M, params: R[M]['params'], token?: CancellationToken): Promise<R[M]['result']> {
    if (params === undefined) return token ? this.connection.sendRequest(method, token) : this.connection.sendRequest(method);
    return token ? this.connection.sendRequest(method, params, token) : this.connection.sendRequest(method, params);
  }

  notify<M extends ClientNotificationMethod>(method: M, params: ClientNotificationMap[M]): Promise<void> {
    if (params === undefined) return this.connection.sendNotification(method);
    return this.connection.sendNotification(method, params);
  }

  onNotification<M extends keyof N & string>(method: M, handler: (params: N[M]) => void): Disposable {
    return this.connection.onNotification(method, (params: N[M]) => handler(params));
  }

  /** 枠が読めない・流れが切れたとき */
  onClose(handler: () => void): Disposable {
    return this.connection.onClose(handler);
  }

  /** shutdown のあと exit を送る。待ち切れなければあきらめる（プロセスを止めるのは呼ぶ側） */
  async shutdown(timeoutMs = 2000): Promise<void> {
    try {
      await withTimeout(this.connection.sendRequest('shutdown'), timeoutMs, 'shutdown に応答がありません');
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
