// 画面の部品のテスト用の HostClient。偽のサーバーのデータ（test/fake-server/fixtures.ts）で候補と解釈を返す。
// 返事を止めておいて（hold）、好きな順で返す（release）こともできる。
import type { AnyChange, CandidatesResult, Change, ItemEdit, KeyValue, ProfileSnapshot, Range } from '../../../src/protocol';
import type { HostClient } from '../../../src/webview/hostClient';
import type { WebviewRequestMap, WebviewRequestMethod } from '../../../src/webviewMessages';
import * as data from '../../fake-server/fixtures';

type Call = { method: WebviewRequestMethod; params: unknown; resolve: () => void };

export class FakeHost implements HostClient {
  readonly requests: { method: WebviewRequestMethod; params: unknown }[] = [];
  readonly changes: Change[] = [];
  readonly edits: AnyChange[] = [];
  readonly itemEdits: ItemEdit[] = [];
  readonly opened: { file: string; range?: Range }[] = [];
  /** true の間は返事を溜める */
  holding = false;
  /** 候補をいくつで切るか（サーバーの limit の代わり） */
  limit = 50;
  /** 候補の結果を差し替える（並びを決めたいとき） */
  candidates: CandidatesResult | undefined;
  /** 解釈の結果を表記ごとに差し替える（偽のサーバーのデータにない値を返したいとき） */
  readonly values = new Map<string, KeyValue>();
  private readonly held: Call[] = [];

  request<M extends WebviewRequestMethod>(method: M, params: WebviewRequestMap[M]['params']): Promise<WebviewRequestMap[M]['result']> {
    this.requests.push({ method, params });
    const result = (method === 'keycode/candidates' && this.candidates ? this.candidates : answer(method, params, this.limit, this.values)) as WebviewRequestMap[M]['result'];
    if (!this.holding) return Promise.resolve(result);
    return new Promise((resolve) => this.held.push({ method, params, resolve: () => resolve(result) }));
  }

  change(change: Change): void {
    this.changes.push(change);
  }

  edit(change: AnyChange): void {
    this.edits.push(change);
  }

  itemEdit(edit: ItemEdit): void {
    this.itemEdits.push(edit);
  }

  openFile(file: string, range?: Range): void {
    this.opened.push(range ? { file, range } : { file });
  }

  /** 溜めた返事の i 番目を返す */
  release(index: number): void {
    const [call] = this.held.splice(index, 1);
    call?.resolve();
  }

  get heldCount(): number {
    return this.held.length;
  }
}

function answer(method: WebviewRequestMethod, params: unknown, limit: number, values: ReadonlyMap<string, KeyValue>): unknown {
  if (method === 'keycode/inspect') {
    const { text } = params as { text: string };
    const value = values.get(text) ?? data.interpret(text);
    return {
      value,
      diagnostics: value ? [] : [{ severity: 'error', source: 'structure', message: `「${text}」は読めない表記です` }],
      description: value ? data.describe(value) : null,
    };
  }
  const { query } = params as { query: string };
  const q = query.toLowerCase();
  const items = data.CANDIDATES.filter((c) => !q || [c.insertText, c.label, c.detail ?? ''].some((t) => t.toLowerCase().includes(q)));
  return { items: items.slice(0, limit), typed: query ? data.interpret(query) : null, truncated: items.length > limit };
}

export function fixtureSnapshot(overrides: Partial<ProfileSnapshot> = {}): ProfileSnapshot {
  return {
    profileId: 'p1',
    name: 'default',
    dir: 'profiles/default',
    status: 'ok',
    files: { 'layers/0_base.yml': 'sha256:00' },
    metadata: data.METADATA,
    positionMap: data.POSITION_MAP,
    layers: data.LAYERS,
    settings: data.SETTINGS,
    references: data.REFERENCES,
    diagnostics: [],
    ...overrides,
  };
}

/** 間引きと非同期の返事を進める */
export async function settle(ms = 60): Promise<void> {
  await new Promise((resolve) => setTimeout(resolve, ms));
}
