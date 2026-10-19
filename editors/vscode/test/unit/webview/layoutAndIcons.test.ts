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
import { keyAccessibleName, keyFaceNote, keyMark, layerSlots, windowLabels } from '../../../src/webview/model';
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

describe('キーの面の印・窓・帯', () => {
  const value = (text: string): KeyValue => data.interpret(text)!;
  const faceOf = (v: KeyValue) => {
    const element = document.createElement('div');
    element.append(...keyFace({ text: v.text, value: v }));
    return element;
  };
  const face = (text: string) => faceOf(value(text));
  const tapDance = (actions?: NonNullable<KeyValue['display']['actions']>): KeyValue => ({
    text: "TapDance('Paste Variants')",
    canonical: "TapDance('Paste Variants')",
    code: 0x5702,
    kind: 'tapDance',
    display: actions ? { label: 'Paste Variants', actions } : { label: 'Paste Variants' },
  });
  const four = tapDance([
    { action: 'tap', label: '⌘V' },
    { action: 'hold', label: 'Copy Selected' },
    { action: 'doubleTap', label: 'Copy Word' },
    { action: 'tapHold', label: 'Copy Line' },
  ]);
  const slots = () => layerSlots(data.LAYERS[0]!, data.POSITION_MAP);
  const encoderView = (hand: 'left' | 'right', op: 'ccw' | 'push' | 'cw', v: KeyValue) => {
    const all = slots();
    const view = new KeyboardView({ onSelect: () => undefined });
    view.setSlots(all);
    const slot = all.find((s) => s.hand === hand && s.encoder === op)!;
    view.update(slot.id, { text: v.text, value: v, diagnostics: [], changed: false });
    return view.element.querySelectorAll('.encoder')[hand === 'left' ? 0 : 1]!.querySelector(`.encoder-${op}`)!;
  };

  it('NoKey は空白で、✕ や x を描かない', () => {
    const element = face('NoKey');
    expect(element.textContent).toBe('');
    expect(element.querySelector('.key-label')).toBeNull();
  });

  it('マクロは M、自分のショートカットは ★ の印を右上に付ける', () => {
    const mark = (text: string) => face(text).querySelector('.key-mark');
    expect(mark("Macro('Bracket Pair')")?.textContent).toBe('M');
    expect(mark("Macro('Bracket Pair')")?.classList.contains('mark-macro')).toBe(true);
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
    const q = slots().find((slot) => slot.label === 'Q')!;
    const macro = value("Macro('Bracket Pair')");
    expect(keyAccessibleName(q, macro.text, macro, [])).toBe('左手 Q: マクロ Bracket Pair');
    expect(keyFaceNote(macro)).toBe('印「M」: マクロ');
    const tip = describeContent(macro.text, { value: macro, diagnostics: [], description: null }, { mark: '印「M」: マクロ' }) as HTMLElement;
    expect(tip.querySelector('.tooltip-mark')?.textContent).toBe('印「M」: マクロ');
  });

  it('タップダンスは、割り当てのある動作の数の窓に分ける（1 つでも窓）。TD の印は付けない', () => {
    for (const [count, v] of [
      [4, four],
      [2, value("TapDance('Tab Escape')")],
      [1, tapDance([{ action: 'tap', label: 'OSL L4' }])],
    ] as const) {
      const element = faceOf(v);
      expect(element.querySelector('.td-windows')?.classList.contains(`td-${count}`), String(count)).toBe(true);
      expect(element.querySelectorAll('.td-window')).toHaveLength(count);
      expect(element.querySelector('.key-mark')).toBeNull();
    }
    expect([...faceOf(four).querySelectorAll('.td-window')].map((w) => w.getAttribute('data-action'))).toEqual(['tap', 'hold', 'doubleTap', 'tapHold']);
    expect(faceOf(four).querySelector('.td-more')?.textContent).toBe('+3');
    expect(face("TapDance('Tab Escape')").querySelector('.td-window-1')?.textContent).toBe('Tab');
  });

  it('窓の文字は、ほかの窓と重なる先頭の語を落とす（説明と読み上げは元の文字）', () => {
    const paste = tapDance([
      { action: 'tap', label: '⌘V' },
      { action: 'hold', label: 'Copy Selected' },
      { action: 'doubleTap', label: 'Copy Current Word' },
      { action: 'tapHold', label: 'Copy Current Line' },
    ]);
    expect([...faceOf(paste).querySelectorAll('.td-window')].map((w) => w.textContent)).toEqual(['⌘V', 'Selected', 'Word', 'Line']);
    expect(keyFaceNote(paste)).toContain('ダブルタップ Copy Current Word');
    expect(windowLabels(four.display.actions!)).toEqual(['⌘V', 'Selected', 'Word', 'Line']);
    // 重ならない・落とすと空になる・1 つだけなら元のまま
    expect(windowLabels([
      { action: 'tap', label: 'Tab' },
      { action: 'hold', label: 'Escape' },
    ])).toEqual(['Tab', 'Escape']);
    expect(windowLabels([
      { action: 'tap', label: 'Copy' },
      { action: 'hold', label: 'Copy Line' },
    ])).toEqual(['Copy', 'Line']);
    expect(windowLabels([{ action: 'tap', label: 'Copy Line' }])).toEqual(['Copy Line']);
  });

  it('窓の文字は、1 語なら 1 行（語の途中で折らない）、2 語以上なら語の切れ目で折り返す', () => {
    const labels = [...faceOf(tapDance([
      { action: 'tap', label: 'Escape' },
      { action: 'hold', label: 'Bracket Pair' },
    ])).querySelectorAll('.td-label')];
    expect(labels[0]!.classList.contains('multi')).toBe(false);
    expect(labels[1]!.classList.contains('multi')).toBe(true);
  });

  it('動作の分からない（actions のない）タップダンスだけ、ふつうのキーに TD の印', () => {
    const element = faceOf(tapDance());
    expect(element.querySelector('.td-windows')).toBeNull();
    expect(element.querySelector('.key-mark')?.textContent).toBe('TD');
    expect(keyMark(tapDance())?.meaning).toBe('タップダンス');
  });

  it('窓の動作は読み上げと説明でも分かる', () => {
    const b = slots().find((slot) => slot.label === 'B')!;
    expect(keyAccessibleName(b, four.text, four, [])).toBe(
      '左手 B: タップダンス Paste Variants（タップ ⌘V、ホールド Copy Selected、ダブルタップ Copy Word、タップホールド Copy Line）',
    );
    expect(keyFaceNote(four)).toBe('窓（タップから順に）: タップ ⌘V・ホールド Copy Selected・ダブルタップ Copy Word・タップホールド Copy Line');
  });

  it('レイヤー操作は LT と同じ下の帯にレイヤー番号。MO は面を空け、ほかは面に操作名', () => {
    const mo = face('MO(1)');
    expect(mo.querySelector('.key-tap')?.textContent).toBe('');
    expect(mo.querySelector('.key-hold')?.textContent).toBe('L1');
    const tg = face('TG(3)');
    expect(tg.querySelector('.key-tap')?.textContent).toBe('TG');
    expect(tg.querySelector('.key-hold')?.textContent).toBe('L3');
    const thumb = slots().find((slot) => slot.label === 'fn')!;
    expect(keyAccessibleName(thumb, 'MO(3)', value('MO(3)'), [])).toBe('左手 fn: MO(3)');
    expect(keyAccessibleName(thumb, 'MO(3)', value('MO(3)'), [], new Map([[3, 'Function Keys']]))).toBe('左手 fn: MO(3)（Function Keys）');
  });

  it('エンコーダの帯では窓にせず、タップの札と「+残りの数」の札', () => {
    const part = encoderView('left', 'ccw', four);
    expect(part.classList.contains('windowed')).toBe(true);
    expect(part.querySelector('.td-window-1')?.textContent).toBe('⌘V');
    expect(part.querySelector('.td-more')?.textContent).toBe('+3');
  });

  it('エンコーダの帯にも印・レイヤーの帯を付ける', () => {
    const macro = encoderView('right', 'push', value("Macro('Bracket Pair')"));
    expect(macro.classList.contains('marked')).toBe(true);
    expect(macro.querySelector('.key-mark')?.textContent).toBe('M');
    const mo = encoderView('right', 'cw', value('MO(1)'));
    expect(mo.classList.contains('dual')).toBe(true);
    expect(mo.querySelector('.key-hold')?.textContent).toBe('L1');
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
