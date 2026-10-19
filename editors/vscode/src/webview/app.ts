// 編集画面の全体。上にキーボード図、下にレイヤーの編集画面（ADR 009）。選んでいるレイヤーと欄は上下で共有する。
// ホストから snapshot と未保存の変更（Change の並び）を受けて描き、欄で決めた値を Change としてホストに渡す。
// 未保存の値の表示の文字と検証は keycode/inspect で聞く（onchange の検証。ADR 012）。
//
// 描き直し: 図と欄を作り直すのは、position_map・レイヤーの並び・ファイル・欄の Address が変わったときだけ（model.ts の structureKey）。
// 保存や外での変更で files の版・diagnostics・値が変わっただけなら、値だけを描き直す（打っている欄のフォーカスと文字が残る）。
// 作り直すときも、フォーカスのある欄・打ちかけの文字・下のペインのスクロール位置を戻す。
import type { Change, Diagnostic, KeyValue, ProfileSnapshot } from '../protocol';
import type { HostMessage, WebviewMessage } from '../webviewMessages';
import { h, nodes } from './dom';
import type { HostClient } from './hostClient';
import { Inspector } from './inspector';
import type { KeyInput } from './keyInput';
import { KeyboardView } from './keyboardView';
import { LayerEditor } from './layerEditor';
import { changeMap, currentText, diagnosticsByAddress, layerSlots, layerTitle, slotLabel, structureKey, type Slot } from './model';
import { attachTooltip, describeContent, hideTooltip } from './tooltip';

/** 画面を閉じても覚えておくもの（Webview の getState / setState。タブを裏に回すと Webview は作り直される） */
export type ViewState = { layer?: number; selected?: string };

export type AppOptions = {
  host: HostClient;
  /** 描き終えたら（統合テストが待つ） */
  onRendered?: (message: Extract<WebviewMessage, { type: 'rendered' }>) => void;
  state?: { get(): ViewState | undefined; set(state: ViewState): void };
  /** 下のペインのレイヤーの欄のあとに置く部品（QMK 設定・メタデータ）。読めないプロファイルの表示では出ない */
  sections?: HTMLElement[];
};

/** 作り直す前のフォーカスと打ちかけ */
type Draft = { slotId: string; text: string; editing: boolean; selection: [number | null, number | null] } | undefined;

export class App {
  private snapshot: ProfileSnapshot | undefined;
  private snapshotKey = '';
  private structure = '';
  private changes = new Map<string, Change>();
  private diagnostics = new Map<string, Diagnostic[]>();
  private generalDiagnostics: Diagnostic[] = [];
  private layerIndex: number | undefined;
  private selected: string | undefined;
  private slots: Slot[] = [];
  private readonly inspector: Inspector;

  private readonly keyboard: KeyboardView;
  private readonly editor: LayerEditor;
  private readonly tabs = h('div', { class: 'layer-tabs', role: 'group', 'aria-label': 'レイヤー' });
  private readonly header = h('header', { class: 'profile-header' });
  private readonly problems = h('div', { class: 'problems' });
  private readonly banner = h('div', { class: 'banner', role: 'alert', hidden: true });
  private readonly layerInfo = h('div', { class: 'layer-info' });
  private readonly topPane: HTMLElement;
  private readonly bottomPane: HTMLElement;

  constructor(
    private readonly root: HTMLElement,
    private readonly options: AppOptions,
  ) {
    this.inspector = new Inspector(options.host);
    const saved = options.state?.get();
    this.layerIndex = saved?.layer;
    this.selected = saved?.selected;
    this.keyboard = new KeyboardView({
      onSelect: (id) => this.reveal(id),
      decorate: (element, id) => attachTooltip(element, () => this.describe(id), { focus: 'visible' }),
    });
    this.editor = new LayerEditor({
      host: options.host,
      onCommit: (id, text) => this.commit(id, text),
      onFocus: (id) => this.select(id),
      decorate: (input: KeyInput, id) =>
        attachTooltip(input.input, () => this.describe(id), { focus: 'always', canShow: () => !input.isOpen && !input.isEditing }),
    });
    this.topPane = h('div', { class: 'top-pane' }, this.header, this.banner, this.tabs, this.keyboard.element);
    this.bottomPane = h('div', { class: 'bottom-pane' }, this.layerInfo, this.problems, this.editor.element, ...(options.sections ?? []));
    this.root.replaceChildren(h('div', { class: 'loading' }, '読み込んでいます…'));
  }

