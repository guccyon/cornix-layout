// テスト用の偽のサーバー。protocol.md の例を元にしたデータ（fixtures.ts）を、`cornix serve` と同じ枠（Content-Length）と約束で返す。
// Ruby のサーバーがなくても画面の作業と統合テストを進めるためのもの。枠は vscode-jsonrpc を使わずに自前で読み書きし、拡張の側の枠の扱いも確かめる。
// ディスクに設定ディレクトリがあれば、レイヤーのキー・エンコーダと QMK 設定の値はファイルの `キー: 値` の行から読む（ほかは fixtures の固定のデータ）。
// 開いたプロファイルごとに「知っている版」を持ち、workspace/didChangeFiles と profile/saved で版が違えば profile/didChange を送る（protocol.md の 6.4・7.2）。
//
// わざと崩すための環境変数（main.ts が読む）:
//   CORNIX_FAKE_SCENARIO=invalid   profile/open が status: "invalid" のプロファイルを返す
//   CORNIX_FAKE_EXIT_ON=<メソッド>  そのリクエストが来たら終了コード 3 で落ちる（再起動の確認用）
import * as crypto from 'node:crypto';
import * as fs from 'node:fs';
import * as path from 'node:path';
import type { Readable, Writable } from 'node:stream';
import {
  ErrorCodes,
  PROTOCOL_VERSION,
  type Address,
  type AnyChange,
  type ComboSnapshot,
  type Diagnostic,
  type ItemEdit,
  type ItemFileEdits,
  type MacroSnapshot,
  type PlanItemEditResult,
  type ShortcutSnapshot,
  type TapDanceSnapshot,
  type DidChangeFilesParams,
  type DraftParams,
  type FileEdits,
  type FileVersion,
  type KeyValue,
  type LayerSnapshot,
  type ProfileListResult,
  type QmkSettingSnapshot,
  type ProfileSnapshot,
  type TextEdit,
} from '../../src/protocol';
import * as data from './fixtures';
import { NotLocal, applyChange, quote } from './yamlLines';

/** 偽のサーバーの profile/validate・planEdits の params（changes は v0.2 の AnyChange。protocol.md の 12.3） */
type Draft = DraftParams;

/** 名前の変更でこの名前にすると、compile の照合に失敗したことにする（-32061 の reason "verify" を試すため） */
export const VERIFY_FAIL_NAME = 'VerifyFail';

export type FakeServerOptions = {
  /** ワークスペースのフォルダ（--root） */
  root: string;
  scenario?: 'default' | 'invalid';
  exitOn?: string;
  /** ログ（標準エラー出力） */
  log?: (line: string) => void;
  /** exit の通知・exitOn で呼ぶ */
  onExit?: (code: number) => void;
  /** 受け付ける約束の版（既定は拡張と同じ版だけ）。版の食い違いを試すときに差し替える */
  supportedVersions?: string[];
  /** initialize の result に入れる版（既定は受け付けた版）。違う版を返すサーバーを試すとき */
  respondVersion?: string;
};

/**
 * テストが偽のサーバーの振る舞いを途中で変える通知（偽のサーバーだけのもの。Ruby のサーバーは `$/` の通知を捨てる）。
 * params: { scenario?: 'default' | 'invalid'; delays?: { [method]: ミリ秒 } }（delays はそのメソッドの応答を遅らせる。保存の途中を作るため）
 */
export const FAKE_CONFIGURE = '$/fake/configure';

/** 通知で送るメソッド（id 付きで来たら -32600） */
const NOTIFICATION_METHODS = new Set(['initialized', 'exit', 'profile/close', 'workspace/didChangeFiles', '$/cancelRequest', FAKE_CONFIGURE]);

type Message = {
  jsonrpc?: string;
  id?: number | string | null;
  method?: string;
  params?: unknown;
  result?: unknown;
  error?: unknown;
};

class RpcError extends Error {
  constructor(
    readonly code: number,
    message: string,
    readonly data?: unknown,
  ) {
    super(message);
  }
}

export function runFakeServer(input: Readable, output: Writable, options: FakeServerOptions): void {
  const server = new FakeServer(options, (message) => writeMessage(output, message));
  readMessages(input, (message) => server.handle(message), (error) => {
    writeMessage(output, { jsonrpc: '2.0', id: null, error: { code: ErrorCodes.ParseError, message: error.message } });
  });
}

// ---------------------------------------------------------------------------
// 枠（Content-Length: <バイト数>\r\n\r\n<JSON>）
// ---------------------------------------------------------------------------

export function writeMessage(output: Writable, message: Message): void {
  const body = Buffer.from(JSON.stringify(message), 'utf-8');
  output.write(Buffer.concat([Buffer.from(`Content-Length: ${body.length}\r\n\r\n`, 'ascii'), body]));
}

export function readMessages(input: Readable, onMessage: (message: unknown) => void, onError: (error: Error) => void): void {
  let buffer = Buffer.alloc(0);
  input.on('data', (chunk: Buffer) => {
    buffer = Buffer.concat([buffer, chunk]);
    for (;;) {
      const headerEnd = buffer.indexOf('\r\n\r\n');
      if (headerEnd < 0) return;
      const header = buffer.subarray(0, headerEnd).toString('ascii');
      const match = /Content-Length: *(\d+)/i.exec(header);
      if (!match?.[1]) {
        buffer = buffer.subarray(headerEnd + 4);
        onError(new Error('Content-Length がありません'));
        continue;
      }
      const length = Number(match[1]);
      const start = headerEnd + 4;
      if (buffer.length < start + length) return;
      const body = buffer.subarray(start, start + length).toString('utf-8');
      buffer = buffer.subarray(start + length);
      let message: unknown;
      try {
        message = JSON.parse(body) as unknown;
      } catch {
        onError(new Error('JSON として読めません'));
        continue;
      }
      onMessage(message);
    }
  });
}

// ---------------------------------------------------------------------------
// 振り分け
// ---------------------------------------------------------------------------

class FakeServer {
  private state: 'new' | 'initialized' | 'shutdown' = 'new';
  private nextProfile = 1;
  private readonly profiles = new Map<string, { dir: string; name: string }>();
  /** 開いたプロファイルの「知っている版」（profile/open・profile/saved・profile/didChange で覚えた版） */
  private readonly known = new Map<string, Record<string, FileVersion>>();
  private scenario: 'default' | 'invalid';
  private delays: Record<string, number> = {};

  constructor(
    private readonly options: FakeServerOptions,
    private readonly send: (message: Message) => void,
  ) {
    this.scenario = options.scenario ?? 'default';
  }

  /** protocol.md の 1.・4.・9. と、spec/fixtures/protocol/lifecycle の Ruby のサーバーの振る舞いに合わせる */
  handle(raw: unknown): void {
    if (raw === null || typeof raw !== 'object' || Array.isArray(raw)) {
      this.error(null, ErrorCodes.InvalidRequest, 'JSON-RPC の形ではありません（オブジェクトでない・バッチ）');
      return;
    }
    const message = raw as Message;
    const hasId = 'id' in message;
    const id = message.id ?? null;
    const { method } = message;
    if (message.jsonrpc !== '2.0') {
      if (hasId) this.error(id, ErrorCodes.InvalidRequest, 'jsonrpc: "2.0" がありません');
      return;
    }
    if (typeof method !== 'string') {
      // 拡張からの応答（result か error がある）は使わない。それ以外は形の誤り
      if (!('result' in message) && !('error' in message)) this.error(id, ErrorCodes.InvalidRequest, 'method がありません');
      return;
    }
    this.log(`← ${method}`);
    if (method === this.options.exitOn) {
      this.log(`${method} が来たので落ちます（CORNIX_FAKE_EXIT_ON）`);
      this.options.onExit?.(3);
      return;
    }
    if (!hasId) {
      // リクエストで送るメソッドを通知で送っても実行しない
      if (NOTIFICATION_METHODS.has(method)) this.notification(method, message.params);
      return;
    }
    if (NOTIFICATION_METHODS.has(method)) {
      this.error(id, ErrorCodes.InvalidRequest, `${method} は通知で送るメソッドです`);
      return;
    }
    const { params } = message;
    if (params !== undefined && (params === null || typeof params !== 'object' || Array.isArray(params))) {
      this.error(id, ErrorCodes.InvalidParams, 'params がオブジェクトではありません');
      return;
    }
    try {
      const result = this.request(method, params ?? {});
      const delay = this.delays[method];
      if (delay) setTimeout(() => this.send({ jsonrpc: '2.0', id, result }), delay);
      else this.send({ jsonrpc: '2.0', id, result });
    } catch (error) {
      if (error instanceof RpcError) this.error(id, error.code, error.message, error.data);
      else this.error(id, ErrorCodes.InternalError, String(error));
    }
  }

