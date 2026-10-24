// v0.4（tasks-v0.4.md の「画面」）: 実機への反映（プレビュー → 確定）。
// - TransferSection: 編集フォームの一番下の畳める節「デバイス転送」。「反映のプレビュー…」を押すとホストに deviceAction('preview') を送る。
//   保存済みのプロファイルに検証のエラーがあれば押せなくし、横に理由を出す（実機を読む 10 秒を無駄にしない）。
//   押す前に気づけるよう、検証のエラーと警告の一覧も節に出す（警告だけなら押せる。見出しにも件数）。
// - TransferDialog: ホストの transfer がある間に出すモーダル。読んでいる間は進み具合と「やめる」。プレビューでは
//   図（違うキー・エンコーダの操作を橙の枠）・レイヤーのタブ（違いの件数）・違いの一覧・「確定」「やめる」。書いている間は進み具合（取り消せない）。
//   開いている間は編集画面を操作できない（App が編集画面に inert を付ける）。
// - 違いを図の欄・レイヤーに結びつける関数（DOM に依存しない）。
// 状態はホストが送る（webviewMessages.ts の DeviceViewState）。画面は自分では読まない・書かない。
import type { DeviceChange } from '../deviceProtocol';
import type { Diagnostic, LayerSnapshot, ProfileSnapshot } from '../protocol';
import type { DeviceAction, DeviceTransfer, DeviceViewState } from '../webviewMessages';
import { h, nodes } from './dom';
import { KeyboardView } from './keyboardView';
import { ENCODER_OPS, HAND_LABEL, baseLayerValue, layerSlots, layerTitle, type Slot } from './model';
import { attachTooltip } from './tooltip';

/** ホストから状態が来る前（と v0.3 までのホスト）の状態 */
export const IDLE_DEVICE_STATE: DeviceViewState = { transfer: null, busyElsewhere: false, allowWrites: false };

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

/** 図の欄の id → その欄の違い（そのレイヤーの欄だけ） */
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

const PHASE_TEXT = { read: '実機を読んでいます', write: '書き込んでいます', verify: '読み直して確かめています' } as const;

/** 読む・書く間の進み具合の文（「実機を読んでいます（12/40）」） */
export function transferProgressText(transfer: DeviceTransfer): string {
  if (transfer.step === 'preview') return '';
  const progress = transfer.progress;
  const phase = transfer.step === 'reading' ? 'read' : (transfer.progress?.phase ?? 'read');
  const base = transfer.step === 'writing' && phase === 'read' ? '書く前に実機を読み直しています' : PHASE_TEXT[phase];
  return progress ? `${base}（${progress.done}/${progress.total}）` : `${base}…`;
}

/** 保存済みのプロファイルの検証のエラーの数（読めないプロファイルは少なくとも 1） */
export function snapshotErrors(snapshot: Pick<ProfileSnapshot, 'status' | 'diagnostics'> | undefined): number {
  if (!snapshot) return 0;
  const errors = snapshot.diagnostics.filter((diagnostic) => diagnostic.severity === 'error').length;
  return snapshot.status === 'invalid' ? Math.max(errors, 1) : errors;
}

/** 検証の結果の場所（「ファイル: キーの位置」。validate の表示と同じ並び） */
export function diagnosticPlace(diagnostic: Diagnostic): string | undefined {
  const file = diagnostic.address?.file ?? diagnostic.file;
  const path = diagnostic.address?.path.join('.');
  return file && path ? `${file}: ${path}` : file;
}

const WRITE_SETTING_NOTE = '書き込みは設定 cornix.device.allowWrites を有効にしたときだけできます（既定は無効。プレビューはいつでもできます）。';

export type TransferSectionOptions = {
  onPreview: () => void;
  /** 検証の結果の 1 行（App の問題の行と同じもの。「ファイルを開く」付き） */
  problemRow: (diagnostic: Diagnostic) => HTMLElement;
};

