// @vitest-environment happy-dom
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import type { Change } from '../../../src/protocol';
import { App, type ViewState } from '../../../src/webview/app';
import type { WebviewMessage } from '../../../src/webviewMessages';
import { FakeHost, fixtureSnapshot, settle } from './fakeHost';

const base = 'layers/0_base.yml';
const slotOf = (hand: string, group: string, symbol: string) => JSON.stringify([base, 'mapping', hand, group, symbol]);

let host: FakeHost;
let root: HTMLElement;
let app: App;
let rendered: Extract<WebviewMessage, { type: 'rendered' }>[];
let state: ViewState | undefined;

function keyElement(id: string): HTMLElement {
  const element = root.querySelector<HTMLElement>(`.board [data-slot='${id}']`);
  if (!element) throw new Error(`図に ${id} がない`);
  return element;
}

function field(id: string): HTMLElement {
  const element = root.querySelector<HTMLElement>(`.field[data-slot='${id}']`);
  if (!element) throw new Error(`欄に ${id} がない`);
  return element;
}

beforeEach(() => {
  host = new FakeHost();
  root = document.createElement('div');
  document.body.replaceChildren(root);
  rendered = [];
  state = undefined;
  app = new App(root, {
    host,
    onRendered: (message) => rendered.push(message),
    state: { get: () => state, set: (s) => (state = s) },
  });
});

afterEach(() => document.body.replaceChildren());

describe('App の描画', () => {
  it('キーボード図（全キーとエンコーダ）とレイヤーの編集画面を描く', () => {
    app.receive({ type: 'snapshot', snapshot: fixtureSnapshot(), changes: [] });
    expect(root.querySelectorAll('.board .key')).toHaveLength(48);
    expect(root.querySelectorAll('.board .encoder-part')).toHaveLength(6);
    expect(root.querySelectorAll('.layer-editor .field')).toHaveLength(54);
    expect(rendered.at(-1)).toEqual({ type: 'rendered', status: 'ok', layer: 0, keys: 48, encoders: 6, styled: false });
    expect(root.querySelector('.layer-tab.selected')?.textContent).toBe('0 Base');
  });

  it('2 役のキーはタップとホールドを上下に分け、同梱のショートカットにはアイコンを付ける', () => {
    app.receive({ type: 'snapshot', snapshot: fixtureSnapshot(), changes: [] });
    const space = keyElement(slotOf('left_hand', 'thumb_keys', 'middle'));
    expect(space.classList.contains('dual')).toBe(true);
    expect(space.querySelector('.key-tap')?.textContent).toBe('Space');
    expect(space.querySelector('.key-hold')?.textContent).toBe('L1');
    const palette = keyElement(slotOf('right_hand', 'row0', 'Y'));
    expect(palette.querySelector('[data-icon="material-icon-theme:vscode"]')).not.toBeNull();
    // 自分のショートカット（Symbols の Y）にはアイコンがない
    app.selectLayer(1);
    const own = root.querySelector<HTMLElement>(`.board [data-slot='${JSON.stringify(['layers/1_symbols.yml', 'mapping', 'right_hand', 'row0', 'Y'])}']`);
    expect(own?.textContent).toBe('⇧⌘[');
    expect(own?.querySelector('[data-icon]')).toBeNull();
  });

  it('レイヤーを選ぶと上下とも切り替わり、選んだレイヤーを覚える', () => {
    app.receive({ type: 'snapshot', snapshot: fixtureSnapshot(), changes: [] });
    root.querySelectorAll<HTMLElement>('.layer-tab')[1]?.click();
    expect(app.currentLayer).toBe(1);
    expect(state).toEqual({ layer: 1 });
    expect(root.querySelector('.layer-info h2')?.textContent).toContain('1 Symbols');
    expect(root.querySelector<HTMLInputElement>('.field input')?.value).toBe('Escape');
  });

  it('図のキーを押すと下の欄へ移り、選んだ欄を上下で共有する', () => {
    app.receive({ type: 'snapshot', snapshot: fixtureSnapshot(), changes: [] });
    const id = slotOf('left_hand', 'row1', 'A');
    keyElement(id).click();
    expect(app.selectedSlot).toBe(id);
    expect(keyElement(id).classList.contains('selected')).toBe(true);
    expect(field(id).classList.contains('selected')).toBe(true);
    expect(document.activeElement).toBe(field(id).querySelector('input'));
  });

  it('保存済みの検証の結果を欄と図に出し、ファイル全体の問題は一覧にする', () => {
    const id = slotOf('right_hand', 'row2', 'N');
    app.receive({
      type: 'snapshot',
      snapshot: fixtureSnapshot({
        diagnostics: [
          { severity: 'error', source: 'semantic', message: 'マクロ M20 が定義されていません', address: { file: base, path: ['mapping', 'right_hand', 'row2', 'N'] } },
          { severity: 'warning', source: 'semantic', message: 'ファイルの警告', file: 'layers/1_symbols.yml' },
        ],
      }),
      changes: [],
    });
    expect(keyElement(id).classList.contains('error')).toBe(true);
    expect(field(id).querySelector('.message-line.error')?.textContent).toBe('マクロ M20 が定義されていません');
    expect(root.querySelector('.problems summary')?.textContent).toBe('ファイルの問題（1 件）');
    root.querySelector<HTMLElement>('.problems .link-button')?.click();
    expect(host.opened).toEqual([{ file: 'layers/1_symbols.yml' }]);
  });
});