  /** ホストからのメッセージ（応答以外） */
  receive(message: HostMessage): void {
    if (message.type === 'snapshot') this.setSnapshot(message.snapshot, message.changes);
    if (message.type === 'error') {
      this.banner.textContent = message.message;
      this.banner.hidden = false;
      if (!this.snapshot) this.root.replaceChildren(this.banner);
    }
  }

  get currentLayer(): number | undefined {
    return this.layerIndex;
  }

  get selectedSlot(): string | undefined {
    return this.selected;
  }

  /** 下の欄の入力欄（テスト用） */
  get inputs(): ReadonlyMap<string, KeyInput> {
    return this.editor.inputs;
  }

  setSnapshot(snapshot: ProfileSnapshot, changes: Change[]): void {
    this.changes = changeMap(changes);
    const key = JSON.stringify(snapshot);
    if (key === this.snapshotKey && this.snapshot) {
      // 中身が同じ（変更・元に戻すのたび）なら、値だけを描き直す
      this.renderHeader();
      this.updateSlots();
      this.rendered();
      return;
    }
    this.snapshotKey = key;
    this.snapshot = snapshot;
    this.inspector.clear();
    const { byAddress, general } = diagnosticsByAddress(snapshot);
    this.diagnostics = byAddress;
    this.generalDiagnostics = general;
    this.banner.hidden = true;
    if (snapshot.status === 'invalid') {
      this.structure = '';
      hideTooltip();
      this.renderInvalid(snapshot);
      this.rendered();
      return;
    }
    if (!snapshot.layers.some((layer) => layer.index === this.layerIndex)) this.layerIndex = snapshot.layers[0]?.index;
    const structure = structureKey(snapshot);
    if (structure === this.structure && this.topPane.isConnected) {
      // 形が同じ: 作り直さずに値・印・見出しだけを描き直す
      this.renderHeader();
      this.renderTabs();
      this.renderProblems();
      this.renderLayerInfo();
      this.slots = this.currentSlots();
      this.keyboard.replaceSlots(this.slots);
      this.updateSlots();
      this.rendered();
      return;
    }
    this.structure = structure;
    const draft = this.captureDraft();
    const scroll = this.bottomPane.scrollTop;
    hideTooltip();
    if (!this.topPane.isConnected) this.root.replaceChildren(this.topPane, this.bottomPane);
    this.renderHeader();
    this.renderProblems();
    this.renderLayer();
    this.restoreDraft(draft);
    this.bottomPane.scrollTop = scroll;
    this.rendered();
  }

  selectLayer(index: number): void {
    if (!this.snapshot?.layers.some((layer) => layer.index === index)) return;
    this.layerIndex = index;
    this.saveState();
    hideTooltip();
    this.renderLayer();
    this.rendered();
  }

  /** 欄を選ぶ（上下で共有） */
  select(slotId: string | undefined): void {
    this.selected = slotId;
    this.keyboard.setSelected(slotId);
    this.editor.setSelected(slotId);
    this.saveState();
  }

  /** 図のキーを押した: 下の該当の欄へ移る */
  reveal(slotId: string): void {
    this.select(slotId);
    this.editor.reveal(slotId);
  }

  private saveState(): void {
    this.options.state?.set({
      ...(this.layerIndex === undefined ? {} : { layer: this.layerIndex }),
      ...(this.selected === undefined ? {} : { selected: this.selected }),
    });
  }

  private currentSlots(): Slot[] {
    const layer = this.snapshot?.layers.find((l) => l.index === this.layerIndex);
    return layer && this.snapshot ? layerSlots(layer, this.snapshot.positionMap) : [];
  }

