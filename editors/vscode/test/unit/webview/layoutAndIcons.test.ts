// @vitest-environment happy-dom
import * as fs from 'node:fs';
import * as path from 'node:path';
import { describe, expect, it } from 'vitest';
import { BOARD, ENCODERS, keyRect, type KeyRect } from '../../../src/webview/cornixLayout';
import { iconElement, setMediaBase } from '../../../src/webview/icons';
import { ICON_ASSETS } from '../../../src/webview/icons/manifest';
import { MessageHostClient } from '../../../src/webview/hostClient';
import { Inspector } from '../../../src/webview/inspector';
import { layerSlots } from '../../../src/webview/model';
import type { WebviewMessage } from '../../../src/webviewMessages';
import * as data from '../../fake-server/fixtures';
import { FakeHost } from './fakeHost';

const extensionRoot = path.resolve(__dirname, '../../..');
const repoRoot = path.resolve(extensionRoot, '../..');

function overlaps(a: KeyRect, b: KeyRect): boolean {
  const margin = 0.02; // 傾けた親指の角の重なりは見ない
  return a.x + margin < b.x + b.w - margin && b.x + margin < a.x + a.w - margin && a.y + margin < b.y + b.h - margin && b.y + margin < a.y + a.h - margin;
}

describe('Cornix の物理配置', () => {
  it('position_map のすべての位置に、図の中で重ならないキーがある', () => {
    const rects = data.POSITION_MAP.map((entry) => ({ entry, rect: keyRect(entry.hand, entry.row, entry.col) }));
    for (const { entry, rect } of rects) {
      expect(rect, `${entry.hand} ${entry.group} ${entry.symbol}`).toBeDefined();
      expect(rect!.x).toBeGreaterThanOrEqual(0);
      expect(rect!.x + rect!.w).toBeLessThanOrEqual(BOARD.width);
      expect(rect!.y + rect!.h).toBeLessThanOrEqual(BOARD.height);
    }
    for (let i = 0; i < rects.length; i++) {
      for (let j = i + 1; j < rects.length; j++) {
        expect(overlaps(rects[i]!.rect!, rects[j]!.rect!), `${rects[i]!.entry.symbol} と ${rects[j]!.entry.symbol}`).toBe(false);
      }
    }
  });

  it('列は左右とも物理的に左から右。右手は row3 が外側、親指が内側', () => {
    const x = (hand: 'left' | 'right', row: number, col: number) => keyRect(hand, row, col)!.x;
    for (const hand of ['left', 'right'] as const) {
      for (let col = 1; col <= 5; col++) expect(x(hand, 0, col)).toBeGreaterThan(x(hand, 0, col - 1));
    }
    expect(x('left', 3, 3)).toBeGreaterThan(x('left', 3, 2)); // 左手: 親指が row3 の右（内側）
    expect(x('right', 3, 0)).toBeGreaterThan(x('right', 3, 5)); // 右手: row3（矢印）が親指の右（外側）
    expect(x('right', 0, 0)).toBeGreaterThan(x('left', 0, 5));
  });

  it('エンコーダは両手の間にあり、キーと重ならない', () => {
    for (const place of Object.values(ENCODERS)) {
      const box = { ...place, rotate: 0 };
      for (const entry of data.POSITION_MAP) expect(overlaps(box, keyRect(entry.hand, entry.row, entry.col)!)).toBe(false);
    }
    expect(ENCODERS.left.x + ENCODERS.left.w).toBeLessThan(ENCODERS.right.x);
    // 文字が読めるように、エンコーダの欄はキーより幅がある
    for (const place of Object.values(ENCODERS)) expect(place.w).toBeGreaterThan(keyRect('left', 0, 0)!.w * 1.5);
  });

  it('レイヤーの欄は position_map の順のキーとエンコーダ 6 つ', () => {
    const slots = layerSlots(data.LAYERS[0]!, data.POSITION_MAP);
    expect(slots).toHaveLength(54);
    expect(slots[0]).toMatchObject({ label: 'tab', context: 'layerKey', key: { row: 0, col: 0, group: 'row0' } });
    expect(slots.filter((slot) => slot.context === 'encoder').map((slot) => `${slot.hand}.${slot.encoder}`)).toEqual([
      'left.push',
      'left.ccw',
      'left.cw',
      'right.push',
      'right.ccw',
      'right.cw',
    ]);
  });
});