/** 編集フォームの一番下の節「デバイス転送」 */
export class TransferSection {
  readonly element: HTMLElement;
  readonly button: HTMLButtonElement;
  private readonly note = h('p', { class: 'device-transfer-note', hidden: true }, WRITE_SETTING_NOTE);
  /** 検証のエラーで押せない理由（ボタンの横） */
  private readonly blocked = h('span', { class: 'device-transfer-blocked', role: 'status', hidden: true });
  /** 見出しの横の件数（畳んでいても気づけるように） */
  private readonly count = h('span', { class: 'device-transfer-count', hidden: true });
  /** 保存済みのプロファイルの検証のエラーと警告の一覧 */
  private readonly problems = h('div', { class: 'device-transfer-problems' });
  private state: DeviceViewState = IDLE_DEVICE_STATE;
  private errors = 0;

  constructor(private readonly options: TransferSectionOptions) {
    this.button = h('button', { type: 'button', class: 'device-preview-button' }, '反映のプレビュー…');
    this.button.addEventListener('click', () => {
      if (!this.button.disabled) options.onPreview();
    });
    this.element = h(
      'section',
      { class: 'device-transfer', 'aria-label': 'デバイス転送' },
      h(
        'details',
        { class: 'section-details' },
        h('summary', {}, h('h2', {}, 'デバイス転送'), this.count),
        h(
          'p',
          { class: 'device-transfer-description' },
          '保存済みのプロファイルを、接続中の Cornix に書き込みます。押すと実機を読んで（Bluetooth では 10 秒ほど）違いをプレビューし、「確定」を押すまでは書き込みません。未保存の変更があれば先に保存します。',
        ),
        h('div', { class: 'device-transfer-actions' }, this.button, this.blocked),
        this.note,
        this.problems,
      ),
    );
    this.update(IDLE_DEVICE_STATE);
    this.setSnapshot(undefined);
  }

  /** 状態を描く。errors は保存済みのプロファイルの検証のエラーの数（snapshotErrors。あれば実機を読む前に止める） */
  update(state: DeviceViewState, errors = this.errors): void {
    this.state = state;
    this.errors = errors;
    this.button.disabled = state.transfer !== null || state.busyElsewhere || errors > 0;
    this.button.title = state.busyElsewhere ? 'ほかのプロファイルの反映の途中です' : '';
    this.blocked.hidden = errors === 0;
    this.blocked.textContent = errors > 0 ? `検証のエラーが ${errors} 件あるので反映できません。先にエラーを直して保存してください。` : '';
    this.note.hidden = state.allowWrites;
  }

  /** 保存済みのプロファイルが変わった（検証のエラーと警告の一覧と、押せるかを描き直す） */
  setSnapshot(snapshot: ProfileSnapshot | undefined): void {
    const diagnostics = snapshot?.diagnostics ?? [];
    const errors = snapshotErrors(snapshot);
    const warnings = diagnostics.filter((diagnostic) => diagnostic.severity === 'warning').length;
    const counts = [errors > 0 && `エラー ${errors} 件`, warnings > 0 && `警告 ${warnings} 件`].filter(Boolean).join('・');
    this.count.hidden = counts === '';
    this.count.className = `device-transfer-count${errors > 0 ? ' error' : ' warning'}`;
    this.count.textContent = counts;
    // エラーを先に
    const sorted = [...diagnostics].sort((a, b) => (a.severity === b.severity ? 0 : a.severity === 'error' ? -1 : 1));
    this.problems.replaceChildren(
      ...(sorted.length === 0
        ? [h('p', { class: 'device-transfer-clean' }, snapshot ? '保存済みのプロファイルに検証の問題はありません。' : '')]
        : [
            h(
              'p',
              { class: 'device-transfer-problems-title' },
              `保存済みのプロファイルの検証: ${counts}`,
              errors === 0 ? '（警告だけなので反映できます。意図どおりか確かめてください）' : '',
            ),
            ...sorted.map((diagnostic) => this.options.problemRow(diagnostic)),
          ]),
    );
    this.update(this.state, errors);
  }
}

