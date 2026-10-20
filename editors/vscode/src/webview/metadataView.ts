// metadata.yaml の表示（読むだけ。spec.md の「ファイルの種類ごと」）。入れ子の Hash は表の中の表、配列は番号を振った表で見せる。
// position_map.yaml は出さない（欄の名前として下のレイヤーの欄に出ている。名前を画面から直すのは roadmap.md の v0.2 の候補）。
import type { ProfileSnapshot } from '../protocol';
import { h } from './dom';

export class MetadataView {
  readonly element: HTMLElement;
  private readonly metadata = h('div', { class: 'metadata-body' });
  private key = '';

  constructor() {
    this.element = h(
      'section',
      { class: 'metadata-view', 'aria-label': 'メタデータ' },
      h(
        'details',
        { class: 'section-details' },
        h('summary', {}, h('h2', {}, 'メタデータ'), h('span', { class: 'read-only' }, '読むだけ')),
        h('h3', {}, 'metadata.yaml'),
        this.metadata,
      ),
    );
  }

  update(snapshot: ProfileSnapshot): void {
    this.element.hidden = snapshot.status !== 'ok';
    const key = JSON.stringify(snapshot.metadata);
    if (key === this.key) return;
    this.key = key;
    const entries = Object.entries(snapshot.metadata);
    this.metadata.replaceChildren(entries.length === 0 ? h('p', { class: 'empty' }, '（書いていません）') : metadataTable(entries));
  }
}

/** 名前と値の表。値が Hash・配列なら、その欄の中にもう 1 つ表を置く */
function metadataTable(entries: [string, unknown][]): HTMLElement {
  const body = h('tbody', {});
  for (const [name, value] of entries) {
    body.append(h('tr', {}, h('th', { scope: 'row' }, name), h('td', {}, metadataValue(value))));
  }
  return h('table', { class: 'metadata-table' }, body);
}

/**
 * 値の見せ方。uid など 2^53 を超える整数は JavaScript の number で丸まっている（protocol.md の 5.2）。
 * 文字と数の配列は 1 行に並べ、Hash を含む配列は 1 つずつ番号を振った表にする
 */
function metadataValue(value: unknown): Node {
  if (value === null || value === undefined) return h('span', { class: 'metadata-empty' }, '（なし）');
  if (Array.isArray(value)) {
    if (value.length === 0) return h('span', { class: 'metadata-empty' }, '（空）');
    if (value.every((item) => item === null || typeof item !== 'object')) {
      return h('span', { class: 'metadata-list' }, ...value.map((item) => h('span', { class: 'metadata-item' }, scalar(item))));
    }
    return metadataTable(value.map((item, index) => [String(index + 1), item]));
  }
  if (typeof value === 'object') {
    const entries = Object.entries(value as Record<string, unknown>);
    if (entries.length === 0) return h('span', { class: 'metadata-empty' }, '（空）');
    return metadataTable(entries);
  }
  return h('span', { class: 'metadata-scalar' }, scalar(value));
}

function scalar(value: unknown): string {
  if (value === null || value === undefined) return '（なし）';
  return String(value);
}
