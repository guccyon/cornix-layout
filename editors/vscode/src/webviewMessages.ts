// 拡張（ホスト）と編集画面（Webview）の間のメッセージ。画面の作業（段 2 の G）はここに種類を足していく。
import type { CandidatesParams, CandidatesResult, Change, InspectParams, InspectResult, ProfileSnapshot, Range } from './protocol';

/**
 * Webview からホストに中継してもらうリクエスト（Webview はサーバーと直接話せない）。
 * params は約束の params から profileId を除いたもの（ホストがそのときの profileId を入れる）
 */
export interface WebviewRequestMap {
  'keycode/candidates': { params: Omit<CandidatesParams, 'profileId'>; result: CandidatesResult };
  'keycode/inspect': { params: Omit<InspectParams, 'profileId'>; result: InspectResult };
}
export type WebviewRequestMethod = keyof WebviewRequestMap;

export type WebviewRequest = {
  [M in WebviewRequestMethod]: { type: 'request'; id: number; method: M; params: WebviewRequestMap[M]['params'] };
}[WebviewRequestMethod];

/** ホスト → Webview */
export type HostMessage =
  /** 描くもの。開いたとき・読み直したとき・変更のたびに送る */
  | { type: 'snapshot'; snapshot: ProfileSnapshot; changes: Change[] }
  /** 読めなかったときなど */
  | { type: 'error'; message: string }
  /** WebviewRequest の応答（id は同じ）。失敗したら error にその文 */
  | { type: 'response'; id: number; result: unknown }
  | { type: 'response'; id: number; error: string };

/** Webview → ホスト */
export type WebviewMessage =
  /** 画面の準備ができた（ホストは snapshot を送る） */
  | { type: 'ready' }
  /** 値を変えた。ホストは未保存の変更に足し、VS Code の編集の履歴に載せる */
  | { type: 'change'; change: Change }
  /** サーバーへのリクエストの中継 */
  | WebviewRequest
  /** 設定ディレクトリのファイルをテキストで開く（file は設定ディレクトリからの相対パス。range があればそこを選ぶ） */
  | { type: 'openFile'; file: string; range?: Range }
  /** snapshot を描き終えた（統合テストが待つため。中身は描いたものの数と、media/webview.css が効いているか） */
  | { type: 'rendered'; status: ProfileSnapshot['status']; layer: number | null; keys: number; encoders: number; styled: boolean };
