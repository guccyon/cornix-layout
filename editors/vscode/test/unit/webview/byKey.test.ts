// @vitest-environment happy-dom
// v0.4（issue #84）: 下の欄の「レイヤーごと / キーごと」の切り替え、キーごとの並べ方、レイヤーの追加と削除
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import type { LayerSnapshot, ProfileSnapshot } from '../../../src/protocol';
import { App, type ViewState } from '../../../src/webview/app';
import { hideTooltip } from '../../../src/webview/tooltip';
import { FakeHost, fixtureSnapshot } from './fakeHost';

const base = 'layers/0_base.yml';
const symbols = 'layers/1_symbols.yml';
const slotOf = (file: string, hand: string, group: string, symbol: string) => JSON.stringify([file, 'mapping', hand, group, symbol]);

let host: FakeHost;
let root: HTMLElement;
let app: App;
let state: ViewState | undefined;

function field(id: string): HTMLElement {
  const element = root.querySelector<HTMLElement>(`.layer-editor .field[data-slot='${id}']`);
  if (!element) throw new Error(`欄に ${id} がない`);
  return element;
}

function modeButton(mode: 'layer' | 'key'): HTMLButtonElement {
  return root.querySelector<HTMLButtonElement>(`.editor-mode [data-mode='${mode}']`)!;
}

/** ファイルを差し替えた（Address も差し替えた）レイヤーの写し */
function copyLayer(layer: LayerSnapshot, index: number, name: string, file: string): LayerSnapshot {
  const json = JSON.stringify(layer).split(JSON.stringify(layer.file)).join(JSON.stringify(file));
  return { ...(JSON.parse(json) as LayerSnapshot), index, name };
}

function withLayer(snapshot: ProfileSnapshot, layer: LayerSnapshot): ProfileSnapshot {
  return { ...snapshot, layers: [...snapshot.layers, layer] };
}

beforeEach(() => {
  host = new FakeHost();
  root = document.createElement('div');
  document.body.replaceChildren(root);
  state = undefined;
  app = new App(root, { host, state: { get: () => state, set: (s) => (state = s) } });
});

afterEach(() => {
  hideTooltip();
  document.body.replaceChildren();
});

