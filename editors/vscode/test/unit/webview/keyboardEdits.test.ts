// @vitest-environment happy-dom
// v0.2 の図とレイヤーの欄（E2）: 位置の名前の表示と名前の変更、KC_TRNS の下のレイヤーの値、割り当てを消す操作と注記の欄
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import type { AnyChange, PositionMapEntry } from '../../../src/protocol';
import { App } from '../../../src/webview/app';
import { hideTooltip } from '../../../src/webview/tooltip';
import * as data from '../../fake-server/fixtures';
import { FakeHost, fixtureSnapshot, settle } from './fakeHost';

const base = 'layers/0_base.yml';
const symbols = 'layers/1_symbols.yml';
const address = (file: string, hand: string, group: string, symbol: string) => ({ file, path: ['mapping', hand, group, symbol] });
const slotOf = (hand: string, group: string, symbol: string, file = base) => JSON.stringify([file, 'mapping', hand, group, symbol]);

/** v0.2 のサーバーの position_map（名前を書いている場所付き） */
const POSITION_MAP_V02: PositionMapEntry[] = data.POSITION_MAP.map((entry) => {
  const index = data.POSITION_MAP.filter((e) => e.hand === entry.hand && e.group === entry.group).indexOf(entry);
  return { ...entry, address: { file: 'position_map.yaml', path: [`${entry.hand}_hand`, entry.group, index] } };
});

let host: FakeHost;
let root: HTMLElement;
let app: App;

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

describe('位置の名前の表示', () => {
  it('図の上のボタンで固定して切り替え、キーの面と読み上げを位置の名前にする', () => {
    app.receive({ type: 'snapshot', snapshot: fixtureSnapshot(), changes: [] });
    const tab = keyElement(slotOf('left_hand', 'row0', 'tab'));
    const toggle = root.querySelector<HTMLButtonElement>('.keyboard-toolbar .position-toggle')!;
    expect(toggle.getAttribute('aria-pressed')).toBe('false');
    expect(tab.querySelector('.td-windows')).not.toBeNull();

    toggle.click();
    expect(toggle.getAttribute('aria-pressed')).toBe('true');
    expect(root.querySelector('.board')?.classList.contains('show-positions')).toBe(true);
    expect(tab.querySelector('.position-name')?.textContent).toBe('tab');
    expect(tab.querySelector('.td-windows')).toBeNull();
    expect(tab.classList.contains('windowed')).toBe(false);
    expect(tab.getAttribute('aria-label')).toBe('左手 位置の名前 tab');
    // エンコーダには位置の名前がないので割り当てのまま
    expect(root.querySelector('.encoder-part .position-name')).toBeNull();

    toggle.click();
    expect(tab.querySelector('.position-name')).toBeNull();
    expect(tab.querySelector('.td-windows')).not.toBeNull();
    expect(tab.getAttribute('aria-label')).toContain('タップダンス');
  });

  it('Alt を押している間だけ一時表示し、離すかウィンドウがフォーカスを失ったら戻す', () => {
    app.receive({ type: 'snapshot', snapshot: fixtureSnapshot(), changes: [] });
    const q = keyElement(slotOf('left_hand', 'row0', 'Q'));
    press(window, 'keydown', 'Alt');
    expect(q.querySelector('.position-name')?.textContent).toBe('Q');
    press(window, 'keyup', 'Alt');
    expect(q.querySelector('.position-name')).toBeNull();
    press(window, 'keydown', 'Alt');
    window.dispatchEvent(new Event('blur'));
    expect(q.querySelector('.position-name')).toBeNull();
    // 固定しているときは Alt を離しても出したまま
    app.keyboardView.setPinned(true);
    press(window, 'keydown', 'Alt');
    press(window, 'keyup', 'Alt');
    expect(q.querySelector('.position-name')?.textContent).toBe('Q');
  });

  it('表示を切り替えている間も、値を変えたら戻したときに新しい値を描く', async () => {
    app.receive({ type: 'snapshot', snapshot: fixtureSnapshot(), changes: [] });
    app.keyboardView.setPinned(true);
    const id = slotOf('left_hand', 'row0', 'Q');
    app.receive({ type: 'snapshot', snapshot: fixtureSnapshot(), changes: [{ address: address(base, 'left_hand', 'row0', 'Q'), value: 'Escape' }] });
    await settle(0);
    expect(keyElement(id).textContent).toBe('Q');
    app.keyboardView.setPinned(false);
    expect(keyElement(id).textContent).toBe('Esc');
  });

  it('キーの欄のラベルは位置の名前の色の印（position-label）、エンコーダの欄には付けない。マクロの印は mark-macro', () => {
    app.receive({ type: 'snapshot', snapshot: fixtureSnapshot(), changes: [] });
    expect(field(slotOf('left_hand', 'row0', 'Q')).querySelector('.field-label')?.classList.contains('position-label')).toBe(true);
    const encoder = JSON.stringify([base, 'mapping', 'encoders', 'left', 'push']);
    expect(field(encoder).querySelector('.field-label')?.classList.contains('position-label')).toBe(false);
    expect(keyElement(slotOf('left_hand', 'row2', 'B')).querySelector('.key-mark.mark-macro')?.textContent).toBe('M');
  });
});