  private error(id: Message['id'], code: number, message: string, data?: unknown): void {
    this.send({ jsonrpc: '2.0', id: id ?? null, error: { code, message, ...(data === undefined ? {} : { data }) } });
  }

  private notification(method: string, params: unknown): void {
    switch (method) {
      case 'initialized':
        return;
      case 'exit':
        this.options.onExit?.(this.state === 'shutdown' ? 0 : 1);
        return;
      case 'profile/close':
        this.profiles.delete((params as { profileId?: string } | undefined)?.profileId ?? '');
        this.known.delete((params as { profileId?: string } | undefined)?.profileId ?? '');
        return;
      case 'workspace/didChangeFiles':
        this.didChangeFiles(params as DidChangeFilesParams);
        return;
      case FAKE_CONFIGURE: {
        const p = (params ?? {}) as { scenario?: 'default' | 'invalid'; delays?: Record<string, number> };
        if (p.scenario) this.scenario = p.scenario;
        if (p.delays) this.delays = p.delays;
        return;
      }
      default:
        // 知らない通知は捨てる（$/cancelRequest も v0.1 では何もしない）
        return;
    }
  }

  private request(method: string, params: unknown): unknown {
    if (this.state === 'shutdown') throw new RpcError(ErrorCodes.InvalidRequest, 'shutdown のあとのリクエストです');
    if (method === 'initialize') {
      if (this.state !== 'new') throw new RpcError(ErrorCodes.InvalidRequest, 'initialize は 1 回だけです');
      return this.initialize(params as { protocolVersion?: unknown });
    }
    if (this.state !== 'initialized') throw new RpcError(ErrorCodes.ServerNotInitialized, 'initialize の前のリクエストです');

    switch (method) {
      case 'shutdown':
        this.state = 'shutdown';
        return null;
      case 'profile/list':
        return this.listProfiles();
      case 'profile/open': {
        const dir = (params as { dir?: unknown } | undefined)?.dir;
        if (typeof dir !== 'string') throw new RpcError(ErrorCodes.InvalidParams, 'dir がありません', { field: 'dir' });
        const summary =
          this.listProfiles().profiles.find((profile) => profile.dir === dir) ??
          (hasEntries(path.resolve(this.options.root, dir)) ? { dir, name: path.basename(dir) } : undefined);
        if (!summary) throw new RpcError(ErrorCodes.ProfileNotFound, `プロファイル ${dir} が見つかりません`, { dir });
        const profileId = `p${this.nextProfile++}`;
        this.profiles.set(profileId, summary);
        return this.remember(this.snapshot(profileId));
      }
      case 'keycode/candidates': {
        const p = params as { profileId?: unknown; context?: unknown; query?: string; limit?: number };
        requireString(p, 'profileId');
        const context = requireString(p, 'context');
        this.profile(p.profileId as string);
        checkContext(context);
        return this.candidates(context, p.query ?? '', p.limit ?? DEFAULT_LIMIT);
      }
      case 'keycode/shortcutTree':
        return data.SHORTCUT_TREE;
      case 'keycode/inspect': {
        const p = params as { profileId?: unknown; context?: unknown; text?: unknown };
        requireString(p, 'profileId');
        const context = requireString(p, 'context');
        requireString(p, 'text');
        this.profile(p.profileId as string);
        checkContext(context);
        const value = data.interpret(p.text as string);
        return {
          value,
          diagnostics: value ? [] : [unreadable(p.text as string)],
          description: value ? data.describe(value) : null,
        };
      }
      case 'profile/validate': {
        const p = this.checkDraft(params);
        this.planEdits(p); // 書き換えられない変更は validate でも -32061
        return { diagnostics: this.validate(p.profileId, p.changes) };
      }
      case 'profile/planEdits': {
        const p = this.checkDraft(params);
        return { files: this.planEdits(p), diagnostics: this.validate(p.profileId, p.changes) };
      }
      case 'profile/planItemEdit':
        return this.planItemEdit(params as Record<string, unknown>);
      case 'profile/saved': {
        const p = params as { profileId: string; files: Record<string, FileVersion> };
        requireString(p, 'profileId');
        this.profile(p.profileId);
        if (p.files === null || typeof p.files !== 'object' || Array.isArray(p.files)) {
          throw new RpcError(ErrorCodes.InvalidParams, 'files の形が違います', { field: 'files' });
        }
        // 知っている版に知らされた版を重ねたものと、読み直した版を全部比べる（#41 と同じ。知らされていないファイルの外での変更も知らせる）
        const expected: Record<string, FileVersion> = { ...(this.known.get(p.profileId) ?? {}), ...p.files };
        const snapshot = this.remember(this.snapshot(p.profileId));
        const changed: Record<string, FileVersion> = {};
        for (const file of new Set([...Object.keys(expected), ...Object.keys(snapshot.files)])) {
          if ((expected[file] ?? null) !== (snapshot.files[file] ?? null)) changed[file] = snapshot.files[file] ?? null;
        }
        if (Object.keys(changed).length > 0) {
          this.send({ jsonrpc: '2.0', method: 'profile/didChange', params: { profileId: p.profileId, files: changed, snapshot } });
        }
        return snapshot;
      }
      default:
        throw new RpcError(ErrorCodes.MethodNotFound, `知らないメソッドです: ${method}`);
    }
  }

  private initialize(params: { protocolVersion?: unknown }) {
    if (typeof params.protocolVersion !== 'string') {
      throw new RpcError(ErrorCodes.InvalidParams, 'protocolVersion がありません', { field: 'protocolVersion' });
    }
    const supported = this.options.supportedVersions ?? [PROTOCOL_VERSION];
    if (!supported.includes(params.protocolVersion)) {
      throw new RpcError(ErrorCodes.ProtocolVersionMismatch, `約束の版 ${params.protocolVersion} には対応していません`, { supported });
    }
    this.state = 'initialized';
    return {
      protocolVersion: this.options.respondVersion ?? params.protocolVersion,
      serverInfo: { name: 'cornix', version: data.SERVER_VERSION, implementation: 'fake' },
      capabilities: { semanticValidation: true, keycodeCode: true },
    };
  }

