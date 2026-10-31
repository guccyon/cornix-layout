// @vitest-environment happy-dom
// v0.4（tasks-v0.4.md の D3）: 実機への反映の画面。編集フォームの一番下の節「デバイス転送」と、反映のプレビューのモーダル
// （図の橙の枠・レイヤーのタブの件数・違いの一覧・確定とやめる・検証のエラー・古いプレビュー・読む間と書く間）
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { CORNIX } from '../../../src/keyboard/cornix';
import type { DeviceChange } from '../../../src/deviceProtocol';
import { App } from '../../../src/webview/app';
import type { DevicePlan } from '../../../src/deviceProtocol';
import { changePlace, readingSummary, snapshotErrors, transferDescription, transferProgressText } from '../../../src/webview/deviceView';
import { addressKey } from '../../../src/webview/model';
import { hideTooltip } from '../../../src/webview/tooltip';
import type { DeviceTransfer, DeviceViewState } from '../../../src/webviewMessages';
import * as data from '../../fake-server/fixtures';
import { FakeHost, fixtureSnapshot } from './fakeHost';

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

const PLAN: DevicePlan = { token: 'tok', empty: false, changes: CHANGES, warnings: [], keyboard: { name: 'Cornix (fake)', uid: '1' } };

const preview = (overrides: Partial<Extract<DeviceTransfer, { step: 'preview' }>> = {}, state: Partial<DeviceViewState> = {}): DeviceViewState => ({
  transfer: { step: 'preview', plan: PLAN, profile: 'default', stale: false, ...overrides },
  busyElsewhere: false,
  allowWrites: true,
  ...state,
});

const idle = (state: Partial<DeviceViewState> = {}): DeviceViewState => ({ transfer: null, busyElsewhere: false, allowWrites: true, ...state });

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

const section = () => root.querySelector<HTMLElement>('section.device-transfer')!;
const previewButton = () => section().querySelector<HTMLButtonElement>('.device-preview-button')!;
const modal = () => document.querySelector<HTMLElement>('.device-modal-backdrop')!;
const dialog = () => modal().querySelector<HTMLElement>('[role=dialog]')!;
const footerButton = (action: string) => modal().querySelector<HTMLButtonElement>(`.device-modal-footer [data-device-action='${action}']`);
const footerLabels = () => [...modal().querySelectorAll<HTMLButtonElement>('.device-modal-footer button')].map((b) => [b.textContent, b.disabled]);
const rows = () => [...modal().querySelectorAll<HTMLElement>('.device-diff-row')];
const modalTab = (layer: number) => modal().querySelector<HTMLElement>(`.device-modal-tabs .layer-tab[data-layer='${layer}']`)!;

beforeEach(() => {
  host = new FakeHost();
  root = document.createElement('div');
  document.body.replaceChildren(root);
  app = new App(root, { keyboard: CORNIX, host });
  app.receive({ type: 'snapshot', snapshot: fixtureSnapshot(), changes: [] });
});

afterEach(() => {
  hideTooltip();
  document.body.replaceChildren();
});

