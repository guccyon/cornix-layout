// v0.4（tasks-v0.4.md の D3・「画面」）: 実機と比べた状態の表示。
// - DeviceBar: 図の上の「比べる」「反映」「戻す」のボタンと、印「実機: 同じ／違う N 件／未確認」。押すとホストに deviceAction を送る
//   （ホストがコマンドと同じことをする）。操作の最中（busy）はボタンを押せなくし、何をしているかを出す。
//   書き込みの許可（allowWrites）が false でも反映・戻すは出す（押すとホストが案内する。tasks-v0.4.md の「決めたこと」5・7）。
// - DeviceDiffSection: 図の下の畳める節「実機との差分」。行は「場所: 実機の値 → このプロファイルの値」で、押すと該当の欄へ移る（onReveal）。
// - 違いを図の欄・レイヤーのタブに結びつける関数（DOM に依存しない）。
// 状態はホストが送る（webviewMessages.ts の DeviceViewState）。画面は自分では比べない（自動では読まない。「決めたこと」6）。
import type { DeviceChange } from '../deviceProtocol';
import type { DeviceAction, DeviceViewState } from '../webviewMessages';
import { h, nodes } from './dom';
import { ENCODER_OPS, HAND_LABEL, type Slot } from './model';

/** ホストから状態が来る前（と v0.3 までのホスト）の状態 */
export const UNKNOWN_DEVICE_STATE: DeviceViewState = { status: 'unknown', changes: [], busy: null, allowWrites: false };

/** 違いを描く状態か（unknown・same では枠・点・行を出さない） */
export function deviceDifferences(state: DeviceViewState): DeviceChange[] {
  return state.status === 'different' ? state.changes : [];
}

/** 違いがその欄（レイヤー layer の欄）のものか。キーは論理位置、エンコーダは手と操作で比べる */
export function changeMatchesSlot(change: DeviceChange, slot: Pick<Slot, 'hand' | 'key' | 'encoder'>, layer: number | undefined): boolean {
  if (layer === undefined || change.layer !== layer) return false;
  if (change.kind === 'key') {
    const key = change.key;
    return !!key && !!slot.key && key.hand === slot.hand && key.row === slot.key.row && key.col === slot.key.col;
  }
  if (change.kind === 'encoder') {
    const encoder = change.encoder;
    return !!encoder && encoder.side === slot.hand && encoder.direction === slot.encoder;
  }
  return false;
}

/** 図の欄の id → その欄の違い（今のレイヤーの欄だけ） */
export function deviceSlotChanges(changes: readonly DeviceChange[], slots: readonly Slot[], layer: number | undefined): Map<string, DeviceChange> {
  const result = new Map<string, DeviceChange>();
  for (const change of changes) {
    const slot = slots.find((s) => changeMatchesSlot(change, s, layer));
    if (slot) result.set(slot.id, change);
  }
  return result;
}

/** レイヤーの番号 → そのレイヤーのキー・エンコーダの違いの数 */
export function deviceLayerCounts(changes: readonly DeviceChange[]): Map<number, number> {
  const counts = new Map<number, number>();
  for (const change of changes) {
    if ((change.kind !== 'key' && change.kind !== 'encoder') || change.layer === undefined) continue;
    counts.set(change.layer, (counts.get(change.layer) ?? 0) + 1);
  }
  return counts;
}

const ITEM_LABEL: Record<'macro' | 'tapDance' | 'combo', string> = { macro: 'マクロ', tapDance: 'タップダンス', combo: 'コンボ' };

/** 一覧の行の「場所」。キーは「レイヤー名 / 位置の名前」、エンコーダは「レイヤー名 / 左手 エンコーダの押し込み」 */
export function changePlace(change: DeviceChange, layerNames: ReadonlyMap<number, string>): string {
  const layer = change.layer === undefined ? '' : (layerNames.get(change.layer) ?? `レイヤー ${change.layer}`);
  switch (change.kind) {
    case 'key':
      return `${layer} / ${change.position ?? (change.key ? `${HAND_LABEL[change.key.hand]} (${change.key.row}, ${change.key.col})` : '?')}`;
    case 'encoder': {
      const encoder = change.encoder;
      const op = ENCODER_OPS.find((o) => o.op === encoder?.direction)?.label ?? encoder?.direction ?? '';
      return `${layer} / ${encoder ? HAND_LABEL[encoder.side] : ''} エンコーダの${op}`;
    }
    case 'macro':
    case 'tapDance':
    case 'combo': {
      const label = ITEM_LABEL[change.kind];
      if (change.name) return `${label} ${change.index !== undefined ? `${change.index} ` : ''}${change.name}`;
      return `${label} ${change.index ?? ''}`.trim();
    }
    case 'setting':
      return `設定 ${change.name ?? ''}`.trim();
    default:
      return '';
  }
}

/** 印の文（「実機: 同じ」など） */
export function deviceBadgeText(state: DeviceViewState): string {
  if (state.status === 'same') return '実機: 同じ';
  if (state.status === 'different') return `実機: 違う ${state.changes.length} 件`;
  return '実機: 未確認';
}

const BUSY_TEXT: Record<DeviceAction, string> = { compare: '実機と比べています…', apply: '実機に反映しています…', restore: '実機を戻しています…' };