  /**
   * ワークスペースのプロファイルの一覧（protocol.md の 5.1）。Ruby の ListProfiles と同じ順と既定を素朴にまねる:
   * profiles/ の下を名前の順 → .cornix.yml の config: が指すディレクトリ → 中身のある config/。
   * 既定は .cornix.yml の profile: / config:、なければ config。そのディレクトリに中身がなければ null
   */
  private listProfiles(): ProfileListResult {
    const root = this.options.root;
    const profiles: ProfileListResult['profiles'] = [];
    const add = (dir: string) => {
      if (!profiles.some((profile) => profile.dir === dir)) profiles.push({ dir, name: path.basename(dir) });
    };
    const profilesDir = path.join(root, 'profiles');
    if (fs.existsSync(profilesDir)) {
      for (const entry of fs.readdirSync(profilesDir, { withFileTypes: true }).filter((e) => e.isDirectory()).map((e) => e.name).sort()) {
        add(`profiles/${entry}`);
      }
    }
    const settings = readCornixYml(root);
    if (settings.config && hasEntries(path.resolve(root, settings.config))) add(settings.config);
    if (hasEntries(path.join(root, 'config'))) add('config');
    const preferred = settings.profile ? `profiles/${settings.profile}` : (settings.config ?? 'config');
    return { profiles, default: hasEntries(path.resolve(root, preferred)) ? preferred : null };
  }

  private profile(profileId: string | undefined): { dir: string; name: string } {
    const profile = this.profiles.get(profileId ?? '');
    if (!profile) throw new RpcError(ErrorCodes.ProfileNotFound, `プロファイル ${String(profileId)} は開いていません`, { profileId });
    return profile;
  }

  private invalidSnapshot(profileId: string, profile: { dir: string; name: string }, files: Record<string, FileVersion>): ProfileSnapshot {
    return {
      profileId,
      name: profile.name,
      dir: profile.dir,
      status: 'invalid',
      files,
      metadata: {},
      positionMap: [],
      layers: [],
      settings: [],
      references: { layers: [], macros: [], tapDances: [], shortcuts: [] },
      diagnostics: [],
    };
  }

  /** snapshot の版を「知っている版」にする */
  private remember(snapshot: ProfileSnapshot): ProfileSnapshot {
    this.known.set(snapshot.profileId, snapshot.files);
    return snapshot;
  }

  private snapshot(profileId: string): ProfileSnapshot {
    const { dir, name } = this.profile(profileId);
    const files = this.files(dir);
    const base = path.resolve(this.options.root, dir);
    if (this.scenario === 'invalid') {
      return {
        ...this.invalidSnapshot(profileId, { dir, name }, files),
        diagnostics: [
          {
            severity: 'error',
            source: 'structure',
            message: "「Macro('Removed')」は読めない表記です（定義のないマクロ）",
            address: { file: 'layers/0_base.yml', path: ['mapping', 'left_hand', 'row0', 'tab'] },
            range: { start: { line: 7, character: 11 }, end: { line: 7, character: 28 } },
          },
        ],
      };
    }
    const layers = data.LAYERS.flatMap((layer) => layerFromDisk(base, layer) ?? []);
    const items = itemsFromDisk(base);
    return {
      profileId,
      name,
      dir,
      status: 'ok',
      files,
      metadata: data.METADATA,
      positionMap: data.POSITION_MAP,
      layers,
      settings: settingsFromDisk(base, data.SETTINGS),
      references: {
        layers: layers.map((layer) => ({ index: layer.index, name: layer.name })),
        macros: items.macros.map((m) => ({ index: m.index, name: m.name, icon: m.icon })),
        tapDances: items.tapDances.map((t) => ({ index: t.index, name: t.name })),
        shortcuts: items.shortcuts.map((s) => ({ name: s.name, text: s.value?.text ?? '' })),
      },
      ...items,
      diagnostics: [...BASE_DIAGNOSTICS],
    };
  }

  /**
   * 設定ディレクトリがディスクにあればその設定ファイルの版、なければ fixtures の名前と仮の版（protocol.md の 5.2 の files）。
   * 設定ファイルは metadata / position_map / settings/qmk_settings / shortcuts（.yaml / .yml）と layers/ macros/ tap_dance/ combos/ の YAML。
   * settings/qmk_settings がなければ settings/qmk_settings.yaml を null で入れる
   */
  private files(dir: string): Record<string, FileVersion> {
    const base = path.resolve(this.options.root, dir);
    if (!fs.existsSync(base)) {
      return Object.fromEntries(data.FALLBACK_FILES.map((file) => [file, `sha256:${'0'.repeat(64)}`]));
    }
    const result: Record<string, FileVersion> = {};
    for (const rel of configFiles(base)) result[rel] = versionOf(fs.readFileSync(path.join(base, rel)));
    if (!('settings/qmk_settings.yaml' in result) && !('settings/qmk_settings.yml' in result)) result['settings/qmk_settings.yaml'] = null;
    return result;
  }

  /** limit は 1 未満なら 1。query は前後の空白を除いて当てる（protocol.md の 5.3） */
  private candidates(context: string, rawQuery: string, rawLimit: number) {
    const query = rawQuery.trim();
    const limit = Math.max(1, Math.trunc(rawLimit));
    const q = query.toLowerCase();
    let items = data.CANDIDATES.filter((item) => item.category !== 'raw');
    if (q) {
      items = items.filter((item) =>
        [item.insertText, item.label, item.detail ?? ''].some((text) => text.toLowerCase().includes(q)),
      );
    } else if (context === 'encoder') {
      items = [...items.filter((item) => item.category === 'media' || item.category === 'mouse'), ...items.filter((item) => item.category !== 'media' && item.category !== 'mouse')];
    }
    const rank = (text: string) => (text.toLowerCase() === q ? 0 : text.toLowerCase().startsWith(q) ? 1 : 2);
    items = items
      .map((item, order) => ({ item, order }))
      .sort((a, b) => {
        const warn = Number(!!a.item.warning) - Number(!!b.item.warning);
        if (warn) return warn;
        if (q) {
          const r = Math.min(rank(a.item.label), rank(a.item.insertText)) - Math.min(rank(b.item.label), rank(b.item.insertText));
          if (r) return r;
        }
        return a.order - b.order;
      })
      .map(({ item }) => item);
    if (q.startsWith('0x')) items = [{ insertText: query, label: query, detail: '直接の値', category: 'raw' }, ...items];
    return { items: items.slice(0, limit), typed: typed(query, rawQuery), truncated: items.length > limit };
  }

