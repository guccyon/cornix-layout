// metadata.yaml と position_map.yaml の表示（読むだけ。spec.md の「ファイルの種類ごと」）。
import type { PositionMapEntry, ProfileSnapshot } from '../protocol';
import { h } from './dom';
import { groupLabel, HAND_LABEL } from './model';

export class MetadataView {
  readonly element: HTMLElement;
  private readonly metadata = h('dl', { class: 'metadata-list' });
  private readonly positions = h('div', { class: 'position-map-list' });
  private key = '';

  constructor() {
    this.element = h(
      'section',
      { class: 'metadata-view', 'aria-label': 'メタデータ' },
      h(
        'details',
        { class: 'section-details' },
        h('summary', {}, h('h2', {}, 'メタデータと position_map'), h('span', { class: 'read-only' }, '読むだけ')),
        h('h3', {}, 'metadata.yaml'),
        this.metadata,
        h('h3', {}, 'position_map.yaml'),
        this.positions,
      ),
    );
  }

  update(snapshot: ProfileSnapshot): void {
    this.element.hidden = snapshot.status !== 'ok';
    const key = JSON.stringify([snapshot.metadata, snapshot.positionMap]);
    if (key === this.key) return;
    this.key = key;
    const entries = Object.entries(snapshot.metadata);
    this.metadata.replaceChildren(
      ...(entries.length === 0
        ? [h('dd', { class: 'empty' }, '（書いていません）')]
        : entries.flatMap(([name, value]) => [h('dt', {}, name), h('dd', {}, formatMetadata(value))])),
    );
    this.positions.replaceChildren(...positionRows(snapshot.positionMap));
  }
}

/** 値の見せ方（入れ子は JSON。uid など 2^53 を超える整数は JavaScript の number で丸まっている。protocol.md の 5.2） */
function formatMetadata(value: unknown): string {
  if (value === null || value === undefined) return '（なし）';
  if (typeof value === 'object') return JSON.stringify(value);
  return String(value);
}

function positionRows(entries: PositionMapEntry[]): HTMLElement[] {
  const rows: HTMLElement[] = [];
  for (const hand of ['left', 'right'] as const) {
    const ofHand = entries.filter((entry) => entry.hand === hand);
    const groups = [...new Set(ofHand.map((entry) => entry.group))];
    for (const group of groups) {
      const symbols = ofHand.filter((entry) => entry.group === group).map((entry) => entry.symbol);
      rows.push(
        h(
          'div',
          { class: 'position-row' },
          h('span', { class: 'position-group' }, `${HAND_LABEL[hand]} ${groupLabel(group)}（${group}）`),
          h('span', { class: 'position-symbols' }, symbols.join(' ')),
        ),
      );
    }
  }
  return rows;
}