describe('並べ方の切り替え', () => {
  it('既定はレイヤーごと。キーごとにすると位置ごとに全レイヤーの行を index の順に並べ、選んだ並べ方を覚える', () => {
    app.receive({ type: 'snapshot', snapshot: fixtureSnapshot(), changes: [] });
    expect(app.editorMode).toBe('layer');
    expect(modeButton('layer').getAttribute('aria-pressed')).toBe('true');
    expect(root.querySelector('.position-block')).toBeNull();

    modeButton('key').click();
    expect(app.editorMode).toBe('key');
    expect(state).toMatchObject({ mode: 'key' });
    expect(modeButton('key').getAttribute('aria-pressed')).toBe('true');
    const block = field(slotOf(base, 'left_hand', 'row0', 'Q')).closest<HTMLElement>('.position-block')!;
    expect(block.querySelector('.position-heading')?.textContent).toBe('Q');
    const rows = [...block.querySelectorAll<HTMLElement>('.layer-row')];
    expect(rows.map((row) => row.querySelector('.layer-row-label')?.textContent)).toEqual(['0 Base', '1 Symbols']);
    expect(rows.map((row) => row.querySelector('input')?.value)).toEqual(['Q', 'Question']);
    // グループの見出しはレイヤーごとと同じ
    expect([...root.querySelectorAll('.layer-editor .hand')].map((hand) => hand.querySelector('h3')?.textContent)).toEqual(['左手', '右手']);
    expect(root.querySelector('.layer-editor .group-label')?.textContent).toBe('1 段目');
    // エンコーダも操作ごとにレイヤーの行
    const encoder = root.querySelectorAll('.layer-editor .hand')[0]!.querySelectorAll('.group');
    const encoderBlocks = encoder[encoder.length - 1]!.querySelectorAll('.position-block');
    expect([...encoderBlocks].map((b) => b.querySelector('.position-heading')?.textContent)).toEqual(['左回し', '押し込み', '右回し']);
    expect(encoderBlocks[0]!.querySelectorAll('.layer-row')).toHaveLength(2);

    modeButton('layer').click();
    expect(root.querySelector('.position-block')).toBeNull();
    expect(state?.mode).toBeUndefined();
  });

  it('覚えた並べ方で開き、外での変更で形が変わっても（レイヤーが増えても）キーごとのまま', () => {
    state = { mode: 'key' };
    app = new App(root, { host, state: { get: () => state, set: (s) => (state = s) } });
    const snapshot = fixtureSnapshot();
    app.receive({ type: 'snapshot', snapshot, changes: [] });
    expect(root.querySelectorAll('.position-block').length).toBeGreaterThan(0);
    const grown = withLayer(snapshot, copyLayer(snapshot.layers[1]!, 2, 'Extra', 'layers/2_extra.yml'));
    app.receive({ type: 'snapshot', snapshot: grown, changes: [] });
    expect(app.editorMode).toBe('key');
    const block = field(slotOf(base, 'left_hand', 'row0', 'Q')).closest('.position-block')!;
    expect([...block.querySelectorAll('.layer-row-label')].map((label) => label.textContent)).toEqual(['0 Base', '1 Symbols', '2 Extra']);
  });

  it('図で選んでいるレイヤーの行を強調し、レイヤーを変えても下の欄は作り直さない', () => {
    app.receive({ type: 'snapshot', snapshot: fixtureSnapshot(), changes: [] });
    app.setMode('key');
    const q0 = field(slotOf(base, 'left_hand', 'row0', 'Q'));
    const q1 = field(slotOf(symbols, 'left_hand', 'row0', 'Q'));
    expect(q0.classList.contains('current-layer')).toBe(true);
    expect(q1.classList.contains('current-layer')).toBe(false);
    const input = q1.querySelector('input')!;
    app.selectLayer(1);
    expect(q1.querySelector('input')).toBe(input);
    expect(q1.classList.contains('current-layer')).toBe(true);
    expect(q0.classList.contains('current-layer')).toBe(false);
    // 図はレイヤー 1 を描く
    expect(root.querySelector(`.board [data-slot='${slotOf(symbols, 'left_hand', 'row0', 'Q')}']`)).not.toBeNull();
  });

  it('図のキーを押すと、その位置の選んでいるレイヤーの行へ移る。ほかのレイヤーの行を選ぶと図では同じ位置のキーを選ぶ', () => {
    app.receive({ type: 'snapshot', snapshot: fixtureSnapshot(), changes: [] });
    app.setMode('key');
    app.selectLayer(1);
    const id = slotOf(symbols, 'left_hand', 'row1', 'A');
    root.querySelector<HTMLElement>(`.board [data-slot='${id}']`)!.click();
    expect(app.selectedSlot).toBe(id);
    expect(document.activeElement).toBe(field(id).querySelector('input'));

    const other = slotOf(base, 'left_hand', 'row1', 'A');
    field(other).querySelector('input')!.dispatchEvent(new Event('focus'));
    expect(app.selectedSlot).toBe(other);
    expect(field(other).classList.contains('selected')).toBe(true);
    expect(root.querySelector(`.board [data-slot='${id}']`)!.classList.contains('selected')).toBe(true);
  });

  it('ほかのレイヤーの行で決めた値は、そのレイヤーの Address の Change になる（約束は今と同じ）', () => {
    app.receive({ type: 'snapshot', snapshot: fixtureSnapshot(), changes: [] });
    app.setMode('key');
    const id = slotOf(symbols, 'left_hand', 'row0', 'W');
    const input = field(id).querySelector('input')!;
    input.focus();
    input.value = 'Escape';
    input.dispatchEvent(new Event('input'));
    input.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', cancelable: true }));
    expect(host.changes).toEqual([{ address: { file: symbols, path: ['mapping', 'left_hand', 'row0', 'W'] }, value: 'Escape' }]);
    expect(field(id).classList.contains('changed')).toBe(true);
    // 図（レイヤー 0）の同じ位置は変わらない
    expect(field(slotOf(base, 'left_hand', 'row0', 'W')).classList.contains('changed')).toBe(false);
  });

  it('「▽ と空欄を畳む」は ▽ と書いていない行に印を付け、選んだことを覚える', () => {
    app.receive({ type: 'snapshot', snapshot: fixtureSnapshot(), changes: [] });
    expect(root.querySelector('.fold-quiet-input')).toBeNull();
    app.setMode('key');
    const fold = root.querySelector<HTMLInputElement>('.fold-quiet-input')!;
    fold.checked = true;
    fold.dispatchEvent(new Event('change'));
    expect(state).toMatchObject({ mode: 'key', foldQuiet: true });
    expect(root.querySelector('.layer-editor')!.classList.contains('fold-quiet')).toBe(true);
    // lctrl: レイヤー 1 は Trans、W: レイヤー 1 は書いていない
    expect(field(slotOf(symbols, 'left_hand', 'row1', 'lctrl')).classList.contains('quiet')).toBe(true);
    expect(field(slotOf(symbols, 'left_hand', 'row0', 'W')).classList.contains('quiet')).toBe(true);
    expect(field(slotOf(symbols, 'left_hand', 'row0', 'Q')).classList.contains('quiet')).toBe(false);
    app.setMode('layer');
    expect(root.querySelector('.layer-editor')!.classList.contains('fold-quiet')).toBe(false);
  });
});