export type TransferDialogOptions = { onAction: (action: DeviceAction) => void };

/** 反映のプレビューのモーダル（transfer がないときは隠す） */
export class TransferDialog {
  readonly element: HTMLElement;
  private readonly dialog: HTMLElement;
  private readonly title = h('h2', { id: 'device-modal-title' });
  private readonly summary = h('p', { class: 'device-modal-summary' });
  private readonly progressText = h('p', { class: 'device-modal-progress', role: 'status' });
  private readonly progressBar = h('progress', { class: 'device-modal-bar' }) as HTMLProgressElement;
  private readonly tabs = h('div', { class: 'layer-tabs device-modal-tabs', role: 'group', 'aria-label': 'レイヤー' });
  private readonly keyboard: KeyboardView;
  private readonly board: HTMLElement;
  private readonly list = h('div', { class: 'device-diff-list' });
  private readonly notes = h('div', { class: 'device-modal-notes' });
  private readonly footer = h('div', { class: 'device-modal-footer' });
  private state: DeviceViewState = IDLE_DEVICE_STATE;
  private snapshot: ProfileSnapshot | undefined;
  /** 保存済みのプロファイルの検証のエラーの数（あれば確定できない） */
  private errors = 0;
  /** 保存済みのプロファイルの検証の警告（モーダルに一覧で出す。確定は止めない） */
  private validationWarnings: Diagnostic[] = [];
  /** 図と一覧を描いたときの plan と snapshot（進み具合だけが変わったときは描き直さない） */
  private drawnKey = '';
  private layer: number | undefined;
  /** 今の図の欄 */
  private slots: Slot[] = [];
  private slotChanges = new Map<string, DeviceChange>();

  constructor(private readonly options: TransferDialogOptions) {
    this.keyboard = new KeyboardView({
      onSelect: (id) => this.highlight(this.slotChanges.get(id)),
      decorate: (element, id) => attachTooltip(element, () => Promise.resolve(this.describe(id)), { focus: 'visible' }),
    });
    this.board = h('div', { class: 'device-modal-board' }, this.tabs, this.keyboard.element);
    this.dialog = h(
      'div',
      { class: 'device-modal', role: 'dialog', 'aria-modal': 'true', 'aria-labelledby': 'device-modal-title' },
      this.title,
      this.summary,
      this.progressText,
      this.progressBar,
      this.board,
      this.list,
      this.notes,
      this.footer,
    );
    this.element = h('div', { class: 'device-modal-backdrop', hidden: true }, this.dialog);
    this.element.addEventListener('keydown', (event) => {
      if (event.key !== 'Escape') return;
      const step = this.state.transfer?.step;
      if (step === 'reading' || step === 'preview') {
        event.preventDefault();
        this.options.onAction('cancel');
      }
    });
  }

  get isOpen(): boolean {
    return !this.element.hidden;
  }

  /** 図（テスト用） */
  get keyboardView(): KeyboardView {
    return this.keyboard;
  }

  /** 今の図のレイヤー（テスト用） */
  get currentLayer(): number | undefined {
    return this.layer;
  }

  update(state: DeviceViewState, snapshot: ProfileSnapshot | undefined): void {
    const wasOpen = this.isOpen;
    this.state = state;
    this.snapshot = snapshot?.status === 'invalid' ? undefined : snapshot;
    this.errors = snapshotErrors(snapshot);
    this.validationWarnings = snapshot?.diagnostics.filter((diagnostic) => diagnostic.severity === 'warning') ?? [];
    const transfer = state.transfer;
    this.element.hidden = transfer === null;
    if (!transfer) {
      this.drawnKey = '';
      return;
    }
    this.dialog.dataset.step = transfer.step;
    this.renderHeader(transfer);
    const plan = transfer.step === 'reading' ? undefined : transfer.plan;
    const key = plan ? JSON.stringify([plan.token, plan.changes, this.snapshot?.layers, this.snapshot?.positionMap]) : '';
    if (key !== this.drawnKey) {
      this.drawnKey = key;
      this.renderChanges(plan?.changes ?? []);
    }
    this.renderNotes(transfer);
    this.renderFooter(transfer);
    if (!wasOpen) this.footer.querySelector<HTMLButtonElement>('button.primary:not(:disabled)')?.focus() ?? this.footer.querySelector('button')?.focus();
  }

