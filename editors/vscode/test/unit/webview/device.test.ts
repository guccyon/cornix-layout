// @vitest-environment happy-dom
// v0.4（tasks-v0.4.md の D3）: 実機と比べた状態の画面。ボタンと印、違うキーの橙の枠、レイヤーのタブの点、「実機との差分」の節と行から欄へ移る動き
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import type { DeviceChange } from '../../../src/deviceProtocol';
import { App } from '../../../src/webview/app';
import { changePlace, deviceBadgeText } from '../../../src/webview/deviceView';
import { MacroEditor } from '../../../src/webview/macroEditor';
import { addressKey } from '../../../src/webview/model';
import { SettingsEditor } from '../../../src/webview/settingsEditor';
import { hideTooltip } from '../../../src/webview/tooltip';
import type { DeviceViewState } from '../../../src/webviewMessages';
import * as data from '../../fake-server/fixtures';
import { FakeHost, fixtureSnapshot } from './fakeHost';
import { MACRO, PRESET_MACRO } from './itemFixtures';

/** 偽の device のサーバーの既定の違いと同じもの（test/fake-device-server/server.ts の DEFAULT_DIFFERENCES に text を足した） */
const CHANGES: DeviceChange[] = [
  { kind: 'key', layer: 0, key: { hand: 'left', row: 0, col: 1 }, position: 'Q', device: 'KC_A', profile: 'KC_Q', text: 'レイヤー0 (0,1): KC_A → KC_Q' },
  { kind: 'key', layer: 0, key: { hand: 'right', row: 1, col: 5 }, position: 'enter', device: 'KC_NO', profile: 'KC_ENTER', text: 'レイヤー0 (1,11): KC_NO → KC_ENTER' },
  { kind: 'key', layer: 1, key: { hand: 'left', row: 0, col: 0 }, position: 'tab', device: 'KC_TRNS', profile: 'KC_ESCAPE', text: 'レイヤー1 (0,0): KC_TRNS → KC_ESCAPE' },
  { kind: 'encoder', layer: 0, encoder: { side: 'left', direction: 'cw' }, device: 'KC_NO', profile: 'KC_VOLU', text: 'レイヤー0 エンコーダ0 時計回り: KC_NO → KC_VOLU' },
  { kind: 'macro', index: 0, name: 'Bracket Pair', device: '(空)', profile: '[ ] ←', text: 'マクロ M0: [] → [...]' },
  { kind: 'setting', name: 'tapping_term', device: '200', profile: '180', text: '設定 7: 200 → 180' },
  { kind: 'other', device: '', profile: '', text: 'レイヤー0 (4,0): KC_NO → KC_A' },
];

const different = (overrides: Partial<DeviceViewState> = {}): DeviceViewState => ({ status: 'different', changes: CHANGES, busy: null, allowWrites: true, ...overrides });

function keyId(layer: number, hand: 'left' | 'right', row: number, col: number): string {
  const key = data.LAYERS.find((l) => l.index === layer)!.keys.find((k) => k.hand === hand && k.row === row && k.col === col)!;
  return addressKey(key.address);
}

function encoderId(layer: number, hand: 'left' | 'right', op: 'cw' | 'ccw' | 'push'): string {
  return addressKey(data.LAYERS.find((l) => l.index === layer)!.encoders[hand][op].address);
}

let host: FakeHost;
let root: HTMLElement;
let app: App;
let revealed: DeviceChange[];

const badge = () => root.querySelector<HTMLElement>('.device-badge')!;
const actionButton = (action: string) => root.querySelector<HTMLButtonElement>(`[data-device-action='${action}']`)!;
const section = () => root.querySelector<HTMLElement>('section.device-diff')!;
const rows = () => [...root.querySelectorAll<HTMLElement>('.device-diff-row')];
const tab = (layer: number) => root.querySelector<HTMLElement>(`.layer-tab[data-layer='${layer}']`)!;
const deviceDot = (layer: number) => tab(layer).querySelector('.layer-tab-dot.device');

beforeEach(() => {
  host = new FakeHost();
  root = document.createElement('div');
  document.body.replaceChildren(root);
  revealed = [];
  app = new App(root, { host, revealItem: (change) => revealed.push(change) });
  app.receive({ type: 'snapshot', snapshot: fixtureSnapshot(), changes: [] });
});