describe('節「デバイス転送」', () => {
  it('編集フォームの一番下にあり、最初は畳んでいる。「反映のプレビュー…」で preview を送る', () => {
    const pane = root.querySelector('.bottom-pane')!;
    expect(pane.lastElementChild).toBe(section());
    expect(section().querySelector('details')!.open).toBe(false);
    expect(section().querySelector('h2')!.textContent).toBe('デバイス転送');
    previewButton().click();
    expect(host.deviceActions).toEqual(['preview']);
  });

  it('保存済みのプロファイルに検証のエラーがあれば「反映のプレビュー…」を押せず、横に理由を出す。直せば押せる', () => {
    expect(section().querySelector<HTMLElement>('.device-transfer-blocked')!.hidden).toBe(true);
    const diagnostics = [
      { severity: 'error' as const, source: 'semantic' as const, message: '知らないキーコードです: KC_FOO', file: 'layers/0_base.yml' },
      { severity: 'warning' as const, source: 'semantic' as const, message: 'w' },
    ];
    app.receive({ type: 'snapshot', snapshot: fixtureSnapshot({ diagnostics }), changes: [] });
    expect(previewButton().disabled).toBe(true);
    const blocked = section().querySelector<HTMLElement>('.device-transfer-blocked')!;
    expect(blocked.hidden).toBe(false);
    expect(blocked.textContent).toBe('検証のエラーが 1 件あるので反映できません。先にエラーを直して保存してください。');
    // 状態が変わってもエラーのあいだは押せない
    app.receive({ type: 'device', state: idle({ allowWrites: false }) });
    expect(previewButton().disabled).toBe(true);
    app.receive({ type: 'snapshot', snapshot: fixtureSnapshot(), changes: [] });
    expect(previewButton().disabled).toBe(false);
    expect(blocked.hidden).toBe(true);
  });

  it('検証のエラーと警告を節に一覧で出し（エラーが先、場所はファイルとキーの位置）、見出しに件数を出す。警告だけなら押せる', () => {
    const count = () => section().querySelector<HTMLElement>('.device-transfer-count')!;
    expect(count().hidden).toBe(true);
    expect(section().querySelector('.device-transfer-clean')!.textContent).toBe('保存済みのプロファイルに検証の問題はありません。');
    const warning = {
      severity: 'warning' as const,
      source: 'semantic' as const,
      message: '定義されていないレイヤー 9 を参照しています',
      address: { file: 'layers/4_ipad_base.yml', path: ['mapping', 'encoders', 'right', 'push'] },
    };
    app.receive({ type: 'snapshot', snapshot: fixtureSnapshot({ diagnostics: [warning] }), changes: [] });
    expect(previewButton().disabled).toBe(false);
    expect(count().hidden).toBe(false);
    expect(count().textContent).toBe('警告 1 件');
    expect(section().querySelector('.device-transfer-problems-title')!.textContent).toContain('警告だけなので反映できます');
    const rowsOf = () => [...section().querySelectorAll<HTMLElement>('.device-transfer-problems .problem')];
    expect(rowsOf().map((row) => row.querySelector('.problem-file')!.textContent)).toEqual(['layers/4_ipad_base.yml: mapping.encoders.right.push']);
    // 編集フォームにないファイル（このテストの App には下の節もない）は、ファイルを開く
    rowsOf()[0]!.querySelector<HTMLButtonElement>('.link-button')!.click();
    expect(host.opened.at(-1)).toMatchObject({ file: 'layers/4_ipad_base.yml' });

    const error = { severity: 'error' as const, source: 'semantic' as const, message: '知らないキーコードです: KC_FOO', file: 'layers/0_base.yml' };
    app.receive({ type: 'snapshot', snapshot: fixtureSnapshot({ diagnostics: [warning, error] }), changes: [] });
    expect(count().textContent).toBe('エラー 1 件・警告 1 件');
    expect(rowsOf().map((row) => row.classList.contains('error'))).toEqual([true, false]);
    expect(previewButton().disabled).toBe(true);
  });

  it('図の上に実機のボタンはない', () => {
    expect(root.querySelector('.keyboard-toggles .device-bar')).toBeNull();
    expect(root.querySelector('[data-device-action]')).toBeNull();
  });

  it('反映の途中とほかのプロファイルの途中は押せない。書き込みを許していなければ案内を出す', () => {
    app.receive({ type: 'device', state: idle({ allowWrites: false }) });
    expect(previewButton().disabled).toBe(false);
    expect(section().querySelector<HTMLElement>('.device-transfer-note')!.hidden).toBe(false);
    app.receive({ type: 'device', state: idle({ busyElsewhere: true }) });
    expect(previewButton().disabled).toBe(true);
    expect(section().querySelector<HTMLElement>('.device-transfer-note')!.hidden).toBe(true);
    app.receive({ type: 'device', state: preview() });
    expect(previewButton().disabled).toBe(true);
    previewButton().click();
    expect(host.deviceActions).toEqual([]);
  });
});

