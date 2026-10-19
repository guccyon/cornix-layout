// 拡張とサーバー（`cornix serve`）の間のリクエストの約束（docs/vscode-extension/protocol.md の v0.1）を TypeScript にしたもの。
// 型だけを置き、vscode にも vscode-jsonrpc にも依存しない（Webview とテスト用の偽のサーバーからも読む）。
// protocol.md を変えたら、ここも同じ PR で変える。

/** 約束の版（protocol.md の 4.）。1.0 になるまでは major.minor 全体が一致しなければ話せない */
export const PROTOCOL_VERSION = '0.1';

// ---------------------------------------------------------------------------
// 2. 共通の型
// ---------------------------------------------------------------------------

/** ファイルの中の位置。行も列も 0 始まり。列は UTF-16 のコード単位（LSP と同じ） */
export type Position = { line: number; character: number };
export type Range = { start: Position; end: Position };

/**
 * 設定ファイルの中の値の場所。
 * - file: 設定ディレクトリからの相対パス（"layers/0_base.yml"）
 * - path: ファイルの中のキーの道筋（["mapping", "left_hand", "row0", "tab"]）。注記付きの形でも `.key` は付けない
 */
export type Address = {
  file: string;
  path: (string | number)[];
};

/** ディスク上のバイト列そのものの SHA-256（"sha256:" + 小文字の 16 進）。ファイルがなければ null */
export type FileVersion = string | null;

/** 検証の結果 1 件 */
export type Diagnostic = {
  severity: 'error' | 'warning';
  /** 利用者向けの日本語。validate の表示から「ファイル: キーの位置: 」を除いた文 */
  message: string;
  /** 構造検証（読み込み）か意味検証か */
  source: 'structure' | 'semantic';
  /** どの値の問題か。ファイルやディレクトリ全体の問題では省く */
  address?: Address;
  /** address がないときの、問題のあるファイル（ディレクトリの問題は "macros/"） */
  file?: string;
  /** 波線を引く範囲（値の部分）。位置が分からなければ省く */
  range?: Range;
};

export type KeyKind =
  | 'basic'
  | 'modified'
  | 'layerAction'
  | 'layerTap'
  | 'layerMod'
  | 'modTap'
  | 'oneShotMod'
  | 'macro'
  | 'tapDance'
  | 'quantum'
  | 'noKey'
  | 'transparent'
  | 'raw';

export type KeyDisplay = {
  /** 1 行で描くときの短い文字（"Space"、"⇧⌘P"、"Bracket Pair"、"TG L3"）。修飾キーは macOS の並び（⌃⌥⇧⌘） */
  label: string;
  /** 上の面の文字。2 役のキーのタップ側（"Space"）、レイヤー操作の操作名（"TG"）、LM の修飾キー（"⇧"）。MO は省く */
  tap?: string;
  /** 下の帯の文字。2 役のキーのホールド側（"L1"、"⇧"）、レイヤー操作・LM のレイヤー（"L3"）。名前があっても番号 */
  hold?: string;
  /** タップダンスの割り当てのある動作（図で窓に分けて描く）。定義のないもの・どの動作も NoKey なら省く */
  actions?: TapDanceAction[];
};

/** タップダンスの動作 1 つ。tap・hold・doubleTap・tapHold の順で、NoKey の動作は省く */
export type TapDanceAction = {
  action: 'tap' | 'hold' | 'doubleTap' | 'tapHold';
  /** その動作のキーの label（"Tab"、"L1"） */
  label: string;
};

/** 割り当て 1 つの解釈 */
export type KeyValue = {
  /** ファイルに書いてある表記そのまま */
  text: string;
  /** decompile の正規形 */
  canonical: string;
  /** 16bit 値。capabilities.keycodeCode が false のサーバーでは null */
  code: number | null;
  kind: KeyKind;
  /** Shortcut(...) で書いたもの、preset: のマクロを指すもの。どちらでもなければ項目ごと省く（icon・note も同じ） */
  origin?: 'shortcut' | 'presetShortcut' | 'presetMacro';
  display: KeyDisplay;
  /** アイコン ID（"simple-icons:figma"）。同梱のショートカットと preset: のマクロだけ */
  icon?: string;
  /** 注記（{ key:, note: } の note） */
  note?: string;
};

/** 画面での変更 1 つ。キーは表記の文字列、QMK 設定は数値か真偽値 */
export type Change = {
  address: Address;
  value: string | number | boolean;
};

// ---------------------------------------------------------------------------
// 4. ライフサイクル
// ---------------------------------------------------------------------------

export type InitializeParams = {
  protocolVersion: string;
  clientInfo: { name: string; version: string };
};

export type ServerCapabilities = {
  /** Profile#diagnostics に当たる意味検証をする */
  semanticValidation: boolean;
  /** KeyValue.code（16bit 値）を返す */
  keycodeCode: boolean;
};

export type InitializeResult = {
  protocolVersion: string;
  /** version は cornix の版（約束の版 protocolVersion とは別）。implementation で振る舞いを分けない（8.1） */
  serverInfo: { name: string; version: string; implementation: string };
  capabilities: ServerCapabilities;
};