  /**
   * profile/validate・planEdits の params を確かめる。順は #41 の Ruby のサーバーと同じ:
   * params の形（-32602）→ 版の食い違い（-32060）→ 宛先・値の型・baseVersions の抜け（-32602）。書き換えられない（-32061）はそのあと
   */
  private checkDraft(raw: unknown): Draft {
    const params = raw as Record<string, unknown>;
    requireString(params, 'profileId');
    const { dir } = this.profile(params.profileId as string);
    if (params.baseVersions === null || typeof params.baseVersions !== 'object' || Array.isArray(params.baseVersions)) {
      throw new RpcError(ErrorCodes.InvalidParams, 'baseVersions の形が違います', { field: 'baseVersions' });
    }
    if (!Array.isArray(params.changes)) throw new RpcError(ErrorCodes.InvalidParams, 'changes の形が違います', { field: 'changes' });
    params.changes.forEach((change: unknown, index) => {
      const at = `changes[${index}]`;
      const c = change as { op?: unknown; address?: { file?: unknown; path?: unknown }; value?: unknown; index?: unknown; from?: unknown; to?: unknown } | null;
      if (!c || typeof c !== 'object') throw new RpcError(ErrorCodes.InvalidParams, `${at} の形が違います`, { field: at });
      if (!c.address || typeof c.address !== 'object' || typeof c.address.file !== 'string') {
        throw new RpcError(ErrorCodes.InvalidParams, `${at}.address の形が違います`, { field: `${at}.address` });
      }
      if (!Array.isArray(c.address.path) || !c.address.path.every((k) => typeof k === 'string' || typeof k === 'number')) {
        throw new RpcError(ErrorCodes.InvalidParams, `${at}.address.path の形が違います`, { field: `${at}.address.path` });
      }
      const op = c.op ?? 'set';
      if (!['set', 'remove', 'insert', 'move'].includes(op as string)) throw new RpcError(ErrorCodes.InvalidParams, `${at}.op の形が違います`, { field: `${at}.op` });
      if (op === 'set' && !['string', 'number', 'boolean'].includes(typeof c.value)) {
        throw new RpcError(ErrorCodes.InvalidParams, `${at}.value の形が違います`, { field: `${at}.value` });
      }
      if (op === 'insert' && (!Number.isInteger(c.index) || (typeof c.value !== 'string' && (typeof c.value !== 'object' || c.value === null)))) {
        throw new RpcError(ErrorCodes.InvalidParams, `${at} の形が違います`, { field: `${at}.value` });
      }
      if (op === 'move' && (!Number.isInteger(c.from) || !Number.isInteger(c.to))) throw new RpcError(ErrorCodes.InvalidParams, `${at} の形が違います`, { field: `${at}.from` });
    });
    const draft = params as unknown as Draft;
    const current = this.files(dir);
    const conflicts = Object.entries(draft.baseVersions).filter(([file, version]) => file in current && current[file] !== version);
    if (conflicts.length > 0) {
      throw new RpcError(ErrorCodes.VersionConflict, 'ファイルが外で変わっています', {
        files: Object.fromEntries(conflicts.map(([file]) => [file, current[file] ?? null])),
      });
    }
    draft.changes.forEach((change, index) => {
      const at = `changes[${index}]`;
      const setting = data.SETTINGS.find((s) => s.address.file === change.address.file && s.address.path.join('/') === change.address.path.join('/'));
      const content = /^(macros|tap_dance|combos)\//.test(change.address.file) || change.address.file === 'shortcuts.yaml';
      const description = change.address.file.startsWith('layers/') && change.address.path.length === 1 && change.address.path[0] === 'description';
      if (content || description) {
        // v0.2 の中身（protocol.md の 12.2）: ディスクにあるファイルなら宛先として受け付ける（道筋は書き換えるときに確かめる）
        if (!(change.address.file in current)) throw new RpcError(ErrorCodes.InvalidParams, `${at}.address は指せない場所です`, { field: `${at}.address` });
      } else if (change.op !== undefined && change.op !== 'set' && change.op !== 'remove') {
        throw new RpcError(ErrorCodes.InvalidParams, `${at}.address は並びではありません`, { field: `${at}.address` });
      } else if (change.op === 'remove' && setting) {
        throw new RpcError(ErrorCodes.InvalidParams, `${at}.address は消せない場所です`, { field: `${at}.address` });
      } else if (change.op === 'remove') {
        this.checkLayerAddress(change.address, current, at);
      } else if (setting) {
        const ok = setting.type === 'integer' ? Number.isInteger(change.value) : typeof change.value === 'boolean' || change.value === 0 || change.value === 1;
        if (!ok) throw new RpcError(ErrorCodes.InvalidParams, `${setting.name} の値の形が違います`, { field: `${at}.value` });
      } else {
        this.checkLayerAddress(change.address, current, at);
        if (typeof change.value !== 'string') throw new RpcError(ErrorCodes.InvalidParams, `${at}.value はキーの表記の文字列です`, { field: `${at}.value` });
      }
      if (!(change.address.file in draft.baseVersions)) {
        throw new RpcError(ErrorCodes.InvalidParams, `baseVersions に ${change.address.file} がありません`, { field: 'baseVersions' });
      }
    });
    return draft;
  }