afterEach(() => {
  hideTooltip();
  document.body.replaceChildren();
});

describe('ボタンと印', () => {
  it('ホストから状態が来る前は「未確認」。ボタンは図の上の並び（位置の名前のボタンの前）にあり、押すと deviceAction を送る', () => {
    expect(badge().textContent).toBe('実機: 未確認');
    const toggles = root.querySelector('.keyboard-toggles')!;
    expect(toggles.querySelector('.device-bar')).not.toBeNull();
    expect(toggles.lastElementChild?.classList.contains('position-toggle')).toBe(true);
    for (const action of ['compare', 'apply', 'restore']) actionButton(action).click();
    expect(host.deviceActions).toEqual(['compare', 'apply', 'restore']);
  });

  it('印は状態ごとに「同じ」「違う N 件」「未確認」', () => {
    app.receive({ type: 'device', state: { status: 'same', changes: [], busy: null, allowWrites: false } });
    expect(badge().textContent).toBe('実機: 同じ');
    app.receive({ type: 'device', state: different() });
    expect(badge().textContent).toBe('実機: 違う 7 件');
    expect(badge().classList.contains('different')).toBe(true);
    app.receive({ type: 'device', state: { status: 'unknown', changes: [], busy: null, allowWrites: true } });
    expect(badge().textContent).toBe('実機: 未確認');
    expect(deviceBadgeText(different({ changes: [] }))).toBe('実機: 違う 0 件');
  });

  it('busy の間はボタンを押せず、何をしているかを印に出す', () => {
    app.receive({ type: 'device', state: different({ busy: 'apply' }) });
    expect(badge().textContent).toBe('実機に反映しています…');
    for (const action of ['compare', 'apply', 'restore']) expect(actionButton(action).disabled).toBe(true);
    expect(actionButton('apply').classList.contains('running')).toBe(true);
    actionButton('compare').click();
    expect(host.deviceActions).toEqual([]);

    app.receive({ type: 'device', state: { status: 'unknown', changes: [], busy: 'compare', allowWrites: true } });
    expect(badge().textContent).toBe('実機と比べています…');
    app.receive({ type: 'device', state: different() });
    expect(actionButton('compare').disabled).toBe(false);
  });

  it('書き込みを許可していなくても反映・戻すは押せる（見た目で分かる印と説明を付ける）', () => {
    app.receive({ type: 'device', state: different({ allowWrites: false }) });
    expect(actionButton('apply').classList.contains('locked')).toBe(true);
    expect(actionButton('restore').classList.contains('locked')).toBe(true);
    expect(actionButton('compare').classList.contains('locked')).toBe(false);
    expect(actionButton('apply').title).toContain('cornix.device.allowWrites');
    actionButton('apply').click();
    expect(host.deviceActions).toEqual(['apply']);
    app.receive({ type: 'device', state: different({ allowWrites: true }) });
    expect(actionButton('apply').classList.contains('locked')).toBe(false);
  });

  it('snapshot の前に状態が来ても、snapshot を描いたあとに枠を出す', () => {
    const other = document.createElement('div');
    document.body.append(other);
    const late = new App(other, { host });
    late.receive({ type: 'device', state: different() });
    late.receive({ type: 'snapshot', snapshot: fixtureSnapshot(), changes: [] });
    expect(late.keyboardView.deviceDiffIds.sort()).toEqual([keyId(0, 'left', 0, 1), keyId(0, 'right', 1, 5), encoderId(0, 'left', 'cw')].sort());
  });
});

