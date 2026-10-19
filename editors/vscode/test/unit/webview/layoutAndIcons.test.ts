// @vitest-environment happy-dom
import * as fs from 'node:fs';
import * as path from 'node:path';
import { describe, expect, it } from 'vitest';
import { BOARD, ENCODERS, keyRect, type KeyRect } from '../../../src/webview/cornixLayout';
import { iconElement, setMediaBase } from '../../../src/webview/icons';
import { ICON_ASSETS } from '../../../src/webview/icons/manifest';
import { MessageHostClient } from '../../../src/webview/hostClient';
import { Inspector } from '../../../src/webview/inspector';
import { KeyboardView, keyFace } from '../../../src/webview/keyboardView';
import { keyAccessibleName, keyFaceNote, keyMark, layerSlots } from '../../../src/webview/model';
import { describeContent } from '../../../src/webview/tooltip';
import type { KeyValue } from '../../../src/protocol';
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
      expect(rect!.x + rect!.w).toBeLessThanOrEqual(BOARD.width + 1e-9); // 小数の誤差
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

  it('エンコーダは両手の間の円で、キーと重ならない', () => {
    for (const place of Object.values(ENCODERS)) {
      const box = { ...place, rotate: 0 };
      for (const entry of data.POSITION_MAP) expect(overlaps(box, keyRect(entry.hand, entry.row, entry.col)!)).toBe(false);
    }
    expect(ENCODERS.left.x + ENCODERS.left.w).toBeLessThan(ENCODERS.right.x);
    for (const place of Object.values(ENCODERS)) {
      expect(place.w).toBe(place.h); // 円（CSS の border-radius: 50%）
      // 文字が読めるように、円はキー 2 つ分ほどの大きさ（上下の帯の幅がキーより広い）
      expect(place.w).toBeGreaterThanOrEqual(keyRect('left', 0, 0)!.w * 2);
      // 親指のキーより上
      expect(place.y + place.h).toBeLessThan(keyRect('left', 3, 3)!.y);
    }
  });

  it('レイヤーの欄の列の数は 6 つの段が均等に割れる数（6 / 3 / 2）だけ。5 + 1 や 4 + 2 に割らない', () => {
    const css = fs.readFileSync(path.join(extensionRoot, 'media/webview.css'), 'utf-8');
    const columns = [...css.matchAll(/--field-columns:\s*(\d+)/g)].map((m) => Number(m[1]));
    expect(columns.length).toBeGreaterThan(0);
    for (const n of columns) expect(6 % n, `--field-columns: ${n}`).toBe(0);
    expect(columns).toContain(6);
    expect(css).toMatch(/\.fields\s*\{[^}]*grid-template-columns:\s*repeat\(var\(--field-columns\)/);
  });

  it('レイヤーの欄は position_map の順のキーとエンコーダ 6 つ', () => {
    const slots = layerSlots(data.LAYERS[0]!, data.POSITION_MAP);
    expect(slots).toHaveLength(54);
    expect(slots[0]).toMatchObject({ label: 'tab', context: 'layerKey', key: { row: 0, col: 0, group: 'row0' } });
    expect(slots.filter((slot) => slot.context === 'encoder').map((slot) => `${slot.hand}.${slot.encoder}`)).toEqual([
      'left.ccw',
      'left.push',
      'left.cw',
      'right.ccw',
      'right.push',
      'right.cw',
    ]);
  });

  it('図のエンコーダは上から左回し・押し込み・右回しの帯で、2 役の値は tap / hold を分けて描く', () => {
    const slots = layerSlots(data.LAYERS[0]!, data.POSITION_MAP);
    const view = new KeyboardView({ onSelect: () => undefined });
    view.setSlots(slots);
    const encoders = [...view.element.querySelectorAll('.encoder')];
    expect(encoders.map((encoder) => encoder.getAttribute('aria-label'))).toEqual(['左手のエンコーダ', '右手のエンコーダ']);
    for (const encoder of encoders) {
      expect([...encoder.querySelectorAll('.encoder-part')].map((part) => part.classList[1])).toEqual(['encoder-ccw', 'encoder-push', 'encoder-cw']);
    }
    const push = slots.find((slot) => slot.hand === 'left' && slot.encoder === 'push')!;
    const dual: KeyValue = { text: 'LT1(Space)', canonical: 'LT1(Space)', code: 0x412c, kind: 'layerTap', display: { label: 'Space', tap: 'Space', hold: 'L1' } };
    view.update(push.id, { text: dual.text, value: dual, diagnostics: [], changed: false });
    const part = view.element.querySelector('.encoder-push')!;
    expect(part.classList.contains('dual')).toBe(true);
    expect(part.querySelector('.key-tap')?.textContent).toBe('Space');
    expect(part.querySelector('.key-hold')?.textContent).toBe('L1');
  });
});

