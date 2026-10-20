// 編集画面（Webview）から来たリクエストの中継と、「ファイルを開く」のパスの確かめ。vscode に依存しない（単体テストのため）。
import * as path from 'node:path';
import type { HostMessage, WebviewRequestMethod } from '../webviewMessages';
import { isRelayedMethod, PROFILE_FREE_METHODS } from '../webviewMessages';

/** サーバーへのリクエスト（params は Webview の params に profileId を足したもの。PROFILE_FREE_METHODS は {}） */
export type RelayRequest = (method: WebviewRequestMethod, params: object) => Promise<unknown>;

/**
 * Webview の request をサーバーに中継し、応答のメッセージを返す。
 * 中継するのは RELAYED_METHODS だけ（Webview から来た文字列をそのままサーバーに渡さない）。profileId はそのときのものを入れる。
 * プロファイルによらないメソッド（PROFILE_FREE_METHODS）は Webview の params を使わずに {} で送る
 */
export async function relayRequest(
  message: { id: unknown; method: unknown; params: unknown },
  request: RelayRequest,
  profileId: string,
): Promise<Extract<HostMessage, { type: 'response' }>> {
  const id = typeof message.id === 'number' ? message.id : -1;
  const method = String(message.method);
  if (!isRelayedMethod(message.method)) return { type: 'response', id, method, error: `中継しないメソッドです: ${method}` };
  const params = typeof message.params === 'object' && message.params !== null ? message.params : {};
  try {
    const result = await request(message.method, PROFILE_FREE_METHODS.has(message.method) ? {} : { ...params, profileId });
    return { type: 'response', id, method, result };
  } catch (error) {
    return { type: 'response', id, method, error: error instanceof Error ? error.message : String(error) };
  }
}

/**
 * 設定ディレクトリ（dir。ファイルシステムのパス）の中のファイル file（設定ディレクトリからの相対パス）の絶対パス。
 * 絶対パスや、`..` で設定ディレクトリの外に出るものは undefined（開かない）
 */
export function profileFilePath(dir: string, file: string): string | undefined {
  if (!file || path.isAbsolute(file)) return undefined;
  const base = path.resolve(dir);
  const resolved = path.resolve(base, file);
  return resolved.startsWith(base + path.sep) ? resolved : undefined;
}