describe('違うキーの枠とレイヤーのタブの点', () => {
  it('different: 今のレイヤーの違うキーとエンコーダの操作を囲み、読み上げに実機の値を添える', () => {
    app.receive({ type: 'device', state: different() });
    const ids = app.keyboardView.deviceDiffIds;
    expect(ids.sort()).toEqual([keyId(0, 'left', 0, 1), keyId(0, 'right', 1, 5), encoderId(0, 'left', 'cw')].sort());
    const q = root.querySelector<HTMLElement>(`.board [data-slot='${keyId(0, 'left', 0, 1)}']`)!;
    expect(q.getAttribute('aria-label')).toContain('実機は KC_A');
    expect(root.querySelector(`.board [data-slot='${keyId(0, 'left', 0, 0)}']`)!.classList.contains('device-diff')).toBe(false);
  });

  it('違いのあるレイヤーのタブに点（件数はツールチップ）。レイヤーを選び直すと、そのレイヤーの違うキーを囲む', () => {
    app.receive({ type: 'device', state: different() });
    expect(deviceDot(0)).not.toBeNull();
    expect(deviceDot(1)).not.toBeNull();
    expect(tab(1).title).toContain('実機と違うキー 1 件');
    expect(tab(0).title).toContain('実機と違うキー 3 件');

    app.selectLayer(1);
    expect(app.keyboardView.deviceDiffIds).toEqual([keyId(1, 'left', 0, 0)]);
    expect(deviceDot(0)).not.toBeNull();
  });

  it('違いがないレイヤーには点を付けない', () => {
    app.receive({ type: 'device', state: different({ changes: CHANGES.filter((c) => c.layer !== 1) }) });
    expect(deviceDot(0)).not.toBeNull();
    expect(deviceDot(1)).toBeNull();
  });

  it('キー別の並べ方でも、図は今のレイヤーの違うキーを囲む', () => {
    app.setMode('key');
    app.receive({ type: 'device', state: different() });
    app.selectLayer(1);
    expect(app.keyboardView.deviceDiffIds).toEqual([keyId(1, 'left', 0, 0)]);
  });

  it('same・unknown では枠も点も出さず、different から戻ったら消す', () => {
    app.receive({ type: 'device', state: different() });
    app.receive({ type: 'device', state: { status: 'same', changes: [], busy: null, allowWrites: true } });
    expect(app.keyboardView.deviceDiffIds).toEqual([]);
    expect(root.querySelector('.layer-tab-dot.device')).toBeNull();
    // unknown なのに changes が来ても描かない
    app.receive({ type: 'device', state: { status: 'unknown', changes: CHANGES, busy: null, allowWrites: true } });
    expect(app.keyboardView.deviceDiffIds).toEqual([]);
    expect(root.querySelector('.layer-tab-dot.device')).toBeNull();
  });

  it('snapshot を受け直しても（保存・外での変更）枠を保つ', () => {
    app.receive({ type: 'device', state: different() });
    app.receive({ type: 'snapshot', snapshot: fixtureSnapshot({ files: { 'layers/0_base.yml': 'sha256:01' } }), changes: [] });
    expect(app.keyboardView.deviceDiffIds).toHaveLength(3);
  });
});