  private renderHeader(transfer: DeviceTransfer): void {
    const progress = transfer.step !== 'preview';
    this.progressText.hidden = !progress;
    this.progressBar.hidden = !progress;
    if (progress) {
      this.progressText.textContent = transferProgressText(transfer);
      const value = transfer.progress;
      if (value && value.total > 0) {
        this.progressBar.max = value.total;
        this.progressBar.value = value.done;
      } else {
        this.progressBar.removeAttribute('value');
      }
    }
    if (transfer.step === 'reading') {
      this.title.textContent = '実機を読んでいます';
      this.summary.textContent = '保存済みのプロファイルと比べるため、接続中の Cornix を読んでいます（読むだけ。Bluetooth では 10 秒ほど）。';
      return;
    }
    const { plan, profile } = transfer;
    if (transfer.step === 'preview' && plan.empty) {
      this.title.textContent = '実機はこのプロファイルと同じです';
      this.summary.textContent = `${plan.keyboard.name} はプロファイル ${profile} と同じなので、書き込むものはありません。`;
      return;
    }
    this.title.textContent = transfer.step === 'writing' ? '実機に書き込んでいます' : '実機への反映のプレビュー';
    this.summary.textContent = `書き込み先: ${plan.keyboard.name}　プロファイル: ${profile}　違い: ${plan.changes.length} 件`;
  }

  /** 図・レイヤーのタブ・一覧を描き直す（plan か snapshot が変わったときだけ） */
  private renderChanges(changes: readonly DeviceChange[]): void {
    const snapshot = this.snapshot;
    const counts = deviceLayerCounts(changes);
    const layers = snapshot?.layers ?? [];
    const shown = layers.some((layer) => counts.has(layer.index));
    this.board.hidden = !shown;
    if (shown) {
      if (!layers.some((layer) => layer.index === this.layer && counts.has(layer.index))) {
        this.layer = layers.find((layer) => counts.has(layer.index))?.index;
      }
      this.renderTabs(layers, counts);
      this.renderBoard();
    } else {
      this.layer = undefined;
      this.slots = [];
      this.slotChanges = new Map();
    }
    const names = new Map(layers.map((layer) => [layer.index, layer.name]));
    this.list.hidden = changes.length === 0;
    this.list.replaceChildren(
      ...nodes(
        changes.length > 0 && h('div', { class: 'device-diff-legend', 'aria-hidden': 'true' }, '場所: 実機の今の値 → このプロファイルの値（書き込む値）'),
        ...changes.map((change, i) => this.row(change, i, names)),
      ),
    );
  }

  private renderTabs(layers: readonly LayerSnapshot[], counts: ReadonlyMap<number, number>): void {
    this.tabs.replaceChildren(
      ...layers.map((layer) => {
        const count = counts.get(layer.index) ?? 0;
        const selected = layer.index === this.layer;
        const tab = h(
          'button',
          {
            type: 'button',
            class: `layer-tab${selected ? ' selected' : ''}${count > 0 ? ' has-device-diff' : ''}`,
            'aria-pressed': String(selected),
            'data-layer': layer.index,
            title: count > 0 ? `実機と違うキー ${count} 件` : '実機と同じ',
          },
          layerTitle(layer),
          ...nodes(count > 0 && h('span', { class: 'device-tab-count' }, String(count))),
        );
        tab.addEventListener('click', () => this.selectLayer(layer.index));
        return tab;
      }),
    );
  }