describe('反映のプレビューのモーダル', () => {
  it('transfer がなければ出さない。出している間は編集画面に inert を付ける', () => {
    expect(modal().hidden).toBe(true);
    expect(root.hasAttribute('inert')).toBe(false);
    app.receive({ type: 'device', state: preview() });
    expect(modal().hidden).toBe(false);
    expect(dialog().getAttribute('aria-modal')).toBe('true');
    expect(root.hasAttribute('inert')).toBe(true);
    expect(modal().parentElement).toBe(document.body);
    app.receive({ type: 'device', state: idle() });
    expect(modal().hidden).toBe(true);
    expect(root.hasAttribute('inert')).toBe(false);
  });

  it('読んでいる間: 進み具合と「やめる」', () => {
    app.receive({ type: 'device', state: { transfer: { step: 'reading', progress: { done: 2, total: 4 } }, busyElsewhere: false, allowWrites: true } });
    expect(dialog().querySelector('h2')!.textContent).toBe('実機を読んでいます');
    expect(dialog().querySelector('.device-modal-progress')!.textContent).toBe('実機を読んでいます（2/4）');
    expect(footerLabels()).toEqual([['やめる', false]]);
    footerButton('cancel')!.click();
    expect(host.deviceActions).toEqual(['cancel']);
    expect(transferProgressText({ step: 'reading', progress: null })).toBe('実機を読んでいます…');
  });

  it('プレビュー: 書き込み先・件数、図は違いのある最初のレイヤーで違うキーとエンコーダの操作を囲む', () => {
    app.receive({ type: 'device', state: preview() });
    expect(dialog().querySelector('h2')!.textContent).toBe('実機への反映のプレビュー');
    expect(dialog().querySelector('.device-modal-summary')!.textContent).toContain('Cornix (fake)');
    expect(dialog().querySelector('.device-modal-summary')!.textContent).toContain('違い: 7 件');
    expect(app.transfer.currentLayer).toBe(0);
    expect(app.transfer.keyboardView.deviceDiffIds.sort()).toEqual([keyId(0, 'left', 0, 1), keyId(0, 'right', 1, 5), encoderId(0, 'left', 'cw')].sort());
    const q = dialog().querySelector<HTMLElement>(`.board [data-slot='${keyId(0, 'left', 0, 1)}']`)!;
    expect(q.getAttribute('aria-label')).toContain('実機は KC_A');
    // 編集画面の図には枠を出さない
    expect(app.keyboardView.deviceDiffIds).toEqual([]);
  });

  it('レイヤーのタブに違いの件数。押すとそのレイヤーの図にする', () => {
    app.receive({ type: 'device', state: preview() });
    expect(modalTab(0).querySelector('.device-tab-count')!.textContent).toBe('3');
    expect(modalTab(1).querySelector('.device-tab-count')!.textContent).toBe('1');
    modalTab(1).click();
    expect(app.transfer.currentLayer).toBe(1);
    expect(app.transfer.keyboardView.deviceDiffIds).toEqual([keyId(1, 'left', 0, 0)]);
    expect(modalTab(1).getAttribute('aria-pressed')).toBe('true');
    // 編集画面のレイヤーは変えない
    expect(app.currentLayer).toBe(0);
  });

  it('一覧: 「場所: 実機の値 → このプロファイルの値」。キーの行を押すと図のそのキーを示す', () => {
    app.receive({ type: 'device', state: preview() });
    expect(rows().map((row) => row.textContent)).toEqual([
      'Base / Q: KC_A → KC_Q',
      'Base / enter: KC_NO → KC_ENTER',
      'Symbols / tab: KC_TRNS → KC_ESCAPE',
      'Base / 左手 エンコーダの右回し: KC_NO → KC_VOLU',
      'マクロ 0 Bracket Pair: (空) → [ ] ←',
      '設定 tapping_term: 200 → 180',
      'レイヤー0 (4,0): KC_NO → KC_A',
    ]);
    expect(rows()[4]!.tagName).toBe('DIV');
    expect(rows()[6]!.tagName).toBe('DIV');
    rows()[2]!.click();
    expect(app.transfer.currentLayer).toBe(1);
    expect(dialog().querySelector(`.board [data-slot='${keyId(1, 'left', 0, 0)}']`)!.classList.contains('selected')).toBe(true);
    expect(rows()[2]!.classList.contains('selected')).toBe(true);
    // 編集画面は動かさない
    expect(app.selectedSlot).toBeUndefined();
  });

  it('プロファイルにないレイヤーの違いは番号で出し、図には出さない', () => {
    const change: DeviceChange = { kind: 'key', layer: 5, key: { hand: 'left', row: 0, col: 0 }, position: 'tab', device: 'KC_A', profile: 'KC_TRNS', text: '' };
    app.receive({ type: 'device', state: preview({ plan: { ...PLAN, changes: [change] } }) });
    expect(rows()[0]!.textContent).toBe('レイヤー 5 / tab: KC_A → KC_TRNS');
    expect(rows()[0]!.tagName).toBe('DIV');
    expect(dialog().querySelector<HTMLElement>('.device-modal-board')!.hidden).toBe(true);
    expect(changePlace({ kind: 'tapDance', index: 4, name: 'Tab Escape', device: '', profile: '', text: '' }, new Map(), CORNIX)).toBe('タップダンス 4 Tab Escape');
    expect(changePlace({ kind: 'combo', index: 2, device: '', profile: '', text: '' }, new Map(), CORNIX)).toBe('コンボ 2');
  });

  it('「確定」で confirm、「やめる」と Esc で cancel', () => {
    app.receive({ type: 'device', state: preview() });
    expect(footerLabels()).toEqual([
      ['やめる', false],
      ['確定（7 件を書き込む）', false],
    ]);
    footerButton('confirm')!.click();
    footerButton('cancel')!.click();
    modal().dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }));
    expect(host.deviceActions).toEqual(['confirm', 'cancel', 'cancel']);
  });

  it('警告を出す', () => {
    app.receive({ type: 'device', state: preview({ plan: { ...PLAN, warnings: ['KC_FOO は RMK が対応していません'] } }) });
    expect(dialog().querySelector('.device-modal-warnings')!.textContent).toContain('KC_FOO は RMK が対応していません');
  });

  it('書き込みを許していなければ確定は押せず、設定を開くボタンを出す。許したら押せる', () => {
    app.receive({ type: 'device', state: preview({}, { allowWrites: false }) });
    expect(footerButton('confirm')!.disabled).toBe(true);
    const locked = dialog().querySelector<HTMLElement>('.device-modal-locked')!;
    expect(locked.textContent).toContain('cornix.device.allowWrites');
    locked.querySelector('button')!.click();
    expect(host.deviceActions).toEqual(['openSettings']);
    app.receive({ type: 'device', state: preview() });
    expect(footerButton('confirm')!.disabled).toBe(false);
    expect(dialog().querySelector('.device-modal-locked')).toBeNull();
  });

  it('検証のエラーがあるあいだは確定を押せず、理由を出す', () => {
    const diagnostics = [{ severity: 'error' as const, source: 'semantic' as const, message: '知らないキーコードです: KC_FOO', file: 'layers/0_base.yml' }];
    app.receive({ type: 'snapshot', snapshot: fixtureSnapshot({ diagnostics }), changes: [] });
    app.receive({ type: 'device', state: preview() });
    expect(footerButton('confirm')!.disabled).toBe(true);
    expect(dialog().querySelector('.device-modal-errors')!.textContent).toContain('検証のエラーが 1 件');
    // 直して保存したら押せる
    app.receive({ type: 'snapshot', snapshot: fixtureSnapshot(), changes: [] });
    expect(footerButton('confirm')!.disabled).toBe(false);
    expect(dialog().querySelector('.device-modal-errors')).toBeNull();
    expect(snapshotErrors({ status: 'invalid', diagnostics: [] })).toBe(1);
    expect(snapshotErrors({ status: 'ok', diagnostics: [{ severity: 'warning', source: 'semantic', message: 'w' }] })).toBe(0);
  });

  it('レイヤーのキー・エンコーダの問題は「キーを表示」で、そのレイヤーに切り替えて編集フォームの欄にフォーカスする（ファイルは開かない）', () => {
    const diagnostics = [
      { severity: 'warning' as const, source: 'semantic' as const, message: 'レイヤー 9 が定義されていません', address: { file: 'layers/1_symbols.yml', path: ['mapping', 'encoders', 'right', 'push'] } },
      { severity: 'warning' as const, source: 'semantic' as const, message: 'レイヤー全体の問題', file: 'layers/1_symbols.yml' },
    ];
    app.receive({ type: 'snapshot', snapshot: fixtureSnapshot({ diagnostics }), changes: [] });
    const reveal = [...section().querySelectorAll<HTMLButtonElement>('.device-transfer-problems .problem-reveal')];
    expect(reveal.map((b) => b.textContent)).toEqual(['キーを表示', '表示']);
    expect(section().querySelectorAll('.device-transfer-problems .problem .link-button:not(.problem-reveal)')).toHaveLength(0);
    reveal[0]!.click();
    expect(host.opened).toEqual([]);
    expect(root.querySelector('.layer-tabs .layer-tab[data-layer="1"]')!.getAttribute('aria-pressed')).toBe('true');
    expect(document.activeElement?.closest<HTMLElement>('.field')?.dataset.slot).toBe(encoderId(1, 'right', 'push'));
  });

  it('検証の警告はモーダルにも一覧で出し、確定は押せる', () => {
    const diagnostics = [
      { severity: 'warning' as const, source: 'semantic' as const, message: '定義されていないレイヤー 9 を参照しています', address: { file: 'layers/4_ipad_base.yml', path: ['mapping', 'encoders', 'right', 'push'] } },
    ];
    app.receive({ type: 'snapshot', snapshot: fixtureSnapshot({ diagnostics }), changes: [] });
    app.receive({ type: 'device', state: preview() });
    const validation = dialog().querySelector<HTMLElement>('.device-modal-validation')!;
    expect(validation.textContent).toContain('検証の警告が 1 件あります（確定はできます）');
    expect(validation.querySelector('li')!.textContent).toBe('layers/4_ipad_base.yml: mapping.encoders.right.push: 定義されていないレイヤー 9 を参照しています');
    expect(footerButton('confirm')!.disabled).toBe(false);
  });

  it('古いプレビュー: 確定の代わりに「もう一度比べる」（preview を送る）', () => {
    app.receive({ type: 'device', state: preview({ stale: true }) });
    expect(dialog().querySelector('.device-modal-stale')).not.toBeNull();
    expect(footerButton('confirm')).toBeNull();
    footerButton('preview')!.click();
    expect(host.deviceActions).toEqual(['preview']);
  });

  it('違いがなければ「同じです」と「閉じる」だけ', () => {
    app.receive({ type: 'device', state: preview({ plan: { ...PLAN, empty: true, changes: [] } }) });
    expect(dialog().querySelector('h2')!.textContent).toBe('実機はこのプロファイルと同じです');
    expect(footerLabels()).toEqual([['閉じる', false]]);
    expect(rows()).toHaveLength(0);
  });

  it('書いている間: 進み具合を出し、ボタンはどれも押せない。Esc も効かない', () => {
    const writing = (progress: Extract<DeviceTransfer, { step: 'writing' }>['progress']): DeviceViewState => ({
      transfer: { step: 'writing', plan: PLAN, profile: 'default', progress },
      busyElsewhere: false,
      allowWrites: true,
    });
    app.receive({ type: 'device', state: writing({ phase: 'write', done: 1, total: 7 }) });
    expect(dialog().querySelector('h2')!.textContent).toBe('実機に書き込んでいます');
    expect(dialog().querySelector('.device-modal-progress')!.textContent).toBe('書き込んでいます（1/7）');
    expect(footerLabels().every(([, disabled]) => disabled)).toBe(true);
    modal().dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }));
    expect(host.deviceActions).toEqual([]);
    app.receive({ type: 'device', state: writing({ phase: 'read', done: 3, total: 9 }) });
    expect(dialog().querySelector('.device-modal-progress')!.textContent).toBe('書く前に実機を読み直しています（3/9）');
  });

  it('進み具合が変わっても図と一覧は作り直さない（選んだレイヤーを保つ）', () => {
    app.receive({ type: 'device', state: preview() });
    modalTab(1).click();
    const list = rows()[0];
    app.receive({ type: 'device', state: { transfer: { step: 'writing', plan: PLAN, profile: 'default', progress: { phase: 'write', done: 1, total: 7 } }, busyElsewhere: false, allowWrites: true } });
    expect(app.transfer.currentLayer).toBe(1);
    expect(rows()[0]).toBe(list);
  });

  it('snapshot の前に状態が来ても、snapshot が来たら図を描く', () => {
    document.body.replaceChildren();
    const other = document.createElement('div');
    document.body.append(other);
    const late = new App(other, { keyboard: CORNIX, host });
    late.receive({ type: 'device', state: preview() });
    expect(late.transfer.isOpen).toBe(true);
    late.receive({ type: 'snapshot', snapshot: fixtureSnapshot(), changes: [] });
    expect(late.transfer.keyboardView.deviceDiffIds).toHaveLength(3);
  });
});