  private captureDraft(): Draft {
    const active = document.activeElement;
    if (!(active instanceof HTMLInputElement) || !this.editor.element.contains(active)) return undefined;
    const slotId = active.closest<HTMLElement>('.field')?.dataset.slot;
    const input = slotId ? this.editor.inputs.get(slotId) : undefined;
    if (!slotId || !input) return undefined;
    return { slotId, text: active.value, editing: input.isEditing, selection: [active.selectionStart, active.selectionEnd] };
  }

  private restoreDraft(draft: Draft): void {
    if (!draft) return;
    const input = this.editor.inputs.get(draft.slotId);
    if (!input) return;
    if (draft.editing) input.restoreDraft(draft.text);
    input.input.focus();
    try {
      const [start, end] = draft.selection;
      if (start !== null && end !== null) input.input.setSelectionRange(start, end);
    } catch {
      // 選択を戻せない入力欄（ないはず）は捨てる
    }
  }

  private renderHeader(): void {
    const snapshot = this.snapshot;
    if (!snapshot) return;
    const pending = this.changes.size;
    this.header.replaceChildren(
      ...nodes(
        h('span', { class: 'profile-name' }, snapshot.name),
        h('span', { class: 'profile-dir' }, snapshot.dir),
        pending > 0 && h('span', { class: 'pending' }, `未保存の変更 ${pending} 件`),
      ),
    );
  }

  /** レイヤーの切り替え（ただのボタンの並び。選んでいるものは aria-pressed） */
  private renderTabs(): void {
    const snapshot = this.snapshot;
    if (!snapshot) return;
    const focused = document.activeElement instanceof HTMLElement && this.tabs.contains(document.activeElement) ? document.activeElement.dataset.layer : undefined;
    this.tabs.replaceChildren(
      ...snapshot.layers.map((l) => {
        const selected = l.index === this.layerIndex;
        const tab = h(
          'button',
          { type: 'button', class: `layer-tab${selected ? ' selected' : ''}`, 'aria-pressed': String(selected), 'data-layer': l.index, title: l.file },
          layerTitle(l),
        );
        tab.addEventListener('click', () => this.selectLayer(l.index));
        return tab;
      }),
    );
    if (focused !== undefined) this.tabs.querySelector<HTMLElement>(`[data-layer="${focused}"]`)?.focus();
  }

  private renderLayerInfo(): void {
    const layer = this.snapshot?.layers.find((l) => l.index === this.layerIndex);
    if (!layer) {
      this.layerInfo.replaceChildren(h('p', {}, 'レイヤーがありません'));
      return;
    }
    this.layerInfo.replaceChildren(
      ...nodes(
        h('h2', {}, `レイヤー ${layerTitle(layer)}`, h('span', { class: 'layer-file' }, layer.file)),
        layer.description && h('p', { class: 'layer-description' }, layer.description),
      ),
    );
  }

  private renderLayer(): void {
    if (!this.snapshot) return;
    this.renderTabs();
    this.renderLayerInfo();
    this.slots = this.currentSlots();
    this.keyboard.setSlots(this.slots);
    this.editor.setSlots(this.slots);
    if (this.selected && !this.slots.some((slot) => slot.id === this.selected)) this.selected = undefined;
    this.select(this.selected);
    this.updateSlots();
  }

  private renderProblems(): void {
    const list = this.generalDiagnostics;
    if (list.length === 0) {
      this.problems.replaceChildren();
      return;
    }
    const open = this.problems.querySelector('details')?.open ?? false;
    const details = h('details', { class: 'problems-list', open }, h('summary', {}, `ファイルの問題（${list.length} 件）`));
    for (const diagnostic of list) details.append(this.problemRow(diagnostic));
    this.problems.replaceChildren(details);
  }

