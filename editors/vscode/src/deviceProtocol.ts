// 拡張と device のサーバー（`cornix serve --device`）の間のリクエストの約束（docs/vscode-extension/protocol.md の 14.）を TypeScript にしたもの。
// 型だけを置き、vscode にも vscode-jsonrpc にも依存しない（Webview とテスト用の偽の device のサーバーからも読む）。
// 枠・JSON-RPC・ライフサイクル（initialize / shutdown / exit）は編集のサーバーと同じなので protocol.ts の型を使う。
// protocol.md の 14. を変えたら、ここも同じ PR で変える。

import type { Diagnostic, Hand, InitializeParams, InitializeResult } from './protocol';

// ---------------------------------------------------------------------------
// 14.1 device のサーバー
// ---------------------------------------------------------------------------

export type DeviceInitializeParams = InitializeParams;

/** device のサーバーの initialize の result。capabilities に device と deviceWrites が足される */
export type DeviceInitializeResult = Omit<InitializeResult, 'capabilities'> & {
  capabilities: InitializeResult['capabilities'] & {
    /** device/* を持つ（device のサーバーでは常に true） */
    device: true;
    /** --allow-writes を付けて起動した（false なら device/apply・device/restore は -32074） */
    deviceWrites: boolean;
  };
};

// ---------------------------------------------------------------------------
// 14.2 共通の型
// ---------------------------------------------------------------------------

export type DeviceChangeKind = 'key' | 'encoder' | 'macro' | 'tapDance' | 'combo' | 'setting' | 'other';

export type EncoderSide = 'left' | 'right';
export type EncoderDirection = 'cw' | 'ccw' | 'push';

/** 実機との違い 1 件 */
export type DeviceChange = {
  kind: DeviceChangeKind;
  /** kind が key / encoder のとき */
  layer?: number;
  /** kind が key のとき。論理位置（LayerKey・PositionMapEntry の hand / row / col と同じ。図と欄で使う） */
  key?: { hand: Hand; row: number; col: number };
  /** kind が key のとき。position_map の記号（"tab"。一覧の「レイヤー名 / 位置の名前」に使う）。
   *  position_map にない（論理位置に直せない）キーは kind: "other" にして text だけを使う */
  position?: string;
  /** kind が encoder のとき */
  encoder?: { side: EncoderSide; direction: EncoderDirection };
  /** macro / tapDance / combo の番号 */
  index?: number;
  /** 名前がある項目（マクロなど）・設定の名前 */
  name?: string;
  /** 実機の今の値の表記（キーは VialNotation の表記。項目は短い要約） */
  device: string;
  /** このプロファイル（か戻す先のバックアップ）の値の表記 */
  profile: string;
  /** 1 行の説明（Device::ChangeDescriber と同じ文。"レイヤー0 (1,2): KC_A → KC_B"） */
  text: string;
};

export type DevicePlan = {
  /** Planning::Plan#token。device/apply・device/restore に渡す */
  token: string;
  empty: boolean;
  changes: DeviceChange[];
  /** RMK 未対応のキーコードなど（Device::ChangePolicy） */
  warnings: string[];
  /** 書き込み先（確認のダイアログに出す） */
  keyboard: { name: string; uid: string };
};

// ---------------------------------------------------------------------------
// 14.3〜14.5 メソッド
// ---------------------------------------------------------------------------

/** プロファイルを指す（profile/list の dir と同じ。ワークスペースのフォルダからの相対パス） */
export type DeviceDirParams = { dir: string };

export type DeviceCompareParams = DeviceDirParams;
export type DeviceCompareResult = {
  plan: DevicePlan;
  /** 目標の .vil（compile の出力かバックアップ）。ワークスペースのフォルダからの相対パス（外なら絶対パス） */
  source: string;
};

export type DeviceApplyParams = DeviceDirParams & { token: string };
export type DeviceApplyResult = {
  /** 書き込んだ件数（差分がなければ 0） */
  applied: number;
  /** 書く前に取ったバックアップのパス（書かなかったら null） */
  backup: string | null;
  /** 読み直して残った違い（ふつうは []） */
  remaining: DeviceChange[];
};

/** バックアップの種類（Storage::SnapshotStore の種類。read と build は一覧に出さない） */
export type DeviceBackupKind = 'pre-apply' | 'pre-restore' | 'backup' | 'legacy';

export type DeviceBackup = {
  /** device/compareBackup・device/restore の backup に渡す名前 */
  name: string;
  /** .vil のパス */
  path: string;
  /** ISO 8601（時差付き） */
  createdAt: string;
  /** pre-apply は反映の前、pre-restore は戻す前に取ったもの */
  kind: DeviceBackupKind;
};

export type DeviceBackupsParams = DeviceDirParams;
/** 新しい順 */
export type DeviceBackupsResult = { backups: DeviceBackup[] };

export type DeviceCompareBackupParams = DeviceDirParams & { backup: string };
export type DeviceCompareBackupResult = DeviceCompareResult;

export type DeviceRestoreParams = DeviceDirParams & { backup: string; token: string };
export type DeviceRestoreResult = DeviceApplyResult;

// ---------------------------------------------------------------------------
// 14.6 進み具合
// ---------------------------------------------------------------------------

export type DevicePhase = 'read' | 'write' | 'verify';

/** device/progress（サーバー → 拡張の通知）。$/cancelRequest は phase が read の間だけ効く */
export type DeviceProgressParams = { phase: DevicePhase; done: number; total: number };

// ---------------------------------------------------------------------------
// メソッドの一覧
// ---------------------------------------------------------------------------

/** 拡張 → device のサーバーのリクエスト（initialize・shutdown は protocol.ts の RequestMap と同じ） */
export interface DeviceRequestMap {
  initialize: { params: DeviceInitializeParams; result: DeviceInitializeResult };
  shutdown: { params: undefined; result: null };
  'device/compare': { params: DeviceCompareParams; result: DeviceCompareResult };
  'device/apply': { params: DeviceApplyParams; result: DeviceApplyResult };
  'device/backups': { params: DeviceBackupsParams; result: DeviceBackupsResult };
  'device/compareBackup': { params: DeviceCompareBackupParams; result: DeviceCompareBackupResult };
  'device/restore': { params: DeviceRestoreParams; result: DeviceRestoreResult };
}

/** device のサーバー → 拡張の通知 */
export interface DeviceServerNotificationMap {
  'device/progress': DeviceProgressParams;
}

export type DeviceRequestMethod = keyof DeviceRequestMap;
export type DeviceServerNotificationMethod = keyof DeviceServerNotificationMap;

// ---------------------------------------------------------------------------
// 14.7 エラー
// ---------------------------------------------------------------------------

export const DeviceErrorCodes = {
  DeviceUnavailable: -32070,
  PlanChanged: -32071,
  WriteIncomplete: -32072,
  PlanRejected: -32073,
  WritesNotAllowed: -32074,
  CompileFailed: -32075,
  RequestCancelled: -32800,
} as const;

export type DeviceErrorCode = (typeof DeviceErrorCodes)[keyof typeof DeviceErrorCodes];

/** 実機が使えない理由（macOS 以外・ブリッジが未ビルド・見つからない・応答がない） */
export type DeviceUnavailableReason = 'platform' | 'bridge' | 'notConnected' | 'timeout';

/** 各エラーの data の形 */
export type DeviceErrorData = {
  DeviceUnavailable: { reason: DeviceUnavailableReason };
  WriteIncomplete: { applied: number; backup: string | null };
  PlanRejected: { keycodes: string[] };
  CompileFailed: { diagnostics: Diagnostic[] };
};
