// 拡張（ホスト）と編集画面（Webview）の間のメッセージ。画面の作業（段 2 の G）はここに種類を足していく。
import type { DeviceChange } from './deviceProtocol';
import type {
  AnyChange,
  CandidatesParams,
  CandidatesResult,
  Change,
  InspectParams,
  InspectResult,
  ItemEdit,
  ProfileSnapshot,
  Range,
  ShortcutTreeParams,
  ShortcutTreeResult,
} from './protocol';

/**
 * Webview からホストに中継してもらうリクエスト（Webview はサーバーと直接話せない）。
 * params は約束の params から profileId を除いたもの（ホストがそのときの profileId を入れる）。
 * keycode/shortcutTree はプロファイルによらないので params は {}（マクロの preset: を選び直す階層の選択に使う）
 */
export interface WebviewRequestMap {
  'keycode/candidates': { params: Omit<CandidatesParams, 'profileId'>; result: CandidatesResult };
  'keycode/inspect': { params: Omit<InspectParams, 'profileId'>; result: InspectResult };
  'keycode/shortcutTree': { params: ShortcutTreeParams; result: ShortcutTreeResult };
}
export type WebviewRequestMethod = keyof WebviewRequestMap;

/** ホストが中継するメソッド（これ以外は中継しない。Webview から来た文字列をそのままサーバーに渡さないため） */
export const RELAYED_METHODS: ReadonlySet<string> = new Set<WebviewRequestMethod>(['keycode/candidates', 'keycode/inspect', 'keycode/shortcutTree']);

/** 中継するときに profileId を入れないメソッド（プロファイルによらない。params は {} にして送る） */
export const PROFILE_FREE_METHODS: ReadonlySet<WebviewRequestMethod> = new Set<WebviewRequestMethod>(['keycode/shortcutTree']);

export function isRelayedMethod(method: unknown): method is WebviewRequestMethod {
  return typeof method === 'string' && RELAYED_METHODS.has(method);
}

export type WebviewRequest = {
  [M in WebviewRequestMethod]: { type: 'request'; id: number; method: M; params: WebviewRequestMap[M]['params'] };
}[WebviewRequestMethod];

/**
 * v0.4: 実機と比べた状態（tasks-v0.4.md の「画面」）。ホストが持ち、変わるたびに Webview に送る。
 * - unknown: まだ比べていない・保存したあと（「実機: 未確認」）
 * - same / different: 比べた・反映した・戻したあと（different のとき changes に違い。反映のあとは読み直しで残った違い）
 */
export type DeviceViewState = {
  status: 'unknown' | 'same' | 'different';
  /** status が different のときの違い（protocol.md の 14.2。そのほかは []） */
  changes: DeviceChange[];
  /** 実機の操作の最中（ボタンを押せなくする）。null は何もしていない */
  busy: 'compare' | 'apply' | 'restore' | null;
  /** 設定 cornix.device.allowWrites（false でも反映・戻すのボタンは出す。押すとホストが案内する） */
  allowWrites: boolean;
};

/** v0.4: 画面のボタンから頼む実機の操作（ホストがコマンド cornix.device.compare / apply / restore と同じことをする） */
export type DeviceAction = 'compare' | 'apply' | 'restore';

/** ホスト → Webview */
export type HostMessage =
  /** 描くもの。開いたとき・読み直したとき・変更のたびに送る */
  | {
      type: 'snapshot';
      snapshot: ProfileSnapshot;
      /** v0.1 の値の書き換え（同じ Address は最後の値だけ） */
      changes: Change[];
      /** v0.2: 未保存の変更の全部を当てる順に（並びを指す Change を含む。protocol.md の 12.3）。v0.2 のホストは必ず送る */
      pending?: AnyChange[];
    }
  /** 読めなかったときなど */
  | { type: 'error'; message: string }
  /** WebviewRequest の応答（id と method は要求と同じ）。失敗したら error にその文 */
  | { type: 'response'; id: number; method: string; result: unknown }
  | { type: 'response'; id: number; method: string; error: string }
  /** v0.4: 実機と比べた状態。開いたとき（ready のあと）と、変わるたびに送る */
  | { type: 'device'; state: DeviceViewState };

/** Webview → ホスト */
export type WebviewMessage =
  /** 画面の準備ができた（ホストは snapshot を送る） */
  | { type: 'ready' }
  /** 値を変えた。ホストは未保存の変更に足し、VS Code の編集の履歴に載せる */
  | { type: 'change'; change: Change }
  /** v0.2: 並びの操作・行の削除・注記（protocol.md の 12.3）。ホストは未保存の変更の末尾に足す */
  | { type: 'edit'; change: AnyChange }
  /** v0.2: 項目の追加・削除・名前の変更（protocol.md の 12.5）。ホストが確認のダイアログを出してすぐ書く */
  | { type: 'itemEdit'; edit: ItemEdit }
  /** サーバーへのリクエストの中継 */
  | WebviewRequest
  /** v0.4: 実機の操作のボタンを押した */
  | { type: 'deviceAction'; action: DeviceAction }
  /** 設定ディレクトリのファイルをテキストで開く（file は設定ディレクトリからの相対パス。range があればそこを選ぶ） */
  | { type: 'openFile'; file: string; range?: Range }
  /**
   * snapshot を描き終えた。中身は描いたものの数と、media/webview.css が効いているか。
   * 統合テストが待つためのものだが本番でも送る（ホストは onDidReceiveWebviewMessage に流すだけで、何もしない）
   */
  | { type: 'rendered'; status: ProfileSnapshot['status']; layer: number | null; keys: number; encoders: number; styled: boolean };
