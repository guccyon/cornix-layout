// 拡張（ホスト）と編集画面（Webview）の間のメッセージ。画面の作業（段 2 の G）はここに種類を足していく。
import type { Change, ProfileSnapshot } from './protocol';

/** ホスト → Webview */
export type HostMessage =
  /** 描くもの。開いたとき・読み直したとき・変更のたびに送る */
  | { type: 'snapshot'; snapshot: ProfileSnapshot; changes: Change[] }
  /** 読めなかったときなど */
  | { type: 'error'; message: string };

/** Webview → ホスト */
export type WebviewMessage =
  /** 画面の準備ができた（ホストは snapshot を送る） */
  | { type: 'ready' }
  /** 値を変えた。ホストは未保存の変更に足し、VS Code の編集の履歴に載せる */
  | { type: 'change'; change: Change };