describe('キーの面の印', () => {
  const value = (text: string): KeyValue => data.interpret(text)!;
  const face = (text: string) => {
    const element = document.createElement('div');
    element.append(...keyFace({ text, value: value(text) }));
    return element;
  };

  it('NoKey は空白で、✕ や x を描かない', () => {
    const element = face('NoKey');
    expect(element.textContent).toBe('');
    expect(element.querySelector('.key-label')).toBeNull();
  });

  it('マクロは M、タップダンスは TD、自分のショートカットは ★ の印を右上に付ける', () => {
    const mark = (text: string) => face(text).querySelector('.key-mark');
    expect(mark("Macro('Bracket Pair')")?.textContent).toBe('M');
    expect(mark("Macro('Bracket Pair')")?.classList.contains('mark-macro')).toBe(true);
    expect(mark("TapDance('Tab Escape')")?.textContent).toBe('TD');
    expect(mark("Shortcut('前のタブへ')")?.textContent).toBe('★');
    expect(face("Shortcut('前のタブへ')").querySelector('.key-label')?.textContent).toBe('⇧⌘[');
  });

  it('アイコンのある同梱のショートカット・普通のキー・Mod-Tap には印を付けない', () => {
    for (const text of ["Shortcut('VS Code:基本操作:コマンドパレット')", 'Shift + Command + P', 'A', 'LGUI_T(KC_LANG2)']) {
      expect(face(text).querySelector('.key-mark'), text).toBeNull();
    }
    expect(face("Shortcut('VS Code:基本操作:コマンドパレット')").querySelector('.key-icon')).not.toBeNull();
  });

  it('印の意味は読み上げと説明でも分かる', () => {
    const slots = layerSlots(data.LAYERS[0]!, data.POSITION_MAP);
    const q = slots.find((slot) => slot.label === 'Q')!;
    const macro = value("Macro('Bracket Pair')");
    expect(keyAccessibleName(q, macro.text, macro, [])).toBe('左手 Q: マクロ Bracket Pair');
    const tip = describeContent(macro.text, { value: macro, diagnostics: [], description: null }, { mark: '印「M」: マクロ' }) as HTMLElement;
    expect(tip.querySelector('.tooltip-mark')?.textContent).toBe('印「M」: マクロ');
    expect(keyMark(value("TapDance('Tab Escape')"))?.meaning).toBe('タップダンス');
  });

  const tapDance = (actions: NonNullable<KeyValue['display']['actions']>): KeyValue => ({
    text: "TapDance('Paste Variants')",
    canonical: "TapDance('Paste Variants')",
    code: 0x5702,
    kind: 'tapDance',
    display: { label: 'Paste Variants', actions },
  });
  const four = tapDance([
    { action: 'tap', label: '⌘V' },
    { action: 'hold', label: 'Copy Selected' },
    { action: 'doubleTap', label: 'Copy Word' },
    { action: 'tapHold', label: 'Copy Line' },
  ]);

  it('動作が 2 つ以上のタップダンスは、キーの面を動作の数の窓に分け、TD の印は付けない', () => {
    const element = document.createElement('div');
    element.append(...keyFace({ text: four.text, value: four }));
    const grid = element.querySelector('.td-windows')!;
    expect(grid.classList.contains('td-4')).toBe(true);
    expect([...grid.querySelectorAll('.td-window')].map((w) => [w.getAttribute('data-action'), w.textContent])).toEqual([
      ['tap', '⌘V'],
      ['hold', 'Copy Selected'],
      ['doubleTap', 'Copy Word'],
      ['tapHold', 'Copy Line'],
    ]);
    expect(element.querySelector('.key-mark')).toBeNull();
    const two = tapDance([
      { action: 'tap', label: 'Tab' },
      { action: 'hold', label: 'Escape' },
    ]);
    const twoElement = document.createElement('div');
    twoElement.append(...keyFace({ text: two.text, value: two }));
    expect(twoElement.querySelector('.td-windows')?.classList.contains('td-2')).toBe(true);
  });

  it('動作が 1 つ・actions のないタップダンスは、ふつうのキーに TD の印', () => {
    for (const value of [tapDance([{ action: 'tap', label: 'OSL L4' }]), data.interpret("TapDance('Tab Escape')")!]) {
      const element = document.createElement('div');
      element.append(...keyFace({ text: value.text, value }));
      expect(element.querySelector('.td-windows')).toBeNull();
      expect(element.querySelector('.key-mark')?.textContent).toBe('TD');
    }
  });

  it('窓の動作は読み上げと説明でも分かる', () => {
    const slots = layerSlots(data.LAYERS[0]!, data.POSITION_MAP);
    const b = slots.find((slot) => slot.label === 'B')!;
    expect(keyAccessibleName(b, four.text, four, [])).toBe(
      '左手 B: タップダンス Paste Variants（タップ ⌘V、ホールド Copy Selected、ダブルタップ Copy Word、タップホールド Copy Line）',
    );
    expect(keyFaceNote(four)).toBe('窓（左上から）: タップ ⌘V・ホールド Copy Selected・ダブルタップ Copy Word・タップホールド Copy Line');
    expect(keyFaceNote(data.interpret("Macro('Bracket Pair')"))).toBe('印「M」: マクロ');
  });

  it('エンコーダの帯では窓にせず、同じ札を横に並べる', () => {
    const slots = layerSlots(data.LAYERS[0]!, data.POSITION_MAP);
    const view = new KeyboardView({ onSelect: () => undefined });
    view.setSlots(slots);
    const ccw = slots.find((slot) => slot.hand === 'left' && slot.encoder === 'ccw')!;
    view.update(ccw.id, { text: four.text, value: four, diagnostics: [], changed: false });
    const part = view.element.querySelector('.encoder-ccw')!;
    expect(part.classList.contains('windowed')).toBe(true);
    expect(part.querySelectorAll('.td-window')).toHaveLength(4);
  });

  it('エンコーダの帯にも同じ印を付ける', () => {
    const slots = layerSlots(data.LAYERS[0]!, data.POSITION_MAP);
    const view = new KeyboardView({ onSelect: () => undefined });
    view.setSlots(slots);
    const push = slots.find((slot) => slot.hand === 'right' && slot.encoder === 'push')!;
    const td = value("TapDance('Tab Escape')");
    view.update(push.id, { text: td.text, value: td, diagnostics: [], changed: false });
    const part = view.element.querySelectorAll('.encoder')[1]!.querySelector('.encoder-push')!;
    expect(part.classList.contains('marked')).toBe(true);
    expect(part.querySelector('.key-mark')?.textContent).toBe('TD');
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