describe('アイコン', () => {
  const ids = fs
    .readFileSync(path.join(repoRoot, 'data/shortcut_icons.yaml'), 'utf-8')
    .split('\n')
    .map((line) => /^\s+[^#:]+:\s*((?:simple-icons|material-icon-theme|badge):[^\s#]+)/.exec(line)?.[1])
    .filter((id): id is string => !!id);

  it('data/shortcut_icons.yaml のすべての ID が要素になり、SVG とライセンス表記が media/ にある', () => {
    expect(ids.length).toBeGreaterThan(20);
    setMediaBase('https://example.test/media');
    for (const id of ids) {
      const element = iconElement(id);
      expect(element, id).not.toBeNull();
      if (id.startsWith('badge:')) {
        expect(element!.textContent).toBe(id.slice('badge:'.length));
        continue;
      }
      const asset = ICON_ASSETS[id];
      expect(asset, id).toBeDefined();
      expect(fs.existsSync(path.join(extensionRoot, 'media', asset!.file)), asset!.file).toBe(true);
      expect(element!.outerHTML).toContain(`https://example.test/media/${asset!.file}`);
    }
    for (const license of ['simple-icons/LICENSE.md', 'material-icon-theme/LICENSE']) {
      expect(fs.existsSync(path.join(extensionRoot, 'media/icons', license)), license).toBe(true);
    }
  });

  it('同梱する SVG は表にある分だけ', () => {
    const files = ['simple-icons', 'material-icon-theme'].flatMap((dir) =>
      fs
        .readdirSync(path.join(extensionRoot, 'media/icons', dir))
        .filter((file) => file.endsWith('.svg'))
        .map((file) => `icons/${dir}/${file}`),
    );
    expect(files.sort()).toEqual(Object.values(ICON_ASSETS).map((asset) => asset.file).sort());
  });

  it('知らない ID や空ならアイコンを出さない', () => {
    expect(iconElement(null)).toBeNull();
    expect(iconElement('simple-icons:nothing')).toBeNull();
    expect(iconElement('unknown')).toBeNull();
  });
});

describe('ホストとのやりとり', () => {
  it('リクエストに id を付けて送り、同じ id の応答で返す', async () => {
    const posted: WebviewMessage[] = [];
    const client = new MessageHostClient((message) => posted.push(message));
    const first = client.request('keycode/inspect', { context: 'layerKey', text: 'A' });
    const second = client.request('keycode/candidates', { context: 'encoder', query: '' });
    expect(posted).toEqual([
      { type: 'request', id: 1, method: 'keycode/inspect', params: { context: 'layerKey', text: 'A' } },
      { type: 'request', id: 2, method: 'keycode/candidates', params: { context: 'encoder', query: '' } },
    ]);
    expect(client.handle({ type: 'response', id: 2, method: 'keycode/candidates', error: 'だめ' })).toBe(true);
    expect(client.handle({ type: 'response', id: 1, method: 'keycode/inspect', result: { value: null, diagnostics: [], description: null } })).toBe(true);
    expect(client.handle({ type: 'error', message: 'x' })).toBe(false);
    await expect(first).resolves.toEqual({ value: null, diagnostics: [], description: null });
    await expect(second).rejects.toThrow('だめ');
  });

  it('inspect は同じ表記を 1 回だけ聞き、clear で捨てる', async () => {
    const host = new FakeHost();
    const inspector = new Inspector(host);
    await Promise.all([inspector.load('layerKey', 'A'), inspector.load('layerKey', 'A')]);
    expect(inspector.get('layerKey', 'A')?.value?.canonical).toBe('A');
    expect(host.requests).toHaveLength(1);
    await inspector.load('encoder', 'A');
    expect(host.requests).toHaveLength(2);
    inspector.clear();
    expect(inspector.get('layerKey', 'A')).toBeUndefined();
  });
});