describe('キーボードの表示名（KeyboardSpec の displayName）', () => {
  const description = () => section().querySelector('.device-transfer-description')!.textContent;
  const summary = () => dialog().querySelector('.device-modal-summary')!.textContent;
  const reading = (target: App) => target.receive({ type: 'device', state: { transfer: { step: 'reading', progress: null }, busyElsewhere: false, allowWrites: true } });

  it('Cornix では今までの文言のまま', () => {
    expect(description()).toBe(
      '保存済みのプロファイルを、接続中の Cornix に書き込みます。押すと実機を読んで（Bluetooth では 10 秒ほど）違いをプレビューし、「確定」を押すまでは書き込みません。未保存の変更があれば先に保存します。',
    );
    reading(app);
    expect(summary()).toBe('保存済みのプロファイルと比べるため、接続中の Cornix を読んでいます（読むだけ。Bluetooth では 10 秒ほど）。');
  });

  it('表示名を変えた spec では、節の説明と読んでいる間の文がその名前になる', () => {
    document.body.replaceChildren();
    root = document.createElement('div');
    document.body.append(root);
    const other = new App(root, { keyboard: { ...CORNIX, displayName: 'Other Board' }, host });
    other.receive({ type: 'snapshot', snapshot: fixtureSnapshot(), changes: [] });
    expect(description()).toContain('接続中の Other Board に書き込みます');
    expect(description()).not.toContain('Cornix');
    reading(other);
    expect(summary()).toBe('保存済みのプロファイルと比べるため、接続中の Other Board を読んでいます（読むだけ。Bluetooth では 10 秒ほど）。');
    expect(transferDescription('X')).toContain('接続中の X に');
    expect(readingSummary('X')).toContain('接続中の X を');
  });
});