describe('位置の名前の変更', () => {
  it('v0.1 のサーバー（positionMap に address がない）では入口を出さない', () => {
    app.receive({ type: 'snapshot', snapshot: fixtureSnapshot(), changes: [] });
    expect(root.querySelector('.rename-position')).toBeNull();
    // 位置の名前を出していても、キーを押せばふつうに下の欄へ移る
    app.keyboardView.setPinned(true);
    const id = slotOf('left_hand', 'row0', 'Q');
    keyElement(id).click();
    expect(app.selectedSlot).toBe(id);
    expect(root.querySelector('.position-name-input')).toBeNull();
  });

  it('欄のラベルの ✎ から名前を変え、Enter で host.itemEdit の renamePosition を呼ぶ', () => {
    app.receive({ type: 'snapshot', snapshot: fixtureSnapshot({ positionMap: POSITION_MAP_V02 }), changes: [] });
    const id = slotOf('left_hand', 'row0', 'tab');
    const button = field(id).querySelector<HTMLButtonElement>('.rename-position')!;
    expect(button.getAttribute('aria-label')).toBe('位置の名前 tab を変える');
    // エンコーダの欄には出さない
    expect(field(JSON.stringify([base, 'mapping', 'encoders', 'left', 'push'])).querySelector('.rename-position')).toBeNull();
    button.click();
    const input = field(id).querySelector<HTMLInputElement>('.position-name-input')!;
    expect(input.value).toBe('tab');
    expect(document.activeElement).toBe(input);
    input.value = 'esc';
    press(input, 'keydown', 'Enter');
    expect(host.itemEdits).toEqual([{ op: 'renamePosition', hand: 'left', row: 0, col: 0, to: 'esc' }]);
    expect(field(id).querySelector('.position-name-input')).toBeNull();
    expect(field(id).querySelector('.field-label')?.textContent).toBe('tab');
  });

  it('同じ段にある名前・空の名前は送らずに理由を出し、Escape でやめる', () => {
    app.receive({ type: 'snapshot', snapshot: fixtureSnapshot({ positionMap: POSITION_MAP_V02 }), changes: [] });
    const id = slotOf('left_hand', 'row0', 'tab');
    field(id).querySelector<HTMLButtonElement>('.rename-position')!.click();
    const input = field(id).querySelector<HTMLInputElement>('.position-name-input')!;
    input.value = 'Q';
    press(input, 'keydown', 'Enter');
    expect(host.itemEdits).toEqual([]);
    expect(field(id).querySelector('.position-name-message')?.textContent).toBe('同じ段に「Q」があります');
    expect(input.getAttribute('aria-invalid')).toBe('true');
    input.value = '  ';
    press(input, 'keydown', 'Enter');
    expect(field(id).querySelector('.position-name-message')?.textContent).toBe('名前を入れてください');
    press(input, 'keydown', 'Escape');
    expect(field(id).querySelector('.position-name-input')).toBeNull();
    expect(host.itemEdits).toEqual([]);
    // 別の段（右手の row0）の名前と同じでもよい
    field(id).querySelector<HTMLButtonElement>('.rename-position')!.click();
    const again = field(id).querySelector<HTMLInputElement>('.position-name-input')!;
    again.value = 'Y';
    press(again, 'keydown', 'Enter');
    expect(host.itemEdits).toEqual([{ op: 'renamePosition', hand: 'left', row: 0, col: 0, to: 'Y' }]);
  });

  it('位置の名前を出している間に図のキーを押すと、その欄で名前を変え始める', () => {
    app.receive({ type: 'snapshot', snapshot: fixtureSnapshot({ positionMap: POSITION_MAP_V02 }), changes: [] });
    app.keyboardView.setPinned(true);
    const id = slotOf('right_hand', 'thumb_keys', 'middle');
    keyElement(id).click();
    expect(app.selectedSlot).toBe(id);
    const input = field(id).querySelector<HTMLInputElement>('.position-name-input');
    expect(input?.value).toBe('middle');
    expect(document.activeElement).toBe(input);
  });
});

