// 拡張とサーバー（`cornix serve`）の間のリクエストの約束（docs/vscode-extension/protocol.md の v0.1・v0.2）を TypeScript にしたもの。
// 型だけを置き、vscode にも vscode-jsonrpc にも依存しない（Webview とテスト用の偽のサーバーからも読む）。
// protocol.md を変えたら、ここも同じ PR で変える。

/** 約束の版（protocol.md の 4.）。1.0 になるまでは major.minor 全体が一致しなければ話せない */
export const PROTOCOL_VERSION = '0.5';

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
  /** v0.2。省けば set */
  op?: 'set';
  address: Address;
  value: string | number | boolean;
  /** v0.2。"note" は注記を書く（省けば割り当て） */
  field?: 'key' | 'note';
};

/** v0.2: 行や並びの要素を消す（protocol.md の 12.3） */
export type RemoveChange = { op: 'remove'; address: Address; field?: 'key' | 'note' };

/** v0.2: マクロの手順 1 つの値 */
export type MacroStepValue =
  | { action: 'tap' | 'down' | 'up'; keys: string[] }
  | { action: 'delay'; duration: number }
  | { action: 'text'; content: string };

/** v0.2: 並び（sequence・keys・trigger_keys）の index の前に足す */
export type InsertChange = { op: 'insert'; address: Address; index: number; value: string | MacroStepValue };

/** v0.2: 並びの中で from の要素を to へ動かす */
export type MoveChange = { op: 'move'; address: Address; from: number; to: number };

/** v0.2 の Change の全部。並びを指すものは畳まずに順に持つ（protocol.md の 12.3） */
export type AnyChange = Change | RemoveChange | InsertChange | MoveChange;

/** v0.2: キーを入れる欄 1 つ（protocol.md の 12.1） */
export type KeySlot = {
  address: Address;
  /** 書いていなければ null。注記は KeyValue.note */
  value: KeyValue | null;
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
  /** position_map.yaml のグループ（"row0" … "row3"、"thumb"。ファイルが旧名の thumb_keys で書いていても "thumb"。前の版のサーバーは "thumb_keys"） */
  group: string;
  /** position_map.yaml の記号（"tab"） */
  symbol: string;
  /** v0.2: 名前を書いている場所 */
  address?: Address;
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
  /** v0.2: description を書く場所（書いていなければ挿入の場所） */
  descriptionAddress?: Address;
};

/** v0.2: 値 1 つの欄（数値・文字） */
export type ValueSlot<T> = { address: Address; value: T | null };

/** v0.2: マクロの手順 1 つ */
export type MacroStepSnapshot =
  | { address: Address; action: 'tap' | 'down' | 'up'; keysAddress: Address; keys: KeySlot[] }
  | { address: Address; action: 'delay'; duration: ValueSlot<number> }
  | { address: Address; action: 'text'; content: ValueSlot<string> };

/** v0.2: マクロ・タップダンス・コンボの共通の項目 */
type ItemHeader = {
  index: number;
  name: string;
  /** 書いていなければ null */
  description: string | null;
  file: string;
  descriptionAddress: Address;
};

export type MacroSnapshot = ItemHeader & {
  /** preset: のマクロの元のアプリのアイコン */
  icon: string | null;
  /** preset: の名前（sequence で書いていれば null） */
  preset: string | null;
  presetAddress: Address | null;
  /** 手順を 1 行ずつ（keycode/inspect の説明の手順の行と同じ文） */
  summary: string[];
  /** sequence の手順（preset で書いていれば []） */
  steps: MacroStepSnapshot[];
};

export type TapDanceSnapshot = ItemHeader & {
  actions: { tap: KeySlot; hold: KeySlot; doubleTap: KeySlot; tapHold: KeySlot };
  /** 書いていなければ value は null（読み込みでは 250） */
  tappingTerm: ValueSlot<number>;
};

export type ComboSnapshot = ItemHeader & {
  triggersAddress: Address;
  triggers: KeySlot[];
  output: KeySlot;
  /** v0.3: トリガーのキーがすべてそろうレイヤーがある（protocol.md の 13.2。v0.2 のサーバーは返さない） */
  reachable?: boolean;
};

export type ShortcutSnapshot = { name: string; address: Address; value: KeyValue | null };

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
  /** v0.2: 中身の画面（protocol.md の 12.2）。v0.1 のサーバーは返さない */
  macros?: MacroSnapshot[];
  tapDances?: TapDanceSnapshot[];
  combos?: ComboSnapshot[];
  shortcuts?: ShortcutSnapshot[];
  /** v0.5: 未使用の項目（index: のないファイル。protocol.md の 15.1）。v0.4 のサーバーは返さない */
  unused?: UnusedItems;
  /** 保存済みのファイルの検証の結果 */
  diagnostics: Diagnostic[];
};

/** v0.5: 未使用の項目（protocol.md の 15.1）。形は使っている項目と同じで、index だけが null */
export type Unused<T extends { index: number }> = Omit<T, 'index'> & { index: null };