// ---------------------------------------------------------------------------
// 5. プロファイルと候補
// ---------------------------------------------------------------------------

export type ProfileListParams = Record<string, never>;

export type ProfileSummary = {
  /** ワークスペースのフォルダからの相対パス（外なら絶対パス）。profile/open の引数 */
  dir: string;
  /** 表示用。重なってもよい（拡張は重なるときだけ dir を添える） */
  name: string;
};

export type ProfileListResult = {
  profiles: ProfileSummary[];
  /** 既定の設定ディレクトリの dir。なければ null */
  default: string | null;
};

export type ProfileOpenParams = { dir: string };

export type Hand = 'left' | 'right';

/** position_map の 1 つの位置（論理位置。親指キーは row 3 の col 3〜5） */
export type PositionMapEntry = {
  hand: Hand;
  row: number;
  col: number;
  /** position_map.yaml のグループ（"row0" … "row3"、"thumb_keys"） */
  group: string;
  /** position_map.yaml の記号（"tab"） */
  symbol: string;
};

/** レイヤーのキー 1 つ。割り当てのない位置も返り、そのとき value は null */
export type LayerKey = {
  hand: Hand;
  row: number;
  col: number;
  /** その位置を書くときの場所 */
  address: Address;
  value: KeyValue | null;
};

/** エンコーダの操作 1 つ */
export type EncoderAction = {
  address: Address;
  value: KeyValue | null;
};

export type EncoderBinding = {
  push: EncoderAction;
  ccw: EncoderAction;
  cw: EncoderAction;
};

export type LayerSnapshot = {
  index: number;
  name: string;
  /** レイヤーの説明。書いていなければ null（Domain::Layer の既定は nil） */
  description: string | null;
  /** 設定ディレクトリからの相対パス */
  file: string;
  keys: LayerKey[];
  encoders: { left: EncoderBinding; right: EncoderBinding };
};

export type QmkSettingSnapshot = {
  group: 'keyboard' | 'vial';
  name: string;
  type: 'integer' | 'boolean';
  /** ファイルにない設定は null */
  value: number | boolean | null;
  /** data/qmk_settings.yaml に足したら入る */
  default: number | boolean | null;
  description: string | null;
  address: Address;
};

export type ProfileReferences = {
  layers: { index: number; name: string }[];
  macros: { index: number; name: string; icon: string | null }[];
  tapDances: { index: number; name: string }[];
  shortcuts: { name: string; text: string }[];
};

/** profile/open・profile/saved の result と profile/didChange の snapshot */
export type ProfileSnapshot = {
  /** 以降のリクエストで使う。profile/close まで有効 */
  profileId: string;
  name: string;
  dir: string;
  /** "invalid" は構造検証で読めなかった。そのときは files と diagnostics だけを信じてよい（layers などは空） */
  status: 'ok' | 'invalid';
  /** 読んだファイル（設定ディレクトリからの相対パス）とその中身の版 */
  files: Record<string, FileVersion>;
  /** metadata.yaml の中身。読むだけで表示 */
  metadata: Record<string, unknown>;
  positionMap: PositionMapEntry[];
  layers: LayerSnapshot[];
  settings: QmkSettingSnapshot[];
  references: ProfileReferences;
  /** 保存済みのファイルの検証の結果 */
  diagnostics: Diagnostic[];
};

export type ProfileCloseParams = { profileId: string };

/** v0.1 は layerKey と encoder。v0.2 で macroKey などを足す */
export type CandidateContext = 'layerKey' | 'encoder';

export type CandidateCategory =
  | 'basic'
  | 'modifier'
  | 'media'
  | 'mouse'
  | 'layer'
  | 'macro'
  | 'tapDance'
  | 'shortcut'
  | 'presetShortcut'
  | 'special'
  | 'raw';

export type Candidate = {
  /** 選んだときに入れる表記 */
  insertText: string;
  label: string;
  detail?: string;
  category: CandidateCategory;
  icon?: string;
  /** Cornix が対応していないキーなど。付いたものは下に並ぶ */
  warning?: string;
};

export type CandidatesParams = {
  profileId: string;
  /** 知らない context は -32602（data: { field: "context" }） */
  context: CandidateContext;
  /** 入力中の文字。空なら「上に出すもの」から並べる（省くと ""） */
  query?: string;
  /** 省くと 50。1 未満は 1 */
  limit?: number;
};

export type CandidatesResult = {
  /** サーバーが決めた並び順のまま出す */
  items: Candidate[];
  /** query をそのまま表記として読めたときの解釈。読めなければ null */
  typed: KeyValue | null;
  /** limit で切った */
  truncated: boolean;
};

export type ShortcutTreeParams = Record<string, never>;

export type ShortcutTreeItem = {
  label: string;
  /** macro: true なら preset: に書く名前、それ以外は Shortcut('…') */
  insertText: string;
  /** キーの組（macro: true では省く） */
  text?: string;
  /** 複数の手順の定義で、macros/ の preset: でだけ使える */
  macro: boolean;
};