describe('「実機との差分」の節', () => {
  it('unknown では節を出さず、same では「実機と同じです」', () => {
    expect(section().hidden).toBe(true);
    app.receive({ type: 'device', state: { status: 'same', changes: [], busy: null, allowWrites: true } });
    expect(section().hidden).toBe(false);
    expect(section().textContent).toContain('実機と同じです');
    expect(rows()).toHaveLength(0);
  });

  it('different: 行は「場所: 実機の値 → このプロファイルの値」。キーは「レイヤー名 / 位置の名前」、other は text', () => {
    app.receive({ type: 'device', state: different() });
    expect(section().querySelector('details')!.open).toBe(false);
    expect(section().querySelector('.device-diff-count')!.textContent).toBe('7 件');
    const texts = rows().map((row) => row.textContent);
    expect(texts).toEqual([
      'Base / Q: KC_A → KC_Q',
      'Base / enter: KC_NO → KC_ENTER',
      'Symbols / tab: KC_TRNS → KC_ESCAPE',
      'Base / 左手 エンコーダの右回し: KC_NO → KC_VOLU',
      'マクロ 0 Bracket Pair: (空) → [ ] ←',
      '設定 tapping_term: 200 → 180',
      'レイヤー0 (4,0): KC_NO → KC_A',
    ]);
    // other は移り先がないので押せない
    expect(rows()[6]!.tagName).toBe('DIV');
    expect(rows()[0]!.tagName).toBe('BUTTON');
  });

  it('プロファイルにないレイヤーの違いは番号で出し、押せない', () => {
    const change: DeviceChange = { kind: 'key', layer: 5, key: { hand: 'left', row: 0, col: 0 }, position: 'tab', device: 'KC_A', profile: 'KC_TRNS', text: '' };
    app.receive({ type: 'device', state: different({ changes: [change] }) });
    expect(rows()[0]!.textContent).toBe('レイヤー 5 / tab: KC_A → KC_TRNS');
    expect(rows()[0]!.tagName).toBe('DIV');
    expect(changePlace({ kind: 'tapDance', index: 4, name: 'Tab Escape', device: '', profile: '', text: '' }, new Map())).toBe('タップダンス 4 Tab Escape');
    expect(changePlace({ kind: 'combo', index: 2, device: '', profile: '', text: '' }, new Map())).toBe('コンボ 2');
  });

  it('キーの行を押すと、そのレイヤーを選んでその位置の欄へ移る', () => {
    app.receive({ type: 'device', state: different() });
    rows()[2]!.click();
    expect(app.currentLayer).toBe(1);
    expect(app.selectedSlot).toBe(keyId(1, 'left', 0, 0));
    expect(root.querySelector(`.board [data-slot='${keyId(1, 'left', 0, 0)}']`)!.classList.contains('selected')).toBe(true);
    expect(document.activeElement).toBe(app.inputs.get(keyId(1, 'left', 0, 0))!.input);

    rows()[3]!.click();
    expect(app.currentLayer).toBe(0);
    expect(app.selectedSlot).toBe(encoderId(0, 'left', 'cw'));
  });

  it('マクロ・設定の行は revealItem に渡す', () => {
    app.receive({ type: 'device', state: different() });
    rows()[4]!.click();
    rows()[5]!.click();
    expect(revealed.map((c) => c.kind)).toEqual(['macro', 'setting']);
  });

  it('revealItem がなければ項目の行は押せない', () => {
    const other = document.createElement('div');
    document.body.append(other);
    const bare = new App(other, { host });
    bare.receive({ type: 'snapshot', snapshot: fixtureSnapshot(), changes: [] });
    bare.receive({ type: 'device', state: different() });
    const list = [...other.querySelectorAll<HTMLElement>('.device-diff-row')];
    expect(list[4]!.tagName).toBe('DIV');
    expect(list[0]!.tagName).toBe('BUTTON');
  });

  it('開いた節は状態が変わっても開いたまま', () => {
    app.receive({ type: 'device', state: different() });
    section().querySelector('details')!.open = true;
    app.receive({ type: 'device', state: different({ changes: CHANGES.slice(0, 2) }) });
    expect(section().querySelector('details')!.open).toBe(true);
    expect(rows()).toHaveLength(2);
  });
});

describe('下の節へ移る（main.ts の revealItem の先）', () => {
  it('マクロの節: 番号で探して選び、節を開く。番号がなければ名前で探す', () => {
    const macros = new MacroEditor({ host });
    document.body.append(macros.element);
    macros.update(fixtureSnapshot({ macros: [MACRO, PRESET_MACRO] }), []);
    expect(macros.details.open).toBe(false);
    expect(macros.reveal({ index: PRESET_MACRO.index, name: 'ちがう名前' })).toBe(true);
    expect(macros.selected).toBe(PRESET_MACRO.name);
    expect(macros.details.open).toBe(true);
    expect((document.activeElement as HTMLElement).dataset.item).toBe(PRESET_MACRO.name);
    expect(macros.reveal({ name: MACRO.name })).toBe(true);
    expect(macros.selected).toBe(MACRO.name);
    expect(macros.reveal({ index: 99 })).toBe(false);
  });

  it('QMK 設定の節: 節を開いてその設定の欄にフォーカスする', () => {
    const settings = new SettingsEditor({ onCommit: () => undefined });
    document.body.append(settings.element);
    settings.update(fixtureSnapshot(), []);
    const details = settings.element.querySelector('details')!;
    expect(details.open).toBe(false);
    expect(settings.reveal('tapping_term')).toBe(true);
    expect(details.open).toBe(true);
    expect(document.activeElement).toBe(settings.input(addressKey({ file: 'settings/qmk_settings.yaml', path: ['keyboard', 'tapping_term'] })));
    expect(settings.reveal('keyboard.permissive_hold')).toBe(true);
    expect(settings.reveal('no_such_setting')).toBe(false);
  });
});