export type UnusedItems = {
  layers: Unused<LayerSnapshot>[];
  macros: Unused<MacroSnapshot>[];
  tapDances: Unused<TapDanceSnapshot>[];
  combos: Unused<ComboSnapshot>[];
};

export type ProfileCloseParams = { profileId: string };

/** v0.1 は layerKey と encoder。macroKey からあとは v0.2（protocol.md の 12.4） */
export type CandidateContext =
  | 'layerKey'
  | 'encoder'
  | 'macroKey'
  | 'tapDanceAction'
  | 'comboTrigger'
  | 'comboOutput'
  | 'shortcutValue';

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
  /** v0.2: macroKey で除くものも出す（既定 false） */
  all?: boolean;
  /** v0.2: この表記と同じ値の候補を除く（タップダンス自身など） */
  exclude?: string;
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
  /** 当てる順の並び。v0.1 の Change（op を省いた set）も AnyChange に入る（12.3） */
  changes: AnyChange[];
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

/** v0.2: 項目の操作（protocol.md の 12.5） */
export type ItemKind = 'macro' | 'tapDance' | 'combo' | 'shortcut';

export type ItemEdit =
  | { op: 'create'; kind: 'macro' | 'tapDance' | 'combo'; name: string; preset?: string; index?: undefined }
  | { op: 'create'; kind: 'shortcut'; name: string; value: string; index?: undefined }
  /** v0.4: レイヤーを足す（protocol.md の 14.9）。index を省けば空いているいちばん小さい番号 */
  | { op: 'create'; kind: 'layer'; name: string; index?: number }
  | { op: 'delete'; kind: ItemKind; name: string }
  | { op: 'rename'; kind: ItemKind; name: string; to: string }
  /** v0.4: レイヤーは名前が重なってよく、番号のないレイヤーも予定している（#85）のでファイルで探す（省けば name。protocol.md の 14.9） */
  | { op: 'delete'; kind: 'layer'; name: string; file?: string }
  | { op: 'rename'; kind: 'layer'; name: string; to: string; file?: string }
  | { op: 'renamePosition'; hand: Hand; row: number; col: number; to: string }
  /** v0.3: preset: のマクロを同梱の定義の手順に置き換える（protocol.md の 13.1） */
  | { op: 'expandPreset'; kind: 'macro'; name: string }
  /** v0.5: 未使用の項目を末尾の番号で使い始める（protocol.md の 15.3。結果は changes） */
  | { op: 'use'; kind: IndexedKind; file: string }
  /** v0.5: 使っている項目の index: を消して未使用にする（15.3。結果は changes） */
  | { op: 'unuse'; kind: IndexedKind; file: string }
  /** v0.5: 番号を変える。index がほかの項目の番号なら入れ替える（15.3。結果は changes） */
  | { op: 'setIndex'; kind: IndexedKind; file: string; index: number }
  /**
   * v0.5: 使っている項目を並べ直す（15.3。結果は changes）。files は使っている項目すべて（未保存の変更を当てた状態）の新しい並び。
   * 今の番号を小さい順に並べて、新しい並びの順に当てる（抜け番はそのまま）。indexes を書けば files の順にその番号を当てる（抜け番を作れる。レイヤーの並び替えモード）
   */
  | { op: 'reorder'; kind: IndexedKind; files: string[]; indexes?: number[] };

/** v0.5: 番号（index:）を持つ種類 */
export type IndexedKind = 'layer' | 'macro' | 'tapDance' | 'combo';

export type PlanItemEditParams = {
  profileId: string;
  /** snapshot.files をそのまま */
  baseVersions: Record<string, FileVersion>;
  edit: ItemEdit;
  /** v0.5: 今の未保存の変更（当てる順の並び）。use / unuse / setIndex / reorder と create（shortcut）は、これを当てた状態で決める（protocol.md の 15.3） */
  changes?: AnyChange[];
};

/** FileEdits に、消す・改名を足したもの */
export type ItemFileEdits = FileEdits & {
  delete?: boolean;
  /** 改名の行き先（設定ディレクトリからの相対パス） */
  renameTo?: string;
};

export type PlanItemEditResult = {
  /** v0.5: use / unuse / setIndex / reorder と create（shortcut）では []（代わりに changes） */
  files: ItemFileEdits[];
  /** v0.5: 未保存の変更に積む Change の並び（use / unuse / setIndex / reorder と create（shortcut）だけ。protocol.md の 15.3） */
  changes?: AnyChange[];
  /** 書き換える（削除・unuse なら壊れる）参照の場所 */
  references: Address[];
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
  'profile/planItemEdit': { params: PlanItemEditParams; result: PlanItemEditResult };
  'features/status': { params: Record<string, never>; result: FeaturesStatusResult };
}

/** 解放されている機能の名前 */
export type FeaturesStatusResult = { unlocked: string[] };

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
  EditNotLocal: { address: Address; reason: 'multiline' | 'anchor' | 'flowInsert' | 'verify' };
};