export type ShortcutTreeResult = {
  apps: {
    name: string;
    /** アイコンの表になければ null（v0.1 の同梱のアプリはすべてある） */
    icon: string | null;
    categories: { name: string; items: ShortcutTreeItem[] }[];
  }[];
};

export type InspectParams = {
  profileId: string;
  context: CandidateContext;
  text: string;
};

export type InspectResult = {
  /** 読めなければ null */
  value: KeyValue | null;
  /** この欄だけで分かる問題（address は省く）。読めない表記は構造の error が 1 件 */
  diagnostics: Diagnostic[];
  /** マウスを載せたときの説明。lines の最後は QMK の名前と 16bit 値（「QMK: LT(1, KC_SPACE)（0x412C）」。名前にできない値は「16bit 値: 0x5C00」）。読めなければ null */
  description: { title: string; lines: string[] } | null;
};

/** profile/validate と profile/planEdits の params */
export type DraftParams = {
  profileId: string;
  /** 変更を作ったときのファイルの版（変更のあるファイルだけ） */
  baseVersions: Record<string, FileVersion>;
  changes: Change[];
};

export type ValidateParams = DraftParams;
export type ValidateResult = { diagnostics: Diagnostic[] };

// ---------------------------------------------------------------------------
// 6. 保存
// ---------------------------------------------------------------------------

export type TextEdit = { range: Range; newText: string };

export type FileEdits = {
  file: string;
  baseVersion: FileVersion;
  /** ファイルを新しく作るとき true（settings/qmk_settings.yaml がないときだけ） */
  create: boolean;
  edits: TextEdit[];
};

export type PlanEditsParams = DraftParams;
export type PlanEditsResult = {
  files: FileEdits[];
  /** 書き換えたあとの検証の結果（validate と同じ） */
  diagnostics: Diagnostic[];
};

export type SavedParams = {
  profileId: string;
  /** 保存したファイルと、保存したあとの中身の版 */
  files: Record<string, FileVersion>;
};

// ---------------------------------------------------------------------------
// 7. 外での変更
// ---------------------------------------------------------------------------

export type FileChangeType = 'created' | 'changed' | 'deleted';

export type DidChangeFilesParams = {
  /** path はワークスペースのフォルダからの相対パス（外なら絶対パス） */
  changes: { path: string; type: FileChangeType }[];
};

export type ProfileDidChangeParams = {
  profileId: string;
  /** 変わったファイルと新しい版（消えたファイルは null） */
  files: Record<string, FileVersion>;
  snapshot: ProfileSnapshot;
};

// ---------------------------------------------------------------------------
// 3. メソッドの一覧
// ---------------------------------------------------------------------------

/** 拡張 → サーバーのリクエスト */
export interface RequestMap {
  initialize: { params: InitializeParams; result: InitializeResult };
  shutdown: { params: undefined; result: null };
  'profile/list': { params: ProfileListParams; result: ProfileListResult };
  'profile/open': { params: ProfileOpenParams; result: ProfileSnapshot };
  'keycode/candidates': { params: CandidatesParams; result: CandidatesResult };
  'keycode/shortcutTree': { params: ShortcutTreeParams; result: ShortcutTreeResult };
  'keycode/inspect': { params: InspectParams; result: InspectResult };
  'profile/validate': { params: ValidateParams; result: ValidateResult };
  'profile/planEdits': { params: PlanEditsParams; result: PlanEditsResult };
  'profile/saved': { params: SavedParams; result: ProfileSnapshot };
}

/** 拡張 → サーバーの通知 */
export interface ClientNotificationMap {
  initialized: Record<string, never>;
  exit: undefined;
  'profile/close': ProfileCloseParams;
  'workspace/didChangeFiles': DidChangeFilesParams;
}

/** サーバー → 拡張の通知 */
export interface ServerNotificationMap {
  'profile/didChange': ProfileDidChangeParams;
}

export type RequestMethod = keyof RequestMap;
export type ClientNotificationMethod = keyof ClientNotificationMap;
export type ServerNotificationMethod = keyof ServerNotificationMap;

// ---------------------------------------------------------------------------
// 9. エラー
// ---------------------------------------------------------------------------

export const ErrorCodes = {
  ParseError: -32700,
  InvalidRequest: -32600,
  MethodNotFound: -32601,
  InvalidParams: -32602,
  InternalError: -32603,
  ServerNotInitialized: -32002,
  ProfileNotFound: -32050,
  ProtocolVersionMismatch: -32051,
  NotSupported: -32052,
  VersionConflict: -32060,
  EditNotLocal: -32061,
} as const;

export type ErrorCode = (typeof ErrorCodes)[keyof typeof ErrorCodes];

/** 各エラーの data の形 */
export type ErrorData = {
  InvalidParams: { field: string };
  ProfileNotFound: { dir?: string; profileId?: string };
  ProtocolVersionMismatch: { supported: string[] };
  NotSupported: { capability: string };
  VersionConflict: { files: Record<string, FileVersion> };
  EditNotLocal: { address: Address; reason: 'multiline' | 'anchor' | 'flowInsert' };
};