  /** プレビューの図のレイヤーを選ぶ */
  selectLayer(index: number): void {
    if (!this.snapshot?.layers.some((layer) => layer.index === index)) return;
    this.layer = index;
    const plan = this.state.transfer && this.state.transfer.step !== 'reading' ? this.state.transfer.plan : undefined;
    this.renderTabs(this.snapshot.layers, deviceLayerCounts(plan?.changes ?? []));
    this.renderBoard();
  }

  private renderBoard(): void {
    const snapshot = this.snapshot;
    const layer = snapshot?.layers.find((l) => l.index === this.layer);
    const plan = this.state.transfer && this.state.transfer.step !== 'reading' ? this.state.transfer.plan : undefined;
    if (!snapshot || !layer) return;
    this.slots = layerSlots(layer, snapshot.positionMap);
    this.slotChanges = deviceSlotChanges(plan?.changes ?? [], this.slots, this.layer);
    this.keyboard.setLayerNames(new Map(snapshot.layers.map((l) => [l.index, l.name])));
    this.keyboard.setSlots(this.slots);
    for (const slot of this.slots) {
      this.keyboard.update(slot.id, {
        text: slot.saved?.text ?? '',
        value: slot.saved,
        diagnostics: [],
        changed: false,
        base: slot.saved?.kind === 'transparent' ? baseLayerValue(snapshot, this.layer, slot) : null,
      });
    }
    this.keyboard.setDeviceDiffs(new Map([...this.slotChanges].map(([id, change]) => [id, change.device])));
    this.keyboard.setSelected(undefined);
  }

  /** 図のキーの説明（違うキーだけ: 実機の値 → このプロファイルの値） */
  private describe(id: string): Node | null {
    const change = this.slotChanges.get(id);
    if (!change) return null;
    return h(
      'div',
      { class: 'device-tooltip' },
      h('div', {}, '実機: ', h('code', {}, change.device)),
      h('div', {}, 'このプロファイル: ', h('code', {}, change.profile)),
    );
  }

  private row(change: DeviceChange, index: number, names: ReadonlyMap<number, string>): HTMLElement {
    if (change.kind === 'other') {
      return h('div', { class: 'device-diff-row other', 'data-change': index }, h('span', { class: 'device-diff-text' }, change.text));
    }
    const content = [
      h('span', { class: 'device-diff-place' }, changePlace(change, names)),
      ': ',
      h('code', { class: 'device-diff-device', title: '実機の今の値' }, change.device),
      h('span', { class: 'device-diff-arrow' }, ' → '),
      h('code', { class: 'device-diff-profile', title: 'このプロファイルの値' }, change.profile),
    ];
    const onBoard = (change.kind === 'key' || change.kind === 'encoder') && !!this.snapshot?.layers.some((layer) => layer.index === change.layer);
    if (!onBoard) return h('div', { class: 'device-diff-row', 'data-change': index, title: change.text }, ...content);
    const button = h('button', { type: 'button', class: 'device-diff-row', 'data-change': index, title: `${change.text}\n押すと図のそのキーを示す` }, ...content);
    button.addEventListener('click', () => this.reveal(change));
    return button;
  }

  /** 一覧の行を押した: そのレイヤーの図を出して、そのキーを選ぶ */
  private reveal(change: DeviceChange): void {
    if (change.layer === undefined) return;
    if (change.layer !== this.layer) this.selectLayer(change.layer);
    const [id] = deviceSlotChanges([change], this.slots, this.layer).keys();
    this.keyboard.setSelected(id);
    this.highlight(change);
  }