describe('KC_TRNS の下のレイヤーの値', () => {
  const lctrl = slotOf('left_hand', 'row1', 'lctrl', symbols);

  it('レイヤー 0 の同じ位置の値を薄く描き、読み上げと説明に「レイヤー 0 の値」と添える', async () => {
    app.receive({ type: 'snapshot', snapshot: fixtureSnapshot(), changes: [] });
    app.selectLayer(1);
    const key = keyElement(lctrl);
    expect(key.querySelector('.key-label.base-value')?.textContent).toBe('⌃');
    expect(key.getAttribute('aria-label')).toBe('左手 lctrl: ▽（レイヤー 0 の値 ⌃）');
    key.dispatchEvent(new Event('mouseenter'));
    await settle(400);
    expect(document.querySelector('.tooltip .tooltip-base')?.textContent).toBe('レイヤー 0 の値: ⌃（LCtrl）');
  });

  it('レイヤー 0 そのものでは出さず、下の値が NoKey なら ▽ のまま', async () => {
    const snapshot = fixtureSnapshot();
    app.receive({ type: 'snapshot', snapshot, changes: [{ address: address(base, 'left_hand', 'row0', 'Q'), value: 'Trans' }] });
    await settle(0);
    expect(keyElement(slotOf('left_hand', 'row0', 'Q')).querySelector('.base-value')).toBeNull();
    // Symbols の R は NoKey。レイヤー 0 の R を NoKey にした snapshot で、Symbols の別の位置を Trans にして確かめる
    const layers = structuredClone(snapshot.layers);
    const r = layers[0]!.keys.find((k) => k.hand === 'left' && k.row === 0 && k.col === 4)!;
    r.value = data.interpret('NoKey');
    const s = layers[1]!.keys.find((k) => k.hand === 'left' && k.row === 0 && k.col === 4)!;
    s.value = data.interpret('Trans');
    app.receive({ type: 'snapshot', snapshot: fixtureSnapshot({ layers }), changes: [] });
    app.selectLayer(1);
    const key = keyElement(slotOf('left_hand', 'row0', 'R', symbols));
    expect(key.querySelector('.base-value')).toBeNull();
    expect(key.textContent).toBe('▽');
  });
});

