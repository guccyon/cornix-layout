// 拡張（ホスト）と編集画面（Webview）の間のメッセージ。画面の作業（段 2 の G）はここに種類を足していく。
import type { DevicePlan } from './deviceProtocol';
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

/** v0.4: 進み具合（device/progress の phase・done・total） */
export type DeviceTransferProgress = { done: number; total: number };

/**
 * v0.4: 実機への反映の途中の状態（tasks-v0.4.md の「画面」）。ホストが持ち、変わるたびに Webview に送る。Webview はこれがある間モーダルを出す。
 * - reading: 実機を読んで比べている（やめるで取り消せる）
 * - preview: 違いを見せて「確定」か「やめる」を待つ（plan.empty なら書くものはない）。stale は比べたあとで設定ファイルが変わった（確定できない）
 * - writing: 確定して書いている（取り消せない）
 */
export type DeviceTransfer =
  | { step: 'reading'; progress: DeviceTransferProgress | null }
  | { step: 'preview'; plan: DevicePlan; profile: string; stale: boolean }
  | { step: 'writing'; plan: DevicePlan; profile: string; progress: (DeviceTransferProgress & { phase: 'read' | 'write' | 'verify' }) | null };

export type DeviceViewState = {
  /** 反映の途中（ないときはモーダルを出さない） */
  transfer: DeviceTransfer | null;
  /** いずれかのプロファイルで反映の途中（このプロファイルの節の「反映のプレビュー」を押せなくする） */
  busyElsewhere: boolean;
  /** 設定 cornix.device.allowWrites（false でもプレビューはできる。確定は押せない） */
  allowWrites: boolean;
};

/**
 * v0.4: 画面から頼む実機の操作。preview は節のボタンとプレビューの「もう一度比べる」、confirm・cancel はモーダルのボタン、
 * openSettings はモーダルの「設定を開く」（cornix.device.allowWrites を開く）
 */
export type DeviceAction = 'preview' | 'confirm' | 'cancel' | 'openSettings';

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
  /**
   * v0.2: 項目の追加・削除・名前の変更（protocol.md の 12.5）。ホストが確認のダイアログを出してすぐ書く。
   * v0.5: 番号の操作（use / unuse / setIndex）とショートカットの追加（create の shortcut。isPendingItemEdit）は書かずに、
   * ホストが profile/planItemEdit の changes を 1 つの編集として未保存の変更の末尾に足す（確認は unuse で壊れる参照があるときだけ）。
   * 結果は snapshot のメッセージの pending で届く（番号は src/itemIndex.ts の arrangeItems で出す）。失敗はホストが通知で知らせ、pending は変わらない
   */
  | { type: 'itemEdit'; edit: ItemEdit }
  /** サーバーへのリクエストの中継 */
  | WebviewRequest
  /** v0.4: デバイス転送の節・反映のプレビューのボタンを押した */
  | { type: 'deviceAction'; action: DeviceAction }
  /** 設定ディレクトリのファイルをテキストで開く（file は設定ディレクトリからの相対パス。range があればそこを選ぶ） */
  | { type: 'openFile'; file: string; range?: Range }
  /**
   * snapshot を描き終えた。中身は描いたものの数と、media/webview.css が効いているか。
   * 統合テストが待つためのものだが本番でも送る（ホストは onDidReceiveWebviewMessage に流すだけで、何もしない）
   */
  | { type: 'rendered'; status: ProfileSnapshot['status']; layer: number | null; keys: number; encoders: number; styled: boolean };