describe('レイヤーの追加と削除', () => {
  it('並びの末尾の「＋」で空いている番号と名前を選んで足し、足したレイヤーが現れたら選ぶ', () => {
    const snapshot = fixtureSnapshot();
    app.receive({ type: 'snapshot', snapshot, changes: [] });
    const add = root.querySelector<HTMLButtonElement>('.layer-tabs [data-layer-add]')!;
    expect(add.textContent).toBe('＋');
    add.click();
    const select = root.querySelector<HTMLSelectElement>('.layer-form select')!;
    expect([...select.options].map((o) => o.value)).toEqual(['2', '3', '4', '5', '6', '7', '8', '9']);
    const name = root.querySelector<HTMLInputElement>('.layer-form .item-name-input')!;
    // 名前の決まり（空・重なり）
    root.querySelector<HTMLButtonElement>('.layer-form .primary')!.click();
    expect(root.querySelector('.layer-form .message-line')?.textContent).toBe('名前を入れてください');
    name.value = 'Base';
    root.querySelector<HTMLButtonElement>('.layer-form .primary')!.click();
    expect(root.querySelector('.layer-form .message-line')?.textContent).toBe('「Base」はもうあります');
    select.value = '5';
    name.value = 'Mouse';
    name.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', cancelable: true }));
    expect(host.itemEdits).toEqual([{ op: 'create', kind: 'layer', name: 'Mouse', index: 5 }]);
    expect(root.querySelector('.layer-form')).toBeNull();

    app.receive({ type: 'snapshot', snapshot: withLayer(snapshot, copyLayer(snapshot.layers[1]!, 5, 'Mouse', 'layers/5_mouse.yml')), changes: [] });
    expect(app.currentLayer).toBe(5);
    expect(root.querySelector('.layer-tab.selected')?.textContent).toBe('5 Mouse');
  });

  it('空いている番号がなければ「＋」は押せない', () => {
    const snapshot = fixtureSnapshot();
    const layers = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9].map((index) => copyLayer(snapshot.layers[0]!, index, `L${index}`, `layers/${index}_l.yml`));
    app.receive({ type: 'snapshot', snapshot: { ...snapshot, layers }, changes: [] });
    expect(root.querySelector<HTMLButtonElement>('.layer-tabs [data-layer-add]')!.disabled).toBe(true);
  });

  it('見出しの「レイヤーを削除」は選んでいるレイヤーを消す操作をホストに渡す（確認とファイルの削除はホスト）', () => {
    app.receive({ type: 'snapshot', snapshot: fixtureSnapshot(), changes: [] });
    app.selectLayer(1);
    root.querySelector<HTMLButtonElement>('.layer-info .layer-delete')!.click();
    expect(host.itemEdits).toEqual([{ op: 'delete', kind: 'layer', name: 'Symbols' }]);
  });
});