describe('割り当てを消す操作と注記の欄', () => {
  const q = slotOf('left_hand', 'row0', 'Q');
  const qAddress = address(base, 'left_hand', 'row0', 'Q');
  const thumb = slotOf('left_hand', 'thumb_keys', 'left');
  const thumbAddress = address(base, 'left_hand', 'thumb_keys', 'left');

  it('「割り当てを消す」で host.edit の remove を送り、欄は空（placeholder なし）、図は点線の枠（unassigned）', () => {
    app.receive({ type: 'snapshot', snapshot: fixtureSnapshot(), changes: [] });
    const remove = field(q).querySelector<HTMLButtonElement>('.remove-assignment')!;
    expect(remove.getAttribute('aria-label')).toBe('左手 Qの割り当てを消す');
    remove.click();
    expect(host.edits).toEqual([{ op: 'remove', address: qAddress }]);
    const input = field(q).querySelector<HTMLInputElement>('.key-input-field')!;
    expect(input.value).toBe('');
    expect(input.placeholder).toBe('');
    expect(keyElement(q).classList.contains('unassigned')).toBe(true);
    expect(keyElement(q).classList.contains('changed')).toBe(true);
    expect(keyElement(q).getAttribute('aria-label')).toBe('左手 Q: 割り当てなし');
    expect(remove.disabled).toBe(true);
    expect(root.querySelector('.pending')?.textContent).toBe('未保存の変更 1 件');
  });

  it('割り当てのない位置では「割り当てを消す」と注記の欄を使えない', () => {
    app.receive({ type: 'snapshot', snapshot: fixtureSnapshot(), changes: [] });
    app.selectLayer(1);
    const w = slotOf('left_hand', 'row0', 'W', symbols);
    expect(field(w).querySelector<HTMLButtonElement>('.remove-assignment')?.disabled).toBe(true);
    expect(field(w).querySelector<HTMLInputElement>('.note-input')?.disabled).toBe(true);
  });

  it('注記を書くと host.change に field: "note"、空にすると host.edit の注記だけの remove', () => {
    app.receive({ type: 'snapshot', snapshot: fixtureSnapshot(), changes: [] });
    const note = field(thumb).querySelector<HTMLInputElement>('.note-input')!;
    expect(note.value).toBe('タップで英数、押している間は Command');
    expect(field(thumb).classList.contains('has-note')).toBe(true);
    note.focus();
    note.value = '  英数と Command  ';
    note.dispatchEvent(new Event('input'));
    press(note, 'keydown', 'Enter');
    expect(host.changes).toEqual([{ address: thumbAddress, value: '英数と Command', field: 'note' }]);
    expect(note.value).toBe('英数と Command');
    expect(field(thumb).classList.contains('changed')).toBe(true);

    note.value = '';
    note.dispatchEvent(new Event('input'));
    note.dispatchEvent(new Event('blur'));
    expect(host.edits).toEqual([{ op: 'remove', address: thumbAddress, field: 'note' }]);
    expect(field(thumb).classList.contains('has-note')).toBe(false);

    // 注記のない欄に書く
    const qNote = field(q).querySelector<HTMLInputElement>('.note-input')!;
    qNote.value = 'メモ';
    qNote.dispatchEvent(new Event('input'));
    press(qNote, 'keydown', 'Enter');
    expect(host.changes.at(-1)).toEqual({ address: qAddress, value: 'メモ', field: 'note' });
  });

  it('Escape で打ちかけの注記を戻す（送らない）', () => {
    app.receive({ type: 'snapshot', snapshot: fixtureSnapshot(), changes: [] });
    const note = field(q).querySelector<HTMLInputElement>('.note-input')!;
    note.value = 'メモ';
    note.dispatchEvent(new Event('input'));
    press(note, 'keydown', 'Escape');
    note.dispatchEvent(new Event('blur'));
    expect(note.value).toBe('');
    expect(host.changes).toEqual([]);
  });

  it('ホストの pending（remove と注記）を反映し、pending があれば changes は使わない', async () => {
    const pending: AnyChange[] = [
      { op: 'remove', address: qAddress },
      { address: address(base, 'left_hand', 'row0', 'W'), value: 'メモ', field: 'note' },
      { op: 'remove', address: thumbAddress, field: 'note' },
    ];
    app.receive({
      type: 'snapshot',
      snapshot: fixtureSnapshot(),
      changes: [{ address: address(base, 'left_hand', 'row0', 'E'), value: 'Escape' }],
      pending,
    });
    await settle(0);
    expect(field(q).querySelector<HTMLInputElement>('.key-input-field')?.value).toBe('');
    expect(keyElement(q).classList.contains('unassigned')).toBe(true);
    const w = slotOf('left_hand', 'row0', 'W');
    expect(field(w).querySelector<HTMLInputElement>('.note-input')?.value).toBe('メモ');
    expect(field(w).classList.contains('changed')).toBe(true);
    // 割り当ては変えていないので解釈は聞き直さない
    expect(keyElement(w).textContent).toBe('W');
    expect(field(thumb).querySelector<HTMLInputElement>('.note-input')?.value).toBe('');
    expect(field(slotOf('left_hand', 'row0', 'E')).querySelector<HTMLInputElement>('.key-input-field')?.value).toBe('E');
    expect(root.querySelector('.pending')?.textContent).toBe('未保存の変更 3 件');
  });

  it('消したあとに値を入れれば set を足し、空にして決めても消さずに「割り当てを消す」を案内する', () => {
    app.receive({ type: 'snapshot', snapshot: fixtureSnapshot(), changes: [] });
    const input = field(q).querySelector<HTMLInputElement>('.key-input-field')!;
    input.focus();
    input.value = '';
    input.dispatchEvent(new Event('input'));
    press(input, 'keydown', 'Enter');
    expect(input.value).toBe('Q');
    expect(field(q).querySelector('.message-line.hint')?.textContent).toContain('割り当てを消す');
    expect(host.edits).toEqual([]);

    field(q).querySelector<HTMLButtonElement>('.remove-assignment')!.click();
    input.value = 'Q';
    input.dispatchEvent(new Event('input'));
    press(input, 'keydown', 'Enter');
    expect(host.changes).toEqual([{ address: qAddress, value: 'Q' }]);
    // 行を消したあとの set なので、保存済みと同じ値でも未保存の変更に残る
    expect(root.querySelector('.pending')?.textContent).toBe('未保存の変更 2 件');
  });
});