  /**
   * profile/planItemEdit（protocol.md の 12.5）。ディスクの設定ディレクトリに対して、素朴に作る。
   * 名前の変更で to を VERIFY_FAIL_NAME にすると -32061（reason "verify"）を返す。
   * v0.3 の expandPreset（13.1）は preset: の行を fixtures の PRESET_SEQUENCES の手順に置き換える
   */
  private planItemEdit(params: Record<string, unknown>): PlanItemEditResult {
    requireString(params, 'profileId');
    const profileId = params.profileId as string;
    const { dir } = this.profile(profileId);
    if (params.baseVersions === null || typeof params.baseVersions !== 'object' || Array.isArray(params.baseVersions)) {
      throw new RpcError(ErrorCodes.InvalidParams, 'baseVersions の形が違います', { field: 'baseVersions' });
    }
    const baseVersions = params.baseVersions as Record<string, FileVersion>;
    const edit = params.edit as ItemEdit | undefined;
    if (!edit || typeof edit !== 'object') throw new RpcError(ErrorCodes.InvalidParams, 'edit の形が違います', { field: 'edit' });
    const base = path.resolve(this.options.root, dir);
    if (!fs.existsSync(base)) throw new RpcError(ErrorCodes.InvalidParams, '設定ディレクトリがディスクにありません（偽のサーバー）', { field: 'edit' });
    const current = this.files(dir);
    const snapshot = this.snapshot(profileId);
    const read = (rel: string) => fs.readFileSync(path.join(base, rel), 'utf-8');
    const invalid = (message: string, field: string): never => {
      throw new RpcError(ErrorCodes.InvalidParams, message, { field });
    };
    const checkName = (name: unknown, field: string): string => {
      if (typeof name !== 'string' || !name || name.trim() !== name) invalid('名前が空か、前後に空白があります', field);
      return name as string;
    };
    const files: ItemFileEdits[] = [];
    const references: Address[] = [];
    const diagnostics: Diagnostic[] = [];
    const editOf = (rel: string): ItemFileEdits => {
      let entry = files.find((f) => f.file === rel);
      if (!entry) {
        entry = { file: rel, baseVersion: current[rel] ?? null, create: false, edits: [] };
        files.push(entry);
      }
      return entry;
    };
    const itemsOf = (kind: string): { name: string; file: string; index: number }[] => {
      if (kind === 'macro') return snapshot.macros ?? [];
      if (kind === 'tapDance') return snapshot.tapDances ?? [];
      if (kind === 'combo') return snapshot.combos ?? [];
      if (kind === 'layer') return snapshot.layers;
      return [];
    };
    const referenceText = (kind: string, name: string) =>
      kind === 'macro' ? `Macro('${name}')` : kind === 'tapDance' ? `TapDance('${name}')` : kind === 'shortcut' ? `Shortcut('${name}')` : undefined;
    const referencesTo = (text: string | undefined): Address[] =>
      text === undefined
        ? []
        : snapshot.layers.flatMap((layer) =>
            [...layer.keys, ...[layer.encoders.left, layer.encoders.right].flatMap((e) => [e.push, e.ccw, e.cw])]
              .filter((slot) => slot.value?.text === text)
              .map((slot) => slot.address),
          );
    const zero = { line: 0, character: 0 };

    switch (edit.op) {
      case 'create': {
        const name = checkName(edit.name, 'edit.name');
        if (edit.kind === 'shortcut') {
          if ((snapshot.shortcuts ?? []).some((s) => s.name === name)) invalid(`ショートカット ${name} はすでにあります`, 'edit.name');
          const line = `  ${quote(name)}: ${quote(edit.value)}\n`;
          if ('shortcuts.yaml' in current) {
            const lines = read('shortcuts.yaml').split('\n');
            const at = { line: lines.at(-1) === '' ? lines.length - 1 : lines.length, character: 0 };
            editOf('shortcuts.yaml').edits.push({ range: { start: at, end: at }, newText: lines.at(-1) === '' ? line : `\n${line}` });
          } else {
            files.push({ file: 'shortcuts.yaml', baseVersion: null, create: true, edits: [{ range: { start: zero, end: zero }, newText: `---\nshortcuts:\n${line}` }] });
          }
          break;
        }
        const folder = { macro: 'macros', tapDance: 'tap_dance', combo: 'combos' }[edit.kind];
        if (!folder) invalid(`知らない種類です: ${String(edit.kind)}`, 'edit.kind');
        const items = itemsOf(edit.kind);
        if (items.some((item) => item.name === name)) invalid(`${name} はすでにあります`, 'edit.name');
        if (edit.kind === 'macro' && edit.preset !== undefined) {
          const presets = data.SHORTCUT_TREE.apps.flatMap((app) => app.categories.flatMap((c) => c.items.filter((i) => i.macro).map((i) => i.insertText)));
          if (!presets.includes(edit.preset)) invalid(`同梱にない preset です: ${edit.preset}`, 'edit.preset');
        }
        let index = 0;
        while (items.some((item) => item.index === index)) index += 1;
        const slugText = slug(name) || { macro: 'macro', tapDance: 'tap_dance', combo: 'combo' }[edit.kind];
        const file = `${folder}/${String(index).padStart(2, '0')}_${slugText}.${extensionIn(base, folder)}`;
        const body =
          edit.kind === 'macro'
            ? edit.preset
              ? `preset: ${quote(edit.preset)}\n`
              : 'sequence:\n- action: tap\n  keys: [KC_NO]\n'
            : edit.kind === 'combo'
              ? 'trigger_keys: [KC_NO, KC_NO]\noutput_key: KC_NO\n'
              : '';
        files.push({ file, baseVersion: null, create: true, edits: [{ range: { start: zero, end: zero }, newText: `---\nname: ${quote(name)}\nindex: ${index}\n${body}` }] });
        break;
      }
      case 'delete': {
        const name = checkName(edit.name, 'edit.name');
        if (edit.kind === 'shortcut') {
          const lines = read('shortcuts.yaml').split('\n');
          const line = lines.findIndex((text) => new RegExp(`^\\s+(["']?)${escapeRegExp(name)}\\1:`).test(text));
          if (line < 0) invalid(`ショートカット ${name} はありません`, 'edit.name');
          editOf('shortcuts.yaml').edits.push({ range: { start: { line, character: 0 }, end: { line: line + 1, character: 0 } }, newText: '' });
        } else {
          const item = itemsOf(edit.kind).find((i) => i.name === name) ?? invalid(`${name} はありません`, 'edit.name');
          files.push({ file: item.file, baseVersion: current[item.file] ?? null, create: false, delete: true, edits: [] });
        }
        references.push(...referencesTo(referenceText(edit.kind, name)));
        for (const address of references) diagnostics.push({ severity: 'error', source: 'structure', message: `「${referenceText(edit.kind, name)}」は読めない表記です（定義がありません）`, address });
        break;
      }
      case 'rename': {
        const name = checkName(edit.name, 'edit.name');
        const to = checkName(edit.to, 'edit.to');
        if (edit.kind === 'shortcut') {
          const shortcuts = snapshot.shortcuts ?? [];
          if (!shortcuts.some((s) => s.name === name)) invalid(`ショートカット ${name} はありません`, 'edit.name');
          if (shortcuts.some((s) => s.name === to)) invalid(`ショートカット ${to} はすでにあります`, 'edit.to');
          // 同梱のショートカットの名前（アプリ:カテゴリ:ラベル）にすると、それを指していた参照の値が変わる（Ruby の照合と同じ結果を素朴にまねる）
          if (to === VERIFY_FAIL_NAME || to.split(':').length === 3) this.verifyFail({ file: 'shortcuts.yaml', path: ['shortcuts', name] });
          const lines = read('shortcuts.yaml').split('\n');
          const line = lines.findIndex((text) => new RegExp(`^\\s+(["']?)${escapeRegExp(name)}\\1:`).test(text));
          const start = indentOfLine(lines[line] ?? '');
          const end = (lines[line] ?? '').indexOf(':', start);
          editOf('shortcuts.yaml').edits.push({ range: { start: { line, character: start }, end: { line, character: end } }, newText: quote(to) });
        } else {
          const items = itemsOf(edit.kind);
          const item = items.find((i) => i.name === name) ?? invalid(`${name} はありません`, 'edit.name');
          if (items.some((i) => i.name === to)) invalid(`${to} はすでにあります`, 'edit.to');
          if (to === VERIFY_FAIL_NAME) this.verifyFail({ file: item.file, path: ['name'] });
          const lines = read(item.file).split('\n');
          const range = findValue(lines, ['name']);
          if (range) editOf(item.file).edits.push({ range, newText: quote(to) });
          const entry = /^(.*\/)?(\d+)_.*?\.(ya?ml)$/.exec(item.file);
          const renameTo = entry ? `${entry[1] ?? ''}${entry[2]}_${slug(to) || 'item'}.${entry[3]}` : undefined;
          if (renameTo && renameTo !== item.file) editOf(item.file).renameTo = renameTo;
        }
        // 参照をテキストとして置き換える（レイヤーのキーとエンコーダだけ）
        const from = referenceText(edit.kind, name);
        const next = referenceText(edit.kind, to);
        for (const address of referencesTo(from)) {
          references.push(address);
          const range = findValue(read(address.file).split('\n'), address.path);
          if (range && next) editOf(address.file).edits.push({ range, newText: quote(next) });
        }
        break;
      }
      case 'renamePosition': {
        if (edit.hand !== 'left' && edit.hand !== 'right') invalid('hand は left か right です', 'edit.hand');
        if (!Number.isInteger(edit.row)) invalid('row は整数です', 'edit.row');
        if (!Number.isInteger(edit.col)) invalid('col は整数です', 'edit.col');
        const to = checkName(edit.to, 'edit.to');
        const entry = data.POSITION_MAP.find((e) => e.hand === edit.hand && e.row === edit.row && e.col === edit.col) ?? invalid('position_map にない位置です', 'edit');
        if (data.POSITION_MAP.some((e) => e.hand === entry.hand && e.group === entry.group && e.symbol === to)) invalid(`${entry.group} に ${to} はすでにあります`, 'edit.to');
        const hand = entry.hand === 'left' ? 'left_hand' : 'right_hand';
        const lines = read('position_map.yaml').split('\n');
        const range = findValue(lines, [hand, entry.group]);
        if (!range) invalid('position_map.yaml にその位置がありません（偽のサーバー）', 'edit');
        const text = textAt(lines, range!);
        const list = text.startsWith('[') ? text.slice(1, -1).split(',').map((s) => s.trim()) : [];
        list[list.indexOf(entry.symbol)] = to;
        editOf('position_map.yaml').edits.push({ range: range!, newText: `[${list.join(', ')}]` });
        for (const layer of snapshot.layers) {
          const layerLines = read(layer.file).split('\n');
          const at = findValue(layerLines, ['mapping', hand, entry.group, entry.symbol]);
          if (!at) continue;
          const keyStart = indentOfLine(layerLines[at.start.line] ?? '');
          const keyEnd = (layerLines[at.start.line] ?? '').indexOf(':', keyStart);
          editOf(layer.file).edits.push({ range: { start: { line: at.start.line, character: keyStart }, end: { line: at.start.line, character: keyEnd } }, newText: to });
          references.push({ file: layer.file, path: ['mapping', hand, entry.group, entry.symbol] });
        }
        break;
      }
      case 'expandPreset': {
        // protocol.md の 13.1: preset: の行を同梱の定義の sequence: に置き換える（ほかの行は変えない）
        const name = checkName(edit.name, 'edit.name');
        if (edit.kind !== 'macro') invalid('kind は macro です', 'edit.kind');
        const item = itemsOf('macro').find((i) => i.name === name) ?? invalid(`${name} はありません`, 'edit.name');
        const lines = read(item.file).split('\n');
        const line = lines.findIndex((text) => /^preset:/.test(text));
        if (line < 0) invalid(`${name} は preset: で書いたマクロではありません`, 'edit.name');
        const preset = unquote(lines[line]!.replace(/^preset:\s*/, '').trim());
        const steps = data.PRESET_SEQUENCES[preset] ?? invalid(`同梱にない preset です: ${preset}`, 'edit.name');
        const sequence = ['sequence:', ...steps.flatMap((step) => [`- action: ${step.action}`, '  keys:', ...step.keys.map((key) => `  - ${key}`)])].join('\n');
        const last = line + 1 >= lines.length;
        const end = last ? { line, character: lines[line]!.length } : { line: line + 1, character: 0 };
        editOf(item.file).edits.push({ range: { start: { line, character: 0 }, end }, newText: last ? sequence : `${sequence}\n` });
        break;
      }
      default:
        invalid('edit.op が違います', 'edit.op');
    }
    // 書き換えるファイルだけ版を比べる（protocol.md の 12.5）。今あるファイルの版が baseVersions になければ -32602
    if (files.some((f) => !f.create && !(f.file in baseVersions))) invalid('書き換えるファイルの版が baseVersions にありません', 'baseVersions');
    const conflicts = files.filter((f) => !f.create && f.file in baseVersions && baseVersions[f.file] !== (current[f.file] ?? null));
    if (conflicts.length > 0) {
      throw new RpcError(ErrorCodes.VersionConflict, 'ファイルが外で変わっています', {
        files: Object.fromEntries(conflicts.map((f) => [f.file, current[f.file] ?? null])),
      });
    }
    return { files, references, diagnostics };
  }