  private problemRow(diagnostic: Diagnostic): HTMLElement {
    const file = diagnostic.address?.file ?? diagnostic.file;
    const row = h(
      'div',
      { class: `problem ${diagnostic.severity}` },
      h('span', { class: 'problem-severity' }, diagnostic.severity === 'error' ? 'エラー' : '警告'),
      file ? h('span', { class: 'problem-file' }, file) : null,
      h('span', { class: 'problem-message' }, diagnostic.message),
    );
    if (file && !file.endsWith('/')) {
      const open = h('button', { type: 'button', class: 'link-button' }, 'ファイルを開く');
      open.addEventListener('click', () => this.options.host.openFile(file, diagnostic.range));
      row.append(open);
    }
    return row;
  }

  private renderInvalid(snapshot: ProfileSnapshot): void {
    const list = h('div', { class: 'problems-list open' });
    for (const diagnostic of snapshot.diagnostics) list.append(this.problemRow(diagnostic));
    this.slots = [];
    this.editor.setSlots([]);
    this.root.replaceChildren(
      h(
        'div',
        { class: 'invalid' },
        h('header', { class: 'profile-header' }, h('span', { class: 'profile-name' }, snapshot.name), h('span', { class: 'profile-dir' }, snapshot.dir)),
        this.banner,
        h('h2', {}, 'このプロファイルは読めませんでした'),
        h('p', {}, '設定ファイルに読めない値があります。テキストで直して保存すると、ここに描き直します。'),
        list,
      ),
    );
  }

  /** 欄の値・印・メッセージを描き直す */
  private updateSlots(): void {
    for (const slot of this.slots) this.updateSlot(slot);
  }

  private updateSlot(slot: Slot): void {
    const text = currentText(slot, this.changes);
    const changed = this.changes.has(slot.id);
    let value: KeyValue | null | undefined = slot.saved;
    let diagnostics: readonly Diagnostic[] = this.diagnostics.get(slot.id) ?? [];
    if (changed) {
      const result = this.inspector.get(slot.context, text);
      if (result) {
        value = result.value;
        diagnostics = result.diagnostics;
      } else {
        value = undefined;
        diagnostics = [];
        this.inspector.load(slot.context, text).then(
          () => this.refresh(slot.id),
          () => undefined,
        );
      }
    }
    this.keyboard.update(slot.id, { text, value, diagnostics, changed });
    this.editor.update(slot.id, text, diagnostics, changed);
  }

  private refresh(slotId: string): void {
    const slot = this.slots.find((s) => s.id === slotId);
    if (slot) this.updateSlot(slot);
  }

  /** 欄で値を決めた: ホストに Change を渡し、すぐに検証する（ホストからの snapshot を待たずに描く） */
  private commit(slotId: string, text: string): void {
    const slot = this.slots.find((s) => s.id === slotId);
    if (!slot) return;
    const change: Change = { address: slot.address, value: text };
    if (text === (slot.saved?.text ?? '')) this.changes.delete(slot.id);
    else this.changes.set(slot.id, change);
    this.options.host.change(change);
    this.renderHeader();
    this.updateSlot(slot);
  }

  private async describe(slotId: string): Promise<Node | null> {
    const slot = this.slots.find((s) => s.id === slotId);
    if (!slot) return null;
    const text = currentText(slot, this.changes);
    if (!text) return null;
    const changed = this.changes.has(slot.id);
    const result = await this.inspector.load(slot.context, text).catch(() => undefined);
    const saved = changed ? [] : (this.diagnostics.get(slot.id) ?? []);
    const own = result?.diagnostics ?? [];
    const diagnostics = [...saved, ...own.filter((d) => !saved.some((s) => s.message === d.message))];
    const context = slot.encoder ? slotLabel(slot) : undefined;
    return describeContent(text, result, { context, note: changed ? undefined : slot.saved?.note, diagnostics });
  }

  private rendered(): void {
    const keys = this.slots.filter((slot) => slot.key).length;
    const board = this.root.querySelector('.board');
    this.options.onRendered?.({
      type: 'rendered',
      status: this.snapshot?.status ?? 'invalid',
      layer: this.layerIndex ?? null,
      keys,
      encoders: this.slots.length - keys,
      // media/webview.css の .board は position: relative
      styled: !!board && getComputedStyle(board).position === 'relative',
    });
  }
}
