// 約束の適合テスト（protocol.md の 8.2）のデータ spec/fixtures/protocol/ を、Ruby の RSpec と同じ読み方で偽のサーバーに流す。
// 読み方と比べ方は spec/support/protocol_fixtures.rb に合わせる（書いた項目だけを比べ、配列は長さと順序ごと）。
// 偽のサーバーが答えるメソッドのディレクトリだけを流す。中身（profile/open の snapshot、候補の並びなど）が固定のデータのメソッドは、
// 応答が error のデータ（params の誤り・知らないプロファイルなど）だけを流す（ERRORS_ONLY）
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { PassThrough } from 'node:stream';
import { describe, expect, it } from 'vitest';
import { readMessages, runFakeServer } from '../fake-server/server';

const REPO = path.resolve(__dirname, '../../../..');
const DIR = path.join(REPO, 'spec/fixtures/protocol');
const SUPPORTED = [
  'lifecycle',
  'profile_list',
  'profile_open',
  'keycode_candidates',
  'keycode_inspect',
  'profile_validate',
  'profile_plan_edits',
  'profile_saved',
  'workspace_did_change_files',
  'profile_plan_item_edit',
];
/** 応答が error のデータだけを流すディレクトリ（keycode_shortcut_tree は error のデータがないので流さない） */
const ERRORS_ONLY = new Set(['profile_open', 'keycode_candidates', 'keycode_inspect', 'profile_validate', 'profile_plan_edits', 'profile_saved', 'profile_plan_item_edit']);
/** 偽のサーバーでは比べない項目（偽のサーバーの implementation は "fake"） */
const IGNORED = new Set(['$.result.serverInfo.implementation']);

type Json = null | boolean | number | string | Json[] | { [key: string]: Json };
type JsonObject = { [key: string]: Json };
type Fixture = {
  description?: string;
  setup?: { initialize?: boolean; profile?: string; profiles?: Record<string, string | null>; files?: Record<string, string | null>; before?: JsonObject[] };
  request?: JsonObject;
  raw?: string;
  response?: JsonObject;
  notifications?: Json[];
};

function message(hash: JsonObject): JsonObject {
  const full: JsonObject = { jsonrpc: '2.0', ...hash };
  if (full.jsonrpc === null) delete full.jsonrpc;
  return full;
}

function prepare(root: string, setup: NonNullable<Fixture['setup']>): void {
  const profiles = { ...(setup.profiles ?? {}) };
  if (setup.profile) profiles['profiles/default'] = setup.profile;
  for (const [dir, source] of Object.entries(profiles)) {
    const dest = path.join(root, dir);
    if (source === null) fs.mkdirSync(dest, { recursive: true });
    else fs.cpSync(path.join(REPO, 'spec/fixtures', source), dest, { recursive: true });
  }
  for (const [rel, text] of Object.entries(setup.files ?? {})) {
    // null は消す（profile で置いたファイルを除くとき）
    if (text === null) {
      fs.rmSync(path.join(root, rel), { force: true });
      continue;
    }
    fs.mkdirSync(path.dirname(path.join(root, rel)), { recursive: true });
    fs.writeFileSync(path.join(root, rel), text);
  }
}

async function run(fixture: Fixture) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'cornix-protocol-'));
  try {
    const setup = fixture.setup ?? {};
    prepare(root, setup);
    const before: JsonObject[] = [];
    if (setup.initialize !== false) {
      before.push(message({ id: 'setup:initialize', method: 'initialize', params: { protocolVersion: '0.4' } }), message({ method: 'initialized' }));
    }
    if (setup.profile) before.push(message({ id: 'setup:open', method: 'profile/open', params: { dir: 'profiles/default' } }));
    before.push(...(setup.before ?? []).map(message));

    const input = new PassThrough();
    const output = new PassThrough();
    const received: JsonObject[] = [];
    runFakeServer(input, output, { root });
    readMessages(output, (m) => received.push(m as JsonObject), () => undefined);
    const frame = (body: string) => {
      const bytes = Buffer.from(body, 'utf-8');
      input.write(Buffer.concat([Buffer.from(`Content-Length: ${bytes.length}\r\n\r\n`), bytes]));
    };
    for (const m of before) frame(JSON.stringify(m));
    frame(fixture.raw ?? JSON.stringify(message(fixture.request ?? {})));
    await new Promise((resolve) => setTimeout(resolve, 20));

    const responses = received.filter((m) => !('method' in m));
    const setupIds = before.map((m) => m.id).filter((id) => id !== undefined);
    const failed = responses.filter((m) => String(m.id).startsWith('setup:') && 'error' in m);
    if (failed.length > 0) throw new Error(`setup のリクエストが失敗しました: ${JSON.stringify(failed)}`);
    const own = responses.filter((m) => !setupIds.includes(m.id as Json));
    const requestId = fixture.request?.id;
    const response = requestId === undefined ? own[0] : own.find((m) => m.id === requestId);
    return { response, extra: own.filter((m) => m !== response), notifications: received.filter((m) => 'method' in m) };
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
}

function mismatches(expected: Json | undefined, actual: Json | undefined, at = '$'): string[] {
  if (IGNORED.has(at)) return [];
  if (Array.isArray(expected)) {
    if (!Array.isArray(actual)) return [`${at}: 配列のはずが ${JSON.stringify(actual)}`];
    if (actual.length !== expected.length) return [`${at}: 長さが ${expected.length} のはずが ${actual.length}（${JSON.stringify(actual)}）`];
    return expected.flatMap((value, i) => mismatches(value, actual[i], `${at}[${i}]`));
  }
  if (expected !== null && typeof expected === 'object') {
    if (actual === null || typeof actual !== 'object' || Array.isArray(actual)) return [`${at}: オブジェクトのはずが ${JSON.stringify(actual)}`];
    return Object.entries(expected).flatMap(([key, value]) =>
      key in actual ? mismatches(value, actual[key], `${at}.${key}`) : [`${at}.${key}: 項目がありません`],
    );
  }
  return expected === actual ? [] : [`${at}: ${JSON.stringify(expected)} のはずが ${JSON.stringify(actual)}`];
}

for (const group of SUPPORTED) {
  const dir = path.join(DIR, group);
  const files = (fs.existsSync(dir) ? fs.readdirSync(dir).filter((f) => f.endsWith('.json')).sort() : []).filter(
    (file) => !ERRORS_ONLY.has(group) || 'error' in ((JSON.parse(fs.readFileSync(path.join(dir, file), 'utf-8')) as Fixture).response ?? {}),
  );
  describe(`適合テスト ${group}（偽のサーバー）`, () => {
    it('データがある', () => expect(files.length).toBeGreaterThan(0));
    for (const file of files) {
      const fixture = JSON.parse(fs.readFileSync(path.join(dir, file), 'utf-8')) as Fixture;
      it(`${file.replace(/\.json$/, '')}: ${fixture.description ?? ''}`, async () => {
        const outcome = await run(fixture);
        if (fixture.response) {
          expect(outcome.response, '応答がありません').toBeDefined();
          expect(mismatches(fixture.response, outcome.response)).toEqual([]);
        } else {
          expect(outcome.response).toBeUndefined();
        }
        expect(outcome.extra).toEqual([]);
        if (fixture.notifications) expect(mismatches(fixture.notifications, outcome.notifications as Json[])).toEqual([]);
      });
    }
  });
}
