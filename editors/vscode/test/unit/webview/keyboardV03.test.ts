// @vitest-environment happy-dom
// v0.3 の図（E1）: 位置の名前のボタンのホバーと出所の説明、書いていない位置の見た目、コンボのボタンと強調、全レイヤーの表示、図からキーを選ぶ状態
import fs from 'node:fs';
import path from 'node:path';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import type { AnyChange, ComboSnapshot, KeyValue, PositionMapEntry } from '../../../src/protocol';
import { App } from '../../../src/webview/app';
import { comboTargets, effectiveKey, sameKey, triggerKeys } from '../../../src/webview/comboHighlight';
import { layerLineLabel } from '../../../src/webview/model';
import { hideTooltip } from '../../../src/webview/tooltip';
import * as data from '../../fake-server/fixtures';
import { FakeHost, fixtureSnapshot, settle } from './fakeHost';

const base = 'layers/0_base.yml';
const symbols = 'layers/1_symbols.yml';
const comboFile = 'combos/00_left_bracket.yml';
const address = (file: string, hand: string, group: string, symbol: string) => ({ file, path: ['mapping', hand, group, symbol] });
const slotOf = (hand: string, group: string, symbol: string, file = base) => JSON.stringify([file, 'mapping', hand, group, symbol]);

/** v0.2 のサーバーの position_map（名前を書いている場所付き） */
const POSITION_MAP_V02: PositionMapEntry[] = data.POSITION_MAP.map((entry) => {
  const index = data.POSITION_MAP.filter((e) => e.hand === entry.hand && e.group === entry.group).indexOf(entry);
  return { ...entry, address: { file: 'position_map.yaml', path: [`${entry.hand}_hand`, entry.group, index] } };
});

const value = (text: string): KeyValue => {
  const v = data.interpret(text);
  if (!v) throw new Error(`${text} は読めない`);
  return v;
};

/** トリガーを差し替えたコンボ */
function combo(index: number, name: string, triggers: string[], extra: Partial<ComboSnapshot> = {}): ComboSnapshot {
  const file = `combos/0${index}_${name}.yml`;
  return {
    index,
    name,
    description: null,
    file,
    descriptionAddress: { file, path: ['description'] },
    triggersAddress: { file, path: ['trigger_keys'] },
    triggers: triggers.map((text, i) => ({ address: { file, path: ['trigger_keys', i] }, value: value(text) })),
    output: { address: { file, path: ['output_key'] }, value: value('LBracket') },
    ...extra,
  };
}

let host: FakeHost;
let root: HTMLElement;
let app: App;

function keyElement(id: string): HTMLElement {
  const element = root.querySelector<HTMLElement>(`.board [data-slot='${id}']`);
  if (!element) throw new Error(`図に ${id} がない`);
  return element;
}

function highlighted(): string[] {
  return [...root.querySelectorAll<HTMLElement>('.board .combo-trigger')].map((element) => element.dataset.slot ?? '');
}

function comboButton(index: number): HTMLButtonElement {
  const button = root.querySelector<HTMLButtonElement>(`.combo-buttons [data-combo='${index}']`);
  if (!button) throw new Error(`コンボ ${index} のボタンがない`);
  return button;
}

function press(target: EventTarget, type: 'keydown' | 'keyup', key: string): void {
  target.dispatchEvent(new KeyboardEvent(type, { key, bubbles: true, cancelable: true }));
}

beforeEach(() => {
  host = new FakeHost();
  root = document.createElement('div');
  document.body.replaceChildren(root);
  app = new App(root, { host });
});

afterEach(() => {
  hideTooltip();
  document.body.replaceChildren();
});