describe('App の変更', () => {
  it('欄で決めた値を Change として渡し、onchange で検証して図と欄に出す', async () => {
    app.receive({ type: 'snapshot', snapshot: fixtureSnapshot(), changes: [] });
    const id = slotOf('left_hand', 'row0', 'Q');
    const input = field(id).querySelector('input')!;
    input.focus();
    input.value = 'Foo(';
    input.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', cancelable: true }));
    expect(host.changes).toEqual([{ address: { file: base, path: ['mapping', 'left_hand', 'row0', 'Q'] }, value: 'Foo(' }]);
    expect(host.requests).toContainEqual({ method: 'keycode/inspect', params: { context: 'layerKey', text: 'Foo(' } });
    await settle(0);
    expect(field(id).querySelector('.key-input')?.classList.contains('error')).toBe(true);
    expect(field(id).querySelector('.message-line.error')?.textContent).toBe('「Foo(」は読めない表記です');
    expect(keyElement(id).classList.contains('error')).toBe(true);
    expect(keyElement(id).classList.contains('changed')).toBe(true);
    expect(root.querySelector('.pending')?.textContent).toBe('未保存の変更 1 件');
  });

  it('未保存の変更は解釈を聞いて図に描き、元に戻すと保存済みの値に戻る', async () => {
    const snapshot = fixtureSnapshot();
    app.receive({ type: 'snapshot', snapshot, changes: [] });
    const id = slotOf('left_hand', 'row0', 'Q');
    const change: Change = { address: { file: base, path: ['mapping', 'left_hand', 'row0', 'Q'] }, value: 'LT1(Space)' };
    app.receive({ type: 'snapshot', snapshot, changes: [change] });
    await settle(0);
    expect(keyElement(id).querySelector('.key-hold')?.textContent).toBe('L1');
    expect(field(id).querySelector('input')?.value).toBe('LT1(Space)');
    app.receive({ type: 'snapshot', snapshot, changes: [] });
    expect(keyElement(id).textContent).toBe('Q');
    expect(field(id).querySelector('input')?.value).toBe('Q');
    expect(field(id).classList.contains('changed')).toBe(false);
  });

  it('同じ snapshot なら作り直さない（入力欄のフォーカスが残る）', () => {
    const snapshot = fixtureSnapshot();
    app.receive({ type: 'snapshot', snapshot, changes: [] });
    const input = field(slotOf('left_hand', 'row0', 'W')).querySelector('input')!;
    input.focus();
    app.receive({ type: 'snapshot', snapshot: structuredClone(snapshot), changes: [] });
    expect(document.activeElement).toBe(input);
  });

  it('マウスを載せると inspect の説明を出す', async () => {
    app.receive({ type: 'snapshot', snapshot: fixtureSnapshot(), changes: [] });
    keyElement(slotOf('left_hand', 'row2', 'B')).dispatchEvent(new Event('mouseenter'));
    await settle(400);
    const tooltip = document.querySelector<HTMLElement>('.tooltip');
    expect(tooltip?.hidden).toBe(false);
    expect(tooltip?.querySelector('.tooltip-title')?.textContent).toBe('マクロ Bracket Pair（M0）');
    expect(tooltip?.textContent).toContain('tap: [ ] ←');
  });
});

describe('App の読めないプロファイル', () => {
  it('status: invalid ならエラーの一覧とファイルを開くボタンだけを出す', () => {
    const range = { start: { line: 7, character: 11 }, end: { line: 7, character: 28 } };
    app.receive({
      type: 'snapshot',
      snapshot: fixtureSnapshot({
        status: 'invalid',
        layers: [],
        positionMap: [],
        diagnostics: [
          { severity: 'error', source: 'structure', message: '読めない表記です', address: { file: base, path: ['mapping', 'left_hand', 'row0', 'tab'] }, range },
        ],
      }),
      changes: [],
    });
    expect(root.querySelector('.invalid h2')?.textContent).toBe('このプロファイルは読めませんでした');
    expect(root.querySelector('.board')).toBeNull();
    root.querySelector<HTMLElement>('.link-button')?.click();
    expect(host.opened).toEqual([{ file: base, range }]);
    expect(rendered.at(-1)?.status).toBe('invalid');
  });
});
