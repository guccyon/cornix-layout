// テスト用の偽のサーバー。protocol.md の例を元にしたデータ（fixtures.ts）を、`cornix serve` と同じ枠（Content-Length）と約束で返す。
// Ruby のサーバーがなくても画面の作業と統合テストを進めるためのもの。枠は vscode-jsonrpc を使わずに自前で読み書きし、拡張の側の枠の扱いも確かめる。
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
  type Change,
  type Diagnostic,
  type DidChangeFilesParams,
  type DraftParams,
  type FileEdits,
  type FileVersion,
  type ProfileListResult,
  type ProfileSnapshot,
  type TextEdit,
} from '../../src/protocol';
import * as data from './fixtures';

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

/** 通知で送るメソッド（id 付きで来たら -32600） */
const NOTIFICATION_METHODS = new Set(['initialized', 'exit', 'profile/close', 'workspace/didChangeFiles', '$/cancelRequest']);

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

  constructor(
    private readonly options: FakeServerOptions,
    private readonly send: (message: Message) => void,
  ) {}

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
      this.send({ jsonrpc: '2.0', id, result });
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
        return;
      case 'workspace/didChangeFiles':
        this.didChangeFiles(params as DidChangeFilesParams);
        return;
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
        return this.snapshot(profileId);
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
        const p = params as DraftParams;
        this.checkDraft(p);
        return { diagnostics: this.validate(p.changes) };
      }
      case 'profile/planEdits': {
        const p = params as DraftParams;
        this.checkDraft(p);
        return { files: this.planEdits(p), diagnostics: this.validate(p.changes) };
      }
      case 'profile/saved': {
        const p = params as { profileId: string; files: Record<string, FileVersion> };
        this.profile(p.profileId);
        return this.snapshot(p.profileId);
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

  private snapshot(profileId: string): ProfileSnapshot {
    const { dir, name } = this.profile(profileId);
    const files = this.files(dir);
    if (this.options.scenario === 'invalid') {
      return {
        profileId,
        name,
        dir,
        status: 'invalid',
        files,
        metadata: {},
        positionMap: [],
        layers: [],
        settings: [],
        references: { layers: [], macros: [], tapDances: [], shortcuts: [] },
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
    return {
      profileId,
      name,
      dir,
      status: 'ok',
      files,
      metadata: data.METADATA,
      positionMap: data.POSITION_MAP,
      layers: data.LAYERS,
      settings: data.SETTINGS,
      references: data.REFERENCES,
      diagnostics: [
        {
          severity: 'warning',
          source: 'semantic',
          message: 'Cornix は Repeat Key に対応していません（偽のサーバーの例）',
          file: 'layers/1_symbols.yml',
        },
      ],
    };
  }

  /** 設定ディレクトリがディスクにあればその YAML の版、なければ fixtures の名前と仮の版 */
  private files(dir: string): Record<string, FileVersion> {
    const base = path.resolve(this.options.root, dir);
    if (!fs.existsSync(base)) {
      return Object.fromEntries(data.FALLBACK_FILES.map((file) => [file, `sha256:${'0'.repeat(64)}`]));
    }
    const result: Record<string, FileVersion> = {};
    for (const rel of walk(base)) result[rel] = versionOf(fs.readFileSync(path.join(base, rel)));
    return result;
  }

  private candidates(context: string, query: string, limit: number) {
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
    return { items: items.slice(0, limit), typed: query ? data.interpret(query) : null, truncated: items.length > limit };
  }

  private checkDraft(params: DraftParams): void {
    const { dir } = this.profile(params.profileId);
    const current = this.files(dir);
    const conflicts = Object.entries(params.baseVersions ?? {}).filter(([file, version]) => file in current && current[file] !== version);
    if (conflicts.length > 0) {
      throw new RpcError(ErrorCodes.VersionConflict, 'ファイルが外で変わっています', {
        files: Object.fromEntries(conflicts.map(([file]) => [file, current[file] ?? null])),
      });
    }
  }

  private validate(changes: Change[]): Diagnostic[] {
    return changes.flatMap((change): Diagnostic[] => {
      if (typeof change.value !== 'string') return [];
      const macro = /^Macro\((\d+)\)$/.exec(change.value);
      if (macro) {
        return [{ severity: 'error', source: 'semantic', message: `マクロ M${macro[1]} が定義されていません`, address: change.address }];
      }
      return data.interpret(change.value) ? [] : [{ ...unreadable(change.value), address: change.address }];
    });
  }

  /**
   * ディスクのファイルの行を素朴にたどって値の部分を置き換える（ブロック形式の `キー: 値` だけ）。
   * Ruby のサーバーの書き換え（Storage::YamlDocument）の代わりではなく、保存の流れを試すためのもの。
   */
  private planEdits(params: DraftParams): FileEdits[] {
    const { dir } = this.profile(params.profileId);
    const byFile = new Map<string, Change[]>();
    for (const change of params.changes) byFile.set(change.address.file, [...(byFile.get(change.address.file) ?? []), change]);
    return [...byFile].map(([file, changes]) => {
      const full = path.resolve(this.options.root, dir, file);
      if (!fs.existsSync(full)) {
        throw new RpcError(ErrorCodes.EditNotLocal, `${file} がないので書き換えられません（偽のサーバー）`, { address: changes[0]?.address, reason: 'flowInsert' });
      }
      const lines = fs.readFileSync(full, 'utf-8').split('\n');
      const edits: TextEdit[] = changes.map((change) => {
        const range = findValue(lines, change.address.path);
        if (!range) {
          throw new RpcError(ErrorCodes.EditNotLocal, `${file} の ${change.address.path.join('.')} は書き換えられません（偽のサーバー）`, {
            address: change.address,
            reason: 'flowInsert',
          });
        }
        return { range, newText: quote(String(change.value)) };
      });
      return { file, baseVersion: versionOf(fs.readFileSync(full)), create: false, edits };
    });
  }

  private didChangeFiles(params: DidChangeFilesParams): void {
    for (const [profileId, profile] of this.profiles) {
      const base = path.resolve(this.options.root, profile.dir);
      const files: Record<string, FileVersion> = {};
      for (const change of params.changes ?? []) {
        const full = path.resolve(this.options.root, change.path);
        const rel = path.relative(base, full);
        if (rel === '..' || rel.startsWith(`..${path.sep}`) || path.isAbsolute(rel)) continue;
        files[rel.split(path.sep).join('/')] = fs.existsSync(full) ? versionOf(fs.readFileSync(full)) : null;
      }
      if (Object.keys(files).length === 0) continue;
      this.send({ jsonrpc: '2.0', method: 'profile/didChange', params: { profileId, files, snapshot: this.snapshot(profileId) } });
    }
  }

  private log(line: string): void {
    this.options.log?.(`[fake-cornix] ${line}`);
  }
}

/** keycode/candidates の limit を省いたときの数（protocol.md の 5.3） */
const DEFAULT_LIMIT = 50;
/** v0.1 の context（protocol.md の 5.3） */
const CONTEXTS = new Set(['layerKey', 'encoder']);

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

function walk(base: string, rel = ''): string[] {
  return fs.readdirSync(path.join(base, rel), { withFileTypes: true }).flatMap((entry) => {
    const child = rel ? `${rel}/${entry.name}` : entry.name;
    if (entry.isDirectory()) return walk(base, child);
    return /\.ya?ml$/.test(entry.name) ? [child] : [];
  });
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

function quote(value: string): string {
  return /^[\w()' +\-]+$/u.test(value) && !/^[-?:,]/.test(value) ? value : JSON.stringify(value);
}

function escapeRegExp(text: string): string {
  return text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}