describe('位置の名前のボタンのホバーと出所の説明', () => {
  it('ボタンにマウスを載せている間だけ位置の名前を出し、図の下に出所を 1 行出す', () => {
    app.receive({ type: 'snapshot', snapshot: fixtureSnapshot({ positionMap: POSITION_MAP_V02 }), changes: [] });
    const toggle = root.querySelector<HTMLButtonElement>('.position-toggle')!;
    const q = keyElement(slotOf('left_hand', 'row0', 'Q'));
    const hint = root.querySelector<HTMLElement>('.position-hint')!;
    expect(toggle.title).toContain('position_map.yaml');
    expect(toggle.title).toContain('ファイルを変えるとラベルが変わる');
    expect(hint.hidden).toBe(true);
    // 隠している間も文は入れておく（CSS で見えなくするだけで行の高さを残し、ホバーで下の欄をずらさない）
    expect(hint.textContent).toBe('名前は position_map.yaml のもの。キーを押すとここで名前を変えられる');

    toggle.dispatchEvent(new MouseEvent('mouseenter'));
    expect(q.querySelector('.position-name')?.textContent).toBe('Q');
    expect(hint.hidden).toBe(false);
    expect(hint.textContent).toBe('名前は position_map.yaml のもの。キーを押すとここで名前を変えられる');
    // 載せているだけでは固定しない
    expect(toggle.getAttribute('aria-pressed')).toBe('false');

    toggle.dispatchEvent(new MouseEvent('mouseleave'));
    expect(q.querySelector('.position-name')).toBeNull();
    expect(hint.hidden).toBe(true);

    // 固定・Alt と共存する（固定中は離れても出したまま）
    toggle.click();
    toggle.dispatchEvent(new MouseEvent('mouseenter'));
    toggle.dispatchEvent(new MouseEvent('mouseleave'));
    expect(q.querySelector('.position-name')?.textContent).toBe('Q');
    toggle.click();
    press(window, 'keydown', 'Alt');
    toggle.dispatchEvent(new MouseEvent('mouseenter'));
    toggle.dispatchEvent(new MouseEvent('mouseleave'));
    expect(q.querySelector('.position-name')?.textContent).toBe('Q');
    press(window, 'keyup', 'Alt');
    expect(q.querySelector('.position-name')).toBeNull();
  });

  it('名前を変えられないサーバー（positionMap に address がない）では、出所の行に名前を変える案内を入れない', () => {
    app.receive({ type: 'snapshot', snapshot: fixtureSnapshot(), changes: [] });
    app.keyboardView.setPinned(true);
    expect(root.querySelector('.position-hint')?.textContent).toBe('名前は position_map.yaml のもの。ファイルを変えるとラベルが変わる');
  });
});