  private verifyFail(address: Address): never {
    throw new RpcError(ErrorCodes.EditNotLocal, '名前を変える前と後で compile の結果が変わります（偽のサーバー）', { address, reason: 'verify' });
  }

  /** レイヤーのキー・エンコーダ: ディスクにあるファイルで、position_map の位置か、エンコーダの操作だけを指せる */
  private checkLayerAddress(address: Address, current: Record<string, FileVersion>, at: string): void {
    const [mapping, hand, group, symbol] = address.path.map(String);
    const handName = hand === 'left_hand' ? 'left' : hand === 'right_hand' ? 'right' : undefined;
    const key = handName && data.POSITION_MAP.some((e) => e.hand === handName && e.group === group && e.symbol === symbol);
    const encoder = hand === 'encoders' && (group === 'left' || group === 'right') && ['push', 'ccw', 'cw'].includes(symbol ?? '');
    if (!(address.file in current) || !address.file.startsWith('layers/') || mapping !== 'mapping' || address.path.length !== 4 || !(key || encoder)) {
      throw new RpcError(ErrorCodes.InvalidParams, `${at}.address は指せない場所です`, { field: `${at}.address` });
    }
  }

  /**
   * 保存済みのファイルの問題（BASE_DIAGNOSTICS）に、変更の値の問題を足す。読めない表記があれば構造の error だけを返す（protocol.md の 5.6）。
   * `Macro(数字)` は定義のないマクロ（意味検証の error）。`MO(9)` にすると、レイヤー 0 の左手 row3 の fn（MO(3)）にも
   * 「ほかの項目にかかる問題」の例として warning を出す（参照している側に出すことを画面で確かめるためのもの）
   */
  private validate(profileId: string, changes: AnyChange[]): Diagnostic[] {
    this.profile(profileId);
    const own = changes.flatMap((change): Diagnostic[] => {
      if (change.op === 'insert' && typeof change.value === 'string') {
        return data.interpret(change.value) ? [] : [{ ...unreadable(change.value), address: change.address }];
      }
      // キーの表記の set だけを確かめる（注記・説明・数値は見ない）
      if ((change.op !== undefined && change.op !== 'set') || change.field === 'note' || typeof change.value !== 'string') return [];
      if (/^(macros|tap_dance|combos)\//.test(change.address.file) && !change.address.path.some((k) => typeof k === 'number' || /^(on_|output_key)/.test(String(k)))) return [];
      if (change.value === 'MO(9)') {
        return [
          { severity: 'error', source: 'semantic', message: 'レイヤー 9 は定義されていません', address: change.address },
          {
            severity: 'warning',
            source: 'semantic',
            message: 'MO(9) と同じレイヤーの切り替えのキーです（偽のサーバーの例）',
            address: { file: 'layers/0_base.yml', path: ['mapping', 'left_hand', 'row3', 'fn'] },
          },
        ];
      }
      const macro = /^Macro\((\d+)\)$/.exec(change.value);
      if (macro) {
        return [{ severity: 'error', source: 'semantic', message: `マクロ M${macro[1]} が定義されていません`, address: change.address }];
      }
      return data.interpret(change.value) ? [] : [{ ...unreadable(change.value), address: change.address }];
    });
    if (own.some((d) => d.source === 'structure')) return own.filter((d) => d.source === 'structure');
    return [...BASE_DIAGNOSTICS, ...own];
  }

  /**
   * ディスクのファイルの行を素朴にたどって値の部分を置き換える（ブロック形式の `キー: 値` だけ）。
   * Ruby のサーバーの書き換え（Storage::YamlDocument）の代わりではなく、保存の流れを試すためのもの。
   */
  private planEdits(params: Draft): FileEdits[] {
    const { dir } = this.profile(params.profileId);
    const byFile = new Map<string, AnyChange[]>();
    for (const change of params.changes) byFile.set(change.address.file, [...(byFile.get(change.address.file) ?? []), change]);
    return [...byFile].map(([file, changes]) => {
      const full = path.resolve(this.options.root, dir, file);
      if (!fs.existsSync(full)) {
        throw new RpcError(ErrorCodes.EditNotLocal, `${file} がないので書き換えられません（偽のサーバー）`, { address: changes[0]?.address, reason: 'flowInsert' });
      }
      const text = fs.readFileSync(full, 'utf-8');
      const baseVersion = versionOf(fs.readFileSync(full));
      const plain = changes.every((c) => (c.op === undefined || c.op === 'set') && c.field !== 'note' && !c.address.path.some((k) => typeof k === 'number'));
      if (!plain) {
        // v0.2 の Change（12.3）: 順に当てたあとの中身で、ファイル全体を 1 つの書き換えにする（偽のサーバーの簡略。Ruby は値の部分だけ）
        const lines = text.split('\n');
        for (const change of changes) {
          try {
            applyChange(lines, change);
          } catch (error) {
            if (!(error instanceof NotLocal)) throw error;
            throw new RpcError(ErrorCodes.EditNotLocal, `${file} の ${change.address.path.join('.')} は書き換えられません（偽のサーバー: ${error.message}）`, {
              address: change.address,
              reason: 'flowInsert',
            });
          }
        }
        const after = lines.join('\n');
        const old = text.split('\n');
        const end = { line: old.length - 1, character: old.at(-1)!.length };
        const edits: TextEdit[] = after === text ? [] : [{ range: { start: { line: 0, character: 0 }, end }, newText: after }];
        return { file, baseVersion, create: false, edits };
      }
      const lines = text.split('\n');
      const edits: TextEdit[] = changes.flatMap((change) => {
        const range = findValue(lines, change.address.path);
        if (!range) {
          throw new RpcError(ErrorCodes.EditNotLocal, `${file} の ${change.address.path.join('.')} は書き換えられません（偽のサーバー）`, {
            address: change.address,
            reason: 'flowInsert',
          });
        }
        const newText = quote(String((change as { value: string | number | boolean }).value));
        // 今の値と同じなら書き換えない（protocol.md の 6.3）
        return textAt(lines, range) === newText ? [] : [{ range, newText }];
      });
      return { file, baseVersion, create: false, edits };
    }).filter((file) => file.edits.length > 0);
  }

  /**
   * 知らせのパスが開いているプロファイルの中なら読み直し、知っている版と違う設定ファイル（足された・消えたものも。知らせのパスに限らない）が
   * あるときだけ profile/didChange を送る（protocol.md の 7.2）。送ったら知っている版を新しくするので、同じ知らせの 2 回目は送らない
   */
  private didChangeFiles(params: DidChangeFilesParams): void {
    for (const [profileId, profile] of this.profiles) {
      const base = path.resolve(this.options.root, profile.dir);
      // 設定ディレクトリの中か、その親（ディレクトリごと消えた・移したとき）を指す知らせなら読み直す
      const related = (params.changes ?? []).some((change) => {
        const target = path.resolve(this.options.root, change.path);
        const rel = path.relative(base, target);
        const inside = !(rel === '..' || rel.startsWith(`..${path.sep}`) || path.isAbsolute(rel));
        const parent = rel === '' || base.startsWith(target + path.sep);
        return inside || parent;
      });
      if (!related) continue;
      const known = this.known.get(profileId) ?? {};
      if (!fs.existsSync(base)) {
        // 設定ディレクトリが消えた: files はすべて null、snapshot は読めない（#41 と同じ）
        if (Object.values(known).every((version) => version === null) && Object.keys(known).length > 0) continue;
        const files = Object.fromEntries(Object.keys(known).map((file) => [file, null]));
        this.known.set(profileId, files);
        const snapshot: ProfileSnapshot = {
          ...this.invalidSnapshot(profileId, profile, files),
          diagnostics: [{ severity: 'error', source: 'structure', message: `設定ディレクトリ ${profile.dir} がありません` }],
        };
        this.send({ jsonrpc: '2.0', method: 'profile/didChange', params: { profileId, files, snapshot } });
        continue;
      }
      const current = this.files(profile.dir);
      const files: Record<string, FileVersion> = {};
      for (const file of new Set([...Object.keys(known), ...Object.keys(current)])) {
        const before = known[file] ?? null;
        const after = current[file] ?? null;
        if (before !== after) files[file] = after;
      }
      if (Object.keys(files).length === 0) continue;
      const snapshot = this.remember(this.snapshot(profileId));
      this.send({ jsonrpc: '2.0', method: 'profile/didChange', params: { profileId, files, snapshot } });
    }
  }

  private log(line: string): void {
    this.options.log?.(`[fake-cornix] ${line}`);
  }
}

/** 保存済みのファイルの検証の結果（偽のサーバーの例。profile/open と profile/validate が返す） */
const BASE_DIAGNOSTICS: Diagnostic[] = [
  {
    severity: 'warning',
    source: 'semantic',
    message: 'Cornix は Repeat Key に対応していません（偽のサーバーの例）',
    file: 'layers/1_symbols.yml',
  },
];

/**
 * レイヤーのキーとエンコーダの値をディスクのファイルから読む（設定ディレクトリがディスクになければ fixtures のまま）。
 * 書いてある表記が fixtures と同じなら fixtures の KeyValue（注記付き）を、違えば読み直した KeyValue を使う
 */
function layerFromDisk(base: string, layer: LayerSnapshot): LayerSnapshot | undefined {
  const full = path.join(base, layer.file);
  // 設定ディレクトリがディスクにあるのにレイヤーのファイルがなければ、そのレイヤーはない
  if (!fs.existsSync(full)) return fs.existsSync(base) ? undefined : layer;
  const lines = fs.readFileSync(full, 'utf-8').split('\n');
  const read = (keyPath: (string | number)[], fixture: KeyValue | null): KeyValue | null => {
    const range = findValue(lines, keyPath);
    if (!range) return null;
    const text = unquote(textAt(lines, range));
    if (fixture && fixture.text === text) return fixture;
    return data.interpret(text) ?? { text, canonical: text, code: null, kind: 'raw', display: { label: text } };
  };
  const encoder = (binding: LayerSnapshot['encoders']['left']) => ({
    push: { ...binding.push, value: read(binding.push.address.path, binding.push.value) },
    ccw: { ...binding.ccw, value: read(binding.ccw.address.path, binding.ccw.value) },
    cw: { ...binding.cw, value: read(binding.cw.address.path, binding.cw.value) },
  });
  return {
    ...layer,
    keys: layer.keys.map((key) => ({ ...key, value: read(key.address.path, key.value) })),
    encoders: { left: encoder(layer.encoders.left), right: encoder(layer.encoders.right) },
  };
}

/** QMK 設定の値をディスクの settings/qmk_settings.yaml から読む（ファイルがなければ fixtures のまま、書いていなければ null） */
function settingsFromDisk(base: string, settings: QmkSettingSnapshot[]): QmkSettingSnapshot[] {
  const full = path.join(base, 'settings/qmk_settings.yaml');
  if (!fs.existsSync(full)) return settings;
  const lines = fs.readFileSync(full, 'utf-8').split('\n');
  return settings.map((setting) => {
    const range = findValue(lines, setting.address.path);
    if (!range) return { ...setting, value: null };
    const text = unquote(textAt(lines, range));
    const value = setting.type === 'boolean' ? text === 'true' || text === '1' : Number(text);
    return { ...setting, value };
  });
}

type Items = Required<Pick<ProfileSnapshot, 'macros' | 'tapDances' | 'combos' | 'shortcuts'>>;

/**
 * マクロ・タップダンス・コンボ・ショートカットの一覧（protocol.md の 12.2）。設定ディレクトリがディスクになければ fixtures のまま。
 * ディスクにあれば、ファイルの一覧と `name:` `index:` の行から作り、fixtures に同じファイル・同じ名前のものがあればその中身を使う
 * （中身はディスクから読まない。追加・削除・名前の変更の流れを試すためのもの）
 */
function itemsFromDisk(base: string): Items {
  if (!fs.existsSync(base)) return { macros: data.MACROS, tapDances: data.TAP_DANCES, combos: data.COMBOS, shortcuts: data.SHORTCUTS };
  const header = (file: string) => ({
    file,
    descriptionAddress: { file, path: ['description'] },
    description: null,
  });
  const macros = readItems(base, 'macros', data.MACROS, (file, name, index): MacroSnapshot => ({
    ...header(file),
    index,
    name,
    icon: null,
    preset: null,
    presetAddress: null,
    summary: [],
    steps: [],
  }));
  const tapDances = readItems(base, 'tap_dance', data.TAP_DANCES, (file, name, index): TapDanceSnapshot => {
    const action = (key: string) => ({ address: { file, path: ['actions', key] }, value: null });
    return {
      ...header(file),
      index,
      name,
      actions: { tap: action('on_tap'), hold: action('on_hold'), doubleTap: action('on_double_tap'), tapHold: action('on_tap_hold') },
      tappingTerm: { address: { file, path: ['tapping_term'] }, value: null },
    };
  });
  const combos = readItems(base, 'combos', data.COMBOS, (file, name, index): ComboSnapshot => ({
    ...header(file),
    index,
    name,
    triggersAddress: { file, path: ['trigger_keys'] },
    triggers: [0, 1].map((i) => ({ address: { file, path: ['trigger_keys', i] }, value: data.interpret('NoKey') })),
    output: { address: { file, path: ['output_key'] }, value: data.interpret('NoKey') },
  }));
  return { macros, tapDances, combos, shortcuts: readShortcuts(base) };
}

function readItems<T extends { file: string; name: string; index: number }>(base: string, dir: string, fixtures: T[], make: (file: string, name: string, index: number) => T): T[] {
  const full = path.join(base, dir);
  if (!fs.existsSync(full)) return [];
  return fs
    .readdirSync(full)
    .filter((name) => /\.ya?ml$/.test(name) && !name.startsWith('.'))
    .sort()
    .map((entry) => {
      const file = `${dir}/${entry}`;
      const text = fs.readFileSync(path.join(full, entry), 'utf-8');
      const name = unquote(/^name:\s*(.*?)\s*$/m.exec(text)?.[1] ?? entry);
      const index = Number(/^index:\s*(\d+)/m.exec(text)?.[1] ?? /^(\d+)/.exec(entry)?.[1] ?? 0);
      const fixture = fixtures.find((item) => item.file === file && item.name === name);
      const item = fixture ?? make(file, name, index);
      // 説明はディスクの値を出す（保存したあとの snapshot で、書いた説明が未保存の変更として残らないように）
      if (!('description' in item)) return item;
      const description = /^description:\s*(.*?)\s*$/m.exec(text)?.[1];
      return { ...item, description: description === undefined ? null : unquote(description) };
    })
    .sort((a, b) => a.index - b.index);
}

/** shortcuts.yaml の `shortcuts:` の下の `名前: 値` の行（ファイルがなければ []） */
function readShortcuts(base: string): ShortcutSnapshot[] {
  const full = path.join(base, 'shortcuts.yaml');
  if (!fs.existsSync(full)) return [];
  const result: ShortcutSnapshot[] = [];
  let inside = false;
  for (const line of fs.readFileSync(full, 'utf-8').split('\n')) {
    if (/^shortcuts:\s*$/.test(line)) {
      inside = true;
      continue;
    }
    if (!inside) continue;
    const match = /^\s+(["']?)(.+?)\1:\s*(.*?)\s*$/.exec(line);
    if (!match) {
      if (line.trim() && !line.startsWith(' ')) inside = false;
      continue;
    }
    const name = match[2]!;
    const text = unquote(match[3]!);
    const value = data.interpret(text) ?? { text, canonical: text, code: null, kind: 'raw' as const, display: { label: text } };
    result.push({ name, address: { file: 'shortcuts.yaml', path: ['shortcuts', name] }, value });
  }
  return result;
}

function textAt(lines: string[], range: { start: { line: number; character: number }; end: { character: number } }): string {
  return (lines[range.start.line] ?? '').slice(range.start.character, range.end.character);
}

function unquote(text: string): string {
  if (/^".*"$/.test(text)) {
    try {
      return JSON.parse(text) as string;
    } catch {
      return text.slice(1, -1);
    }
  }
  if (/^'.*'$/.test(text)) return text.slice(1, -1).replace(/''/g, "'");
  return text;
}

/** keycode/candidates の limit を省いたときの数（protocol.md の 5.3） */
const DEFAULT_LIMIT = 50;
/** context（protocol.md の 5.3 と 12.4）。偽のサーバーは v0.2 の context でも v0.1 と同じ並びで返す */
const CONTEXTS = new Set(['layerKey', 'encoder', 'macroKey', 'tapDanceAction', 'comboTrigger', 'comboOutput', 'shortcutValue']);

/** params の文字列の項目。なければ・文字列でなければ -32602（Ruby のサーバーと同じ data: { field }） */
function requireString(params: Record<string, unknown>, field: string): string {
  const value = params[field];
  if (typeof value !== 'string') {
    throw new RpcError(ErrorCodes.InvalidParams, `params の ${field} ${value === undefined ? 'がありません' : 'の形が違います'}`, { field });
  }
  return value;
}

/** 知らない context は -32602 */
function checkContext(context: string): void {
  if (!CONTEXTS.has(context)) throw new RpcError(ErrorCodes.InvalidParams, `知らない context です: ${context}`, { field: 'context' });
}

function hasEntries(dir: string): boolean {
  try {
    return fs.statSync(dir).isDirectory() && fs.readdirSync(dir).length > 0;
  } catch {
    return false;
  }
}

/** .cornix.yml の `config:` と `profile:` だけを読む（1 行 1 項目の素朴な読み方） */
function readCornixYml(root: string): { config?: string; profile?: string } {
  const file = path.join(root, '.cornix.yml');
  if (!fs.existsSync(file)) return {};
  const result: { config?: string; profile?: string } = {};
  for (const line of fs.readFileSync(file, 'utf-8').split('\n')) {
    const match = /^(config|profile):\s*["']?([^"'#]+?)["']?\s*(#.*)?$/.exec(line);
    if (match?.[1] && match[2]) result[match[1] as 'config' | 'profile'] = match[2];
  }
  return result;
}

function unreadable(text: string): Diagnostic {
  return { severity: 'error', source: 'structure', message: `「${text}」は読めない表記です` };
}

export function versionOf(bytes: Uint8Array): string {
  return `sha256:${crypto.createHash('sha256').update(bytes).digest('hex')}`;
}

/** query（前後の空白を除いたもの）を表記として読めたときの解釈。text は送られた query のまま */
function typed(query: string, rawQuery: string): KeyValue | null {
  const value = query ? data.interpret(query) : null;
  return value ? { ...value, text: rawQuery } : null;
}

const SINGLE_FILES = ['metadata', 'position_map', 'settings/qmk_settings', 'shortcuts'];
const KIND_DIRS = ['layers', 'macros', 'tap_dance', 'combos'];

/** 設定ファイルの構成のファイル（Ruby の Storage::FileSource::Memory.capture と同じ並び） */
function configFiles(base: string): string[] {
  const singles = SINGLE_FILES.flatMap((name) => ['.yaml', '.yml'].map((ext) => `${name}${ext}`)).filter((rel) =>
    fs.existsSync(path.join(base, rel)),
  );
  const kinds = KIND_DIRS.flatMap((dir) => {
    const full = path.join(base, dir);
    if (!fs.existsSync(full)) return [];
    return fs
      .readdirSync(full, { withFileTypes: true })
      .filter((entry) => entry.isFile() && /\.ya?ml$/.test(entry.name) && !entry.name.startsWith('.'))
      .map((entry) => `${dir}/${entry.name}`)
      .sort();
  });
  return [...singles, ...kinds];
}

function findValue(lines: string[], keyPath: (string | number)[]) {
  let line = -1;
  let indent = -1;
  for (const key of keyPath) {
    const pattern = new RegExp(`^(\\s*)(["']?)${escapeRegExp(String(key))}\\2\\s*:`);
    let found = -1;
    for (let i = line + 1; i < lines.length; i++) {
      const text = lines[i] ?? '';
      const lineIndent = text.length - text.trimStart().length;
      if (text.trim() && lineIndent <= indent) break;
      if (pattern.test(text)) {
        found = i;
        indent = lineIndent;
        break;
      }
    }
    if (found < 0) return null;
    line = found;
  }
  const text = lines[line] ?? '';
  const colon = text.indexOf(':', indent);
  const valueStart = text.slice(colon + 1).search(/\S/);
  if (valueStart < 0) return null;
  const start = colon + 1 + valueStart;
  const comment = text.indexOf(' #', start);
  const raw = text.slice(start, comment < 0 ? undefined : comment);
  const end = start + raw.trimEnd().length;
  return { start: { line, character: start }, end: { line, character: end } };
}

/** ファイル名の slug（ASCII の英数字を小文字にして、ほかを _ にまとめたもの。protocol.md の 12.5） */
function slug(name: string): string {
  return name
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '');
}

/** そのディレクトリでいちばん多い拡張子（なければ yaml） */
function extensionIn(base: string, folder: string): string {
  const full = path.join(base, folder);
  const names = fs.existsSync(full) ? fs.readdirSync(full) : [];
  const yml = names.filter((n) => n.endsWith('.yml')).length;
  const yaml = names.filter((n) => n.endsWith('.yaml')).length;
  return yml === 0 && yaml === 0 ? 'yaml' : yml >= yaml ? 'yml' : 'yaml';
}

function indentOfLine(line: string): number {
  return line.length - line.trimStart().length;
}

function escapeRegExp(text: string): string {
  return text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}