  /** 一覧のその行を強調する（図のキーを押したとき・行を押したとき） */
  private highlight(change: DeviceChange | undefined): void {
    for (const row of this.list.querySelectorAll('.device-diff-row')) row.classList.remove('selected');
    if (!change) return;
    const plan = this.state.transfer && this.state.transfer.step !== 'reading' ? this.state.transfer.plan : undefined;
    const index = plan?.changes.indexOf(change) ?? -1;
    const row = this.list.querySelector<HTMLElement>(`[data-change='${index}']`);
    row?.classList.add('selected');
    row?.scrollIntoView?.({ block: 'nearest' });
  }

  private renderNotes(transfer: DeviceTransfer): void {
    const warnings = transfer.step === 'reading' ? [] : transfer.plan.warnings;
    const stale = transfer.step === 'preview' && transfer.stale;
    const writable = transfer.step === 'preview' && !transfer.plan.empty;
    const settings = h('button', { type: 'button', class: 'link-button' }, '設定を開く');
    settings.addEventListener('click', () => this.options.onAction('openSettings'));
    this.notes.replaceChildren(
      ...nodes(
        warnings.length > 0 &&
          h('div', { class: 'device-modal-warnings' }, h('strong', {}, '注意'), h('ul', {}, ...warnings.map((warning) => h('li', {}, warning)))),
        stale &&
          h('p', { class: 'device-modal-stale', role: 'alert' }, 'プレビューのあとで設定ファイルが変わりました。もう一度比べてから確定してください。'),
        writable &&
          this.errors > 0 &&
          h('p', { class: 'device-modal-errors', role: 'alert' }, `プロファイルに検証のエラーが ${this.errors} 件あるので確定できません。直して保存してから、もう一度比べてください。`),
        writable &&
          this.validationWarnings.length > 0 &&
          h(
            'div',
            { class: 'device-modal-validation' },
            h('strong', {}, `検証の警告が ${this.validationWarnings.length} 件あります（確定はできます）`),
            h('ul', {}, ...this.validationWarnings.map((diagnostic) => h('li', {}, [diagnosticPlace(diagnostic), diagnostic.message].filter(Boolean).join(': ')))),
          ),
        writable && !this.state.allowWrites && h('p', { class: 'device-modal-locked' }, WRITE_SETTING_NOTE, ' ', settings),
        writable && h('p', { class: 'device-modal-backup' }, '確定すると、書く前に実機の今の状態をバックアップし、書いたあと読み直して確かめます。'),
        transfer.step === 'writing' && h('p', { class: 'device-modal-backup' }, '書き始めたら取り消せません。終わるまでキーボードをつないだままにしてください。'),
      ),
    );
  }

  private renderFooter(transfer: DeviceTransfer): void {
    const button = (label: string, action: DeviceAction | null, options: { primary?: boolean; disabled?: boolean } = {}) => {
      const element = h('button', { type: 'button', class: `device-modal-button${options.primary ? ' primary' : ''}`, 'data-device-action': action ?? '' }, label);
      element.disabled = options.disabled === true;
      if (action) element.addEventListener('click', () => !element.disabled && this.options.onAction(action));
      return element;
    };
    switch (transfer.step) {
      case 'reading':
        this.footer.replaceChildren(button('やめる', 'cancel'));
        return;
      case 'writing':
        this.footer.replaceChildren(button('やめる', null, { disabled: true }), button(`確定（${transfer.plan.changes.length} 件を書き込む）`, null, { primary: true, disabled: true }));
        return;
      case 'preview':
        if (transfer.plan.empty) {
          this.footer.replaceChildren(button('閉じる', 'cancel', { primary: true }));
        } else if (transfer.stale) {
          this.footer.replaceChildren(button('やめる', 'cancel'), button('もう一度比べる', 'preview', { primary: true }));
        } else {
          this.footer.replaceChildren(
            button('やめる', 'cancel'),
            button(`確定（${transfer.plan.changes.length} 件を書き込む）`, 'confirm', { primary: true, disabled: !this.state.allowWrites || this.errors > 0 }),
          );
        }
        return;
    }
  }
}