describe('書いていない位置の見た目', () => {
  it('割り当てを消したキーも図に残り、面は NoKey と同じく空白（背景を抜く CSS の決まりはない）', () => {
    app.receive({
      type: 'snapshot',
      snapshot: fixtureSnapshot(),
      changes: [],
      pending: [{ op: 'remove', address: address(base, 'left_hand', 'row0', 'Q') }],
    });
    const q = keyElement(slotOf('left_hand', 'row0', 'Q'));
    expect(q.classList.contains('unassigned')).toBe(true);
    expect(q.textContent).toBe('');
    app.selectLayer(1);
    // NoKey（R）と書いていない位置（W）は同じ面
    const r = keyElement(slotOf('left_hand', 'row0', 'R', symbols));
    const w = keyElement(slotOf('left_hand', 'row0', 'W', symbols));
    expect(r.textContent).toBe('');
    expect(w.textContent).toBe('');
    const css = fs.readFileSync(path.join(__dirname, '../../../media/webview.css'), 'utf-8');
    expect(css).not.toMatch(/^\.key\.unassigned\s*\{/m);
  });
});

describe('コンボのボタンと強調', () => {
  it('コンボがなければボタン列を出さない', () => {
    app.receive({ type: 'snapshot', snapshot: fixtureSnapshot(), changes: [] });
    expect(root.querySelector<HTMLElement>('.combo-buttons')?.hidden).toBe(true);
    expect(root.querySelectorAll('.combo-button')).toHaveLength(0);
  });

  it('押すと固定してトリガーのキーを強調し、もう一度押すと外す。載せている間は一時的に強調する（同時に 1 つ）', () => {
    const combos = [...data.COMBOS, combo(1, 'Copy', ['A', 'S'])];
    app.receive({ type: 'snapshot', snapshot: fixtureSnapshot({ combos }), changes: [] });
    expect(root.querySelector<HTMLElement>('.combo-buttons')?.hidden).toBe(false);
    const j = slotOf('right_hand', 'row1', 'J');
    const k = slotOf('right_hand', 'row1', 'K');
    const a = slotOf('left_hand', 'row1', 'A');
    const s = slotOf('left_hand', 'row1', 'S');
    expect(highlighted()).toEqual([]);

    comboButton(0).click();
    expect(highlighted().sort()).toEqual([j, k].sort());
    expect(comboButton(0).getAttribute('aria-pressed')).toBe('true');
    expect(root.querySelector('.board')?.classList.contains('combo-active')).toBe(true);

    // 載せている間は載せたほうだけ
    comboButton(1).dispatchEvent(new MouseEvent('mouseenter'));
    expect(highlighted().sort()).toEqual([a, s].sort());
    comboButton(1).dispatchEvent(new MouseEvent('mouseleave'));
    expect(highlighted().sort()).toEqual([j, k].sort());

    // ほかを押すと切り替わり、もう一度押すと外れる
    comboButton(1).click();
    expect(comboButton(0).getAttribute('aria-pressed')).toBe('false');
    expect(highlighted().sort()).toEqual([a, s].sort());
    comboButton(1).click();
    expect(highlighted()).toEqual([]);
    expect(root.querySelector('.board')?.classList.contains('combo-active')).toBe(false);
  });

  it('今のレイヤーで割り当てた位置を強調し、KC_TRNS の位置はレイヤー 0 の値で見る', () => {
    const combos = [combo(0, 'Ctrl', ['LCtrl', 'K'])];
    app.receive({ type: 'snapshot', snapshot: fixtureSnapshot({ combos }), changes: [] });
    comboButton(0).click();
    expect(highlighted().sort()).toEqual([slotOf('left_hand', 'row1', 'lctrl'), slotOf('right_hand', 'row1', 'K')].sort());
    // Symbols: lctrl は Trans（レイヤー 0 の LCtrl）、K は LBracket（強調しない）
    app.selectLayer(1);
    expect(highlighted()).toEqual([slotOf('left_hand', 'row1', 'lctrl', symbols)]);
  });

  it('押せないコンボのボタンに ⚠。説明に名前・同時に押すキー・出すキーを出す', async () => {
    const combos = [{ ...data.COMBOS[0]!, reachable: true }, combo(1, 'Never', ['A', 'LBracket'], { reachable: false })];
    app.receive({ type: 'snapshot', snapshot: fixtureSnapshot({ combos }), changes: [] });
    expect(comboButton(0).querySelector('.combo-warning')).toBeNull();
    expect(comboButton(1).querySelector('.combo-warning')?.textContent).toBe('⚠');
    expect(comboButton(1).classList.contains('unreachable')).toBe(true);
    expect(comboButton(1).getAttribute('aria-label')).toBe('コンボ 1 Never（押せない）');

    comboButton(0).dispatchEvent(new MouseEvent('mouseenter'));
    await settle(400);
    const tooltip = document.querySelector<HTMLElement>('.tooltip')!;
    expect(tooltip.hidden).toBe(false);
    expect(tooltip.textContent).toContain('Left Bracket');
    expect(tooltip.textContent).toContain('J と K で [');
    expect(tooltip.textContent).toContain('同時に押すキー: J + K');
    expect(tooltip.textContent).toContain('出すキー: LBracket');
    expect(tooltip.textContent).toContain('2 か所');
    comboButton(0).dispatchEvent(new MouseEvent('mouseleave'));

    comboButton(1).dispatchEvent(new MouseEvent('mouseenter'));
    await settle(400);
    expect(tooltip.textContent).toContain('押せないコンボ');
  });

  it('未保存の変更を重ねて比べる（図の値の変更とトリガーの変更）', async () => {
    app.receive({ type: 'snapshot', snapshot: fixtureSnapshot({ combos: data.COMBOS }), changes: [] });
    comboButton(0).click();
    const pending: AnyChange[] = [
      // 図の Q を J に（Q も強調する）
      { address: address(base, 'left_hand', 'row0', 'Q'), value: 'J' },
      // トリガーの K を A に
      { address: { file: comboFile, path: ['trigger_keys', 1] }, value: 'A' },
    ];
    app.receive({ type: 'snapshot', snapshot: fixtureSnapshot({ combos: data.COMBOS }), changes: [], pending });
    await settle(0);
    expect(highlighted().sort()).toEqual(
      [slotOf('left_hand', 'row0', 'Q'), slotOf('right_hand', 'row1', 'J'), slotOf('left_hand', 'row1', 'A')].sort(),
    );
  });
});

describe('全レイヤーの表示', () => {
  it('各キーの面にレイヤーごとの値を「番号 ラベル」で並べ、KC_TRNS・NoKey・書いていない位置の行は省き、今のレイヤーを強調する', () => {
    app.receive({ type: 'snapshot', snapshot: fixtureSnapshot(), changes: [] });
    const toggle = root.querySelector<HTMLButtonElement>('.layers-toggle')!;
    expect(toggle.textContent).toBe('全レイヤー');
    toggle.click();
    expect(toggle.getAttribute('aria-pressed')).toBe('true');
    const lines = (id: string) =>
      [...keyElement(id).querySelectorAll<HTMLElement>('.layer-line')].map((line) => `${line.textContent}${line.classList.contains('current') ? '*' : ''}`);
    // Q: 0 Q と 1 ?（fixtures の Question のラベル）
    expect(lines(slotOf('left_hand', 'row0', 'Q'))).toEqual(['0Q*', `1${data.interpret('Question')!.display.label}`]);
    // R: レイヤー 1 は NoKey → 省く。lctrl: レイヤー 1 は Trans → 省く。W: レイヤー 1 は書いていない → 省く
    expect(lines(slotOf('left_hand', 'row0', 'R'))).toEqual(['0R*']);
    expect(lines(slotOf('left_hand', 'row1', 'lctrl'))).toEqual([`0${data.interpret('LCtrl')!.display.label}*`]);
    expect(lines(slotOf('left_hand', 'row0', 'W'))).toEqual(['0W*']);
    // 2 役のキーはタップ/ホールド
    expect(lines(slotOf('left_hand', 'thumb_keys', 'middle'))).toEqual(['0Space/L1*', '1Space']);
    expect(keyElement(slotOf('left_hand', 'row0', 'Q')).getAttribute('aria-label')).toContain('全レイヤー: 0 Q、1 ');

    app.selectLayer(1);
    expect(lines(slotOf('left_hand', 'row0', 'Q', symbols))).toEqual(['0Q', `1${data.interpret('Question')!.display.label}*`]);
    // エンコーダはいつもの面
    expect(root.querySelector('.encoder-part .layer-line')).toBeNull();
  });

  it('位置の名前の表示とは同時に出さず、あとから押したほうに切り替える。Alt の一時表示は位置の名前が勝つ', () => {
    app.receive({ type: 'snapshot', snapshot: fixtureSnapshot(), changes: [] });
    const positions = root.querySelector<HTMLButtonElement>('.position-toggle')!;
    const layers = root.querySelector<HTMLButtonElement>('.layers-toggle')!;
    const q = keyElement(slotOf('left_hand', 'row0', 'Q'));
    positions.click();
    layers.click();
    expect(positions.getAttribute('aria-pressed')).toBe('false');
    expect(q.querySelector('.layer-line')).not.toBeNull();
    expect(q.querySelector('.position-name')).toBeNull();
    positions.click();
    expect(layers.getAttribute('aria-pressed')).toBe('false');
    expect(q.querySelector('.position-name')).not.toBeNull();
    expect(q.querySelector('.layer-line')).toBeNull();

    layers.click();
    press(window, 'keydown', 'Alt');
    expect(q.querySelector('.position-name')).not.toBeNull();
    press(window, 'keyup', 'Alt');
    expect(q.querySelector('.layer-line')).not.toBeNull();
    layers.click();
    expect(q.querySelector('.layer-line')).toBeNull();
    expect(q.textContent).toBe('Q');
  });

  it('ほかのレイヤーの未保存の変更も行に出す（解釈が返ったら描き直す）', async () => {
    const pending: AnyChange[] = [
      { address: address(symbols, 'left_hand', 'row0', 'W'), value: 'Escape' },
      { op: 'remove', address: address(symbols, 'left_hand', 'row0', 'Q') },
    ];
    app.receive({ type: 'snapshot', snapshot: fixtureSnapshot(), changes: [], pending });
    app.keyboardView.setShowLayers(true);
    await settle(0);
    const labels = (id: string) => [...keyElement(id).querySelectorAll('.layer-line')].map((line) => line.textContent);
    expect(labels(slotOf('left_hand', 'row0', 'W'))).toEqual(['0W', '1Esc']);
    expect(labels(slotOf('left_hand', 'row0', 'Q'))).toEqual(['0Q']);
  });

  it('表示中にキーを押すと下の欄へ移る（今と同じ）', () => {
    app.receive({ type: 'snapshot', snapshot: fixtureSnapshot(), changes: [] });
    app.keyboardView.setShowLayers(true);
    const q = slotOf('left_hand', 'row0', 'Q');
    keyElement(q).click();
    expect(app.selectedSlot).toBe(q);
  });
});

describe('図からキーを選ぶ（pickKey）', () => {
  it('選ぶ状態の間は図の上に案内を出し、キーを押すと今のレイヤーの表記を渡して抜ける（欄は選ばない）', () => {
    app.receive({ type: 'snapshot', snapshot: fixtureSnapshot(), changes: [] });
    const picked: string[] = [];
    app.pickKey((text) => picked.push(text));
    const banner = root.querySelector<HTMLElement>('.pick-banner')!;
    expect(app.isPicking).toBe(true);
    expect(banner.hidden).toBe(false);
    expect(banner.textContent).toBe('キーを押して選ぶ（Esc で戻る）');
    expect(root.querySelector('.board')?.classList.contains('picking')).toBe(true);

    keyElement(slotOf('left_hand', 'thumb_keys', 'middle')).click();
    expect(picked).toEqual(['LT1(Space)']);
    expect(app.isPicking).toBe(false);
    expect(banner.hidden).toBe(true);
    expect(root.querySelector('.board')?.classList.contains('picking')).toBe(false);
    expect(app.selectedSlot).toBeUndefined();
    // 抜けたあとは普段どおり
    keyElement(slotOf('left_hand', 'row0', 'Q')).click();
    expect(picked).toEqual(['LT1(Space)']);
    expect(app.selectedSlot).toBe(slotOf('left_hand', 'row0', 'Q'));
  });

  it('未保存の表記を渡し、エンコーダも選べる。書いていないキーは選べない（選ぶ状態のまま）', () => {
    app.receive({
      type: 'snapshot',
      snapshot: fixtureSnapshot(),
      changes: [],
      pending: [
        { address: address(base, 'left_hand', 'row0', 'Q'), value: 'Escape' },
        { op: 'remove', address: address(base, 'left_hand', 'row0', 'W') },
      ],
    });
    const picked: string[] = [];
    app.pickKey((text) => picked.push(text));
    keyElement(slotOf('left_hand', 'row0', 'W')).click();
    expect(picked).toEqual([]);
    expect(app.isPicking).toBe(true);
    keyElement(slotOf('left_hand', 'row0', 'Q')).click();
    expect(picked).toEqual(['Escape']);

    app.pickKey((text) => picked.push(text));
    keyElement(JSON.stringify([base, 'mapping', 'encoders', 'left', 'push'])).click();
    expect(picked).toEqual(['Escape', 'Mute']);
  });

  it('Esc か戻り値の関数で選ばずに抜ける。位置の名前の表示中でも名前の変更より選ぶほうが先', () => {
    app.receive({ type: 'snapshot', snapshot: fixtureSnapshot({ positionMap: POSITION_MAP_V02 }), changes: [] });
    const picked: string[] = [];
    app.pickKey((text) => picked.push(text));
    press(window, 'keydown', 'Escape');
    expect(app.isPicking).toBe(false);
    expect(root.querySelector<HTMLElement>('.pick-banner')?.hidden).toBe(true);

    const cancel = app.pickKey((text) => picked.push(text));
    cancel();
    expect(app.isPicking).toBe(false);
    keyElement(slotOf('left_hand', 'row0', 'Q')).click();
    expect(picked).toEqual([]);

    // 古い取り消しの関数は、あとから始めた選ぶ状態を抜けない
    const stale = app.pickKey((text) => picked.push(`old:${text}`));
    app.pickKey((text) => picked.push(text));
    stale();
    expect(app.isPicking).toBe(true);
    app.keyboardView.setPinned(true);
    keyElement(slotOf('left_hand', 'row0', 'E')).click();
    expect(picked).toEqual(['E']);
    expect(root.querySelector('.position-name-edit')).toBeNull();
  });
});

describe('comboHighlight と layerLineLabel', () => {
  it('sameKey は 16bit 値で、なければ正規形で比べる', () => {
    expect(sameKey(value('A'), { ...value('A'), text: 'KC_A' })).toBe(true);
    expect(sameKey(value('A'), value('B'))).toBe(false);
    expect(sameKey({ ...value('A'), code: null }, { ...value('A'), code: null })).toBe(true);
    expect(sameKey({ ...value('A'), code: null }, { ...value('B'), code: null })).toBe(false);
  });

  it('triggerKeys は書いていない・NoKey・解釈のないものを除き、effectiveKey は KC_TRNS をレイヤー 0 の値にする', () => {
    expect(triggerKeys([value('A'), null, undefined, value('NoKey')])).toEqual([value('A')]);
    expect(effectiveKey(value('Trans'), value('B'))).toEqual(value('B'));
    expect(effectiveKey(value('Trans'), value('NoKey'))).toBeNull();
    expect(effectiveKey(value('A'), value('B'))).toEqual(value('A'));
    expect(comboTargets([['a', value('A')], ['b', null], ['c', value('C')]], [value('A'), value('C')])).toEqual(new Set(['a', 'c']));
    expect(comboTargets([['a', value('A')]], [])).toEqual(new Set());
  });

  it('layerLineLabel は KC_TRNS・NoKey・書いていない位置で null、解釈のない値は表記のまま', () => {
    expect(layerLineLabel('', null)).toBeNull();
    expect(layerLineLabel('Trans', value('Trans'))).toBeNull();
    expect(layerLineLabel('NoKey', value('NoKey'))).toBeNull();
    expect(layerLineLabel('Foo', undefined)).toBe('Foo');
    expect(layerLineLabel('LGUI_T(KC_LANG2)', value('LGUI_T(KC_LANG2)'))).toBe('英数/⌘');
    expect(layerLineLabel('MO(3)', value('MO(3)'))).toBe(value('MO(3)').display.label);
  });
});