const ACTIONS: { action: DeviceAction; label: string; title: string; writes: boolean }[] = [
  { action: 'compare', label: '比べる', title: '保存済みのプロファイルと実機を比べる（読むだけ。BLE で 10 秒ほどかかる）', writes: false },
  { action: 'apply', label: '反映', title: '保存済みのプロファイルを実機に書き込む（違いを確かめるダイアログのあと。書く前にバックアップを取る）', writes: true },
  { action: 'restore', label: '戻す', title: 'バックアップを選んで実機を戻す（確かめるダイアログのあと）', writes: true },
];

const LOCKED_TITLE = '\n書き込みは設定 cornix.device.allowWrites を有効にしたときだけ（押すと案内を出す）';

export type DeviceBarOptions = { onAction: (action: DeviceAction) => void };

/** 図の上のボタンと印 */
export class DeviceBar {
  readonly element: HTMLElement;
  private readonly buttons = new Map<DeviceAction, HTMLButtonElement>();
  private readonly badge = h('span', { class: 'device-badge', role: 'status' });

  constructor(options: DeviceBarOptions) {
    for (const { action, label } of ACTIONS) {
      const button = h('button', { type: 'button', class: 'device-button', 'data-device-action': action }, label);
      button.addEventListener('click', () => {
        if (!button.disabled) options.onAction(action);
      });
      this.buttons.set(action, button);
    }
    this.element = h('div', { class: 'device-bar', role: 'group', 'aria-label': '実機' }, this.badge, ...this.buttons.values());
    this.update(UNKNOWN_DEVICE_STATE);
  }

  update(state: DeviceViewState): void {
    const busy = state.busy;
    for (const { action, title, writes } of ACTIONS) {
      const button = this.buttons.get(action)!;
      button.disabled = busy !== null;
      const locked = writes && !state.allowWrites;
      button.classList.toggle('locked', locked);
      button.classList.toggle('running', busy === action);
      button.title = locked ? `${title}${LOCKED_TITLE}` : title;
    }
    this.element.classList.toggle('busy', busy !== null);
    this.badge.className = `device-badge ${busy ? 'busy' : state.status}`;
    this.badge.textContent = busy ? BUSY_TEXT[busy] : deviceBadgeText(state);
    this.badge.title =
      state.status === 'unknown' ? '実機とはまだ比べていません（保存すると未確認に戻る）。「比べる」で確かめる' : '最後に比べた（反映・戻した）ときの結果。保存すると未確認に戻る';
  }
}

export type DeviceDiffSectionOptions = {
  /** 行を押した（その欄へ移る） */
  onReveal: (change: DeviceChange) => void;
  /** 行を押して移れるか（移り先がない行は押せない文にする） */
  canReveal: (change: DeviceChange) => boolean;
};

/** 図の下の畳める節「実機との差分」 */
export class DeviceDiffSection {
  readonly element: HTMLElement;
  readonly details: HTMLDetailsElement;
  private readonly count = h('span', { class: 'device-diff-count' });
  private readonly body = h('div', { class: 'device-diff-list' });

  constructor(private readonly options: DeviceDiffSectionOptions) {
    this.details = h('details', { class: 'device-diff-details' }, h('summary', {}, h('span', { class: 'device-diff-title' }, '実機との差分'), this.count), this.body);
    this.element = h('section', { class: 'device-diff', 'aria-label': '実機との差分', hidden: true }, this.details);
  }

  update(state: DeviceViewState, layerNames: ReadonlyMap<number, string>): void {
    // 未確認のときは節を出さない（比べるまで何もない）
    this.element.hidden = state.status === 'unknown';
    const changes = deviceDifferences(state);
    this.count.textContent = state.status === 'different' ? `${changes.length} 件` : '';
    if (state.status !== 'different') {
      this.body.replaceChildren(...nodes(state.status === 'same' && h('p', { class: 'device-diff-empty' }, '実機と同じです')));
      return;
    }
    const header = h('div', { class: 'device-diff-legend', 'aria-hidden': 'true' }, '場所: 実機の値 → このプロファイルの値');
    this.body.replaceChildren(header, ...changes.map((change, i) => this.row(change, i, layerNames)));
  }

  private row(change: DeviceChange, index: number, layerNames: ReadonlyMap<number, string>): HTMLElement {
    if (change.kind === 'other') {
      return h('div', { class: 'device-diff-row other', 'data-change': index }, h('span', { class: 'device-diff-text' }, change.text));
    }
    const place = changePlace(change, layerNames);
    const content = [
      h('span', { class: 'device-diff-place' }, place),
      ': ',
      h('code', { class: 'device-diff-device', title: '実機の今の値' }, change.device),
      h('span', { class: 'device-diff-arrow' }, ' → '),
      h('code', { class: 'device-diff-profile', title: 'このプロファイルの値' }, change.profile),
    ];
    if (!this.options.canReveal(change)) return h('div', { class: 'device-diff-row', 'data-change': index, title: change.text }, ...content);
    const button = h('button', { type: 'button', class: 'device-diff-row', 'data-change': index, title: `${change.text}\n押すとその欄へ移る` }, ...content);
    button.addEventListener('click', () => this.options.onReveal(change));
    return button;
  }
}
