// 編集画面の全体。上にキーボード図、下にレイヤーの編集画面（ADR 009）。選んでいるレイヤーと欄は上下で共有する。
// ホストから snapshot と未保存の変更（Change の並び）を受けて描き、欄で決めた値を Change としてホストに渡す。
// 未保存の値の表示の文字と検証は keycode/inspect で聞く（onchange の検証。ADR 012）。
// v0.2: 割り当てを消す（remove）・注記（field: "note"）も未保存の変更として描く。ホストが snapshot と一緒に送る pending（当てる順の全部）を
// 欄ごとに畳んで使い（model.ts の slotEdits）、v0.1 のホスト（pending なし）では changes を使う。位置の名前の変更は host.itemEdit（ホストが確認してすぐ書く）。
//
// 描き直し: 図と欄を作り直すのは、position_map・レイヤーの並び・ファイル・欄の Address が変わったときだけ（model.ts の structureKey）。
// 保存や外での変更で files の版・diagnostics・値が変わっただけなら、値だけを描き直す（打っている欄のフォーカスと文字が残る）。
// 作り直すときも、フォーカスのある欄・打ちかけの文字・下のペインのスクロール位置を戻す。
//
// v0.3（tasks-v0.3.md の E1）: 図の全レイヤーの表示の行（ほかのレイヤーも保存済みの値に未保存の変更を重ねる）、コンボのボタンと
// トリガーのキーの強調（comboHighlight.ts。トリガーもコンボの未保存の変更を重ねる）、図からキーを選ぶ状態（pickKey）。
import type { Address, AnyChange, CandidateContext, Change, Diagnostic, KeyValue, LayerSnapshot, ProfileSnapshot, RemoveChange } from '../protocol';
import type { HostMessage, WebviewMessage } from '../webviewMessages';
import { h, nodes } from './dom';
import type { HostClient } from './hostClient';
import { comboTargets, effectiveKey, triggerKeys } from './comboHighlight';
import { Inspector } from './inspector';
import { comboView } from './itemsModel';
import type { KeyInput } from './keyInput';
import { KeyboardView } from './keyboardView';
import { LayerEditor } from './layerEditor';
import {
  addPending,
  addressKey,
  baseLayerValue,
  currentNote,
  currentText,
  diagnosticsByAddress,
  keyAt,
  keyFaceNote,
  layerLineLabel,
  layerSlots,
  layerTitle,
  slotChanged,
  slotEdits,
  slotLabel,
  structureKey,
  valueChanged,
  type LayerLine,
  type Slot,
  type SlotEdits,
} from './model';
import { attachTooltip, comboContent, describeContent, hideTooltip } from './tooltip';

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
  /** 未保存の変更（当てる順）と、それを欄ごとに畳んだもの */
  private pending: AnyChange[] = [];
  private edits: SlotEdits = slotEdits([]);
  private diagnostics = new Map<string, Diagnostic[]>();
  private generalDiagnostics: Diagnostic[] = [];
  private layerIndex: number | undefined;
  private selected: string | undefined;
  private slots: Slot[] = [];
  /** 図に描いた今の値（欄の id → 値。コンボの強調で比べる） */
  private readonly values = new Map<string, KeyValue | null | undefined>();
  /** 図からキーを選んでいる間の受け取り手 */
  private picking: { onPick: (text: string) => void } | undefined;
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
      onRenamePosition: (id) => {
        this.select(id);
        this.editor.startRename(id);
      },
      comboTargets: (index) => this.comboTargets(index),
      decorateCombo: (element, index) => attachTooltip(element, () => Promise.resolve(this.describeCombo(index)), { focus: 'visible' }),
      onPick: (id) => this.picked(id),
      onPickCancel: () => this.endPick(),
    });
    this.editor = new LayerEditor({
      host: options.host,
      onCommit: (id, text) => this.commit(id, text),
      onFocus: (id) => this.select(id),
      onRemove: (id) => this.remove(id),
      onNote: (id, note) => this.commitNote(id, note),
      onRenamePosition: (id, to) => this.renamePosition(id, to),
      layers: () => (this.snapshot?.layers ?? []).map((layer) => ({ index: layer.index, name: layer.name })),
      decorate: (input: KeyInput, id) =>
        attachTooltip(input.input, () => this.describe(id), { focus: 'always', canShow: () => !input.isOpen && !input.isEditing }),
    });
    this.topPane = h('div', { class: 'top-pane' }, this.header, this.banner, this.tabs, this.keyboard.element);
    this.bottomPane = h('div', { class: 'bottom-pane' }, this.layerInfo, this.problems, this.editor.element, ...(options.sections ?? []));
    this.root.replaceChildren(h('div', { class: 'loading' }, '読み込んでいます…'));
  }

  /** ホストからのメッセージ（応答以外） */
  receive(message: HostMessage): void {
    if (message.type === 'snapshot') this.setSnapshot(message.snapshot, message.changes, message.pending);
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

  /** 図（テスト用） */
  get keyboardView(): KeyboardView {
    return this.keyboard;
  }

  /**
   * changes は v0.1 の値の書き換え、pending は v0.2 の未保存の変更の全部（当てる順）。pending があればそちらを使う
   */
  setSnapshot(snapshot: ProfileSnapshot, changes: Change[], pending?: AnyChange[]): void {
    this.setPending(pending ?? changes);
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
      this.keyboard.setLayerNames(this.layerNames());
      this.keyboard.replaceSlots(this.slots);
      this.editor.replaceSlots(this.slots);
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

  /**
   * v0.3: 図のキーを押して選ぶ状態に入る。押したキーの今のレイヤーの表記を onPick に渡して抜ける。
   * 戻り値の関数か Esc で、選ばずに抜ける（tasks-v0.3.md の E1。今は入れ物だけ）
   */
  pickKey(onPick: (text: string) => void): () => void {
    // 選んでいる途中でまた呼ばれたら、前のものは選ばずに抜けたことにする
    const picking = { onPick };
    this.picking = picking;
    this.keyboard.setPicking(true);
    return () => {
      if (this.picking === picking) this.endPick();
    };
  }

  /** 選ぶ状態か（テスト用） */
  get isPicking(): boolean {
    return this.picking !== undefined;
  }

  /** 選ぶ状態で図のキーを押した: 今のレイヤーの表記を渡して抜ける。書いていないキーは選べない（選ぶ状態のまま） */
  private picked(slotId: string): void {
    const picking = this.picking;
    const slot = this.slots.find((s) => s.id === slotId);
    if (!picking || !slot) return;
    const text = currentText(slot, this.edits);
    if (!text) return;
    this.endPick();
    picking.onPick(text);
  }

  private endPick(): void {
    this.picking = undefined;
    this.keyboard.setPicking(false);
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

  private setPending(list: AnyChange[]): void {
    this.pending = list;
    this.edits = slotEdits(list);
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

  private layerNames(): Map<number, string> {
    return new Map((this.snapshot?.layers ?? []).map((layer) => [layer.index, layer.name]));
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
    const pending = this.pending.length;
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
    this.values.clear();
    this.keyboard.setLayerNames(this.layerNames());
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
    this.endPick();
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

  /** 欄の値・印・メッセージを描き直す（コンボのボタンも） */
  private updateSlots(): void {
    this.keyboard.setCombos((this.snapshot?.combos ?? []).map((combo) => ({ index: combo.index, name: combo.name, reachable: combo.reachable })));
    for (const slot of this.slots) this.updateSlot(slot, false);
    this.keyboard.refreshCombo();
  }

  /** refreshCombo: コンボの強調も描き直す（updateSlots はまとめて 1 回） */
  private updateSlot(slot: Slot, refreshCombo = true): void {
    const text = currentText(slot, this.edits);
    const changed = slotChanged(slot, this.edits);
    let value: KeyValue | null | undefined = slot.saved;
    let diagnostics: readonly Diagnostic[] = this.diagnostics.get(slot.id) ?? [];
    if (valueChanged(slot, this.edits)) {
      const result = text ? this.inspector.get(slot.context, text) : undefined;
      if (!text) {
        // 割り当てを消した（書いていない位置になる）
        value = null;
        diagnostics = [];
      } else if (result) {
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
    const base = value?.kind === 'transparent' && this.snapshot ? baseLayerValue(this.snapshot, this.layerIndex, slot) : null;
    this.values.set(slot.id, value);
    const layers = slot.key ? this.layerLines(slot, text, value) : undefined;
    this.keyboard.update(slot.id, { text, value, diagnostics, changed, base, ...(layers ? { layers } : {}) });
    this.editor.update(slot.id, { text, diagnostics, changed, note: currentNote(slot, this.edits) });
    if (refreshCombo) this.keyboard.refreshCombo();
  }

  /**
   * 表記の今の解釈: 書いていなければ null、保存済みの表記のままなら保存済みの値、聞いてあればその値。
   * まだ聞いていなければ聞いて（返ったら onLoaded）、それまでは undefined
   */
  private resolveValue(text: string, saved: KeyValue | null, context: CandidateContext, onLoaded: () => void): KeyValue | null | undefined {
    if (!text) return null;
    if (saved && saved.text === text) return saved;
    const result = this.inspector.get(context, text);
    if (result) return result.value;
    this.inspector.load(context, text).then(onLoaded, () => undefined);
    return undefined;
  }

  /** ほかのレイヤーの位置の今の表記と解釈（保存済みの値に未保存の変更を重ねる） */
  private positionValue(address: Address, saved: KeyValue | null, onLoaded: () => void): { text: string; value: KeyValue | null | undefined } {
    const target = { id: addressKey(address), saved };
    const text = currentText(target, this.edits);
    if (!valueChanged(target, this.edits)) return { text, value: saved };
    return { text, value: this.resolveValue(text, saved, 'layerKey', onLoaded) };
  }

  /** 全レイヤーの表示の行（今のレイヤーは図に描く値、ほかのレイヤーは同じ位置の値） */
  private layerLines(slot: Slot, text: string, value: KeyValue | null | undefined): LayerLine[] {
    const lines: LayerLine[] = [];
    for (const layer of this.snapshot?.layers ?? []) {
      const current = layer.index === this.layerIndex;
      let lineText = text;
      let lineValue = value;
      if (!current) {
        const key = keyAt(layer, slot);
        if (!key) continue;
        ({ text: lineText, value: lineValue } = this.positionValue(key.address, key.value, () => this.refresh(slot.id)));
      }
      const label = layerLineLabel(lineText, lineValue);
      if (label !== null) lines.push({ index: layer.index, label, current });
    }
    return lines;
  }

  /** レイヤー 0 の同じ位置の今の値（KC_TRNS の位置をコンボのトリガーと比べるため。未保存の変更も重ねる） */
  private baseValueAt(slot: Slot, base: LayerSnapshot | undefined): KeyValue | null | undefined {
    const key = base ? keyAt(base, slot) : undefined;
    if (!key) return null;
    return this.positionValue(key.address, key.value, () => this.keyboard.refreshCombo()).value;
  }

  /** コンボのトリガーのキーを今のレイヤーで割り当てた欄（KC_TRNS の位置はレイヤー 0 の値で見る） */
  private comboTargets(index: number): Set<string> {
    const snapshot = this.snapshot;
    const combo = snapshot?.combos?.find((c) => c.index === index);
    if (!snapshot || !combo) return new Set();
    const triggers = triggerKeys(
      comboView(combo, this.pending).triggers.keys.map((entry) =>
        this.resolveValue(entry.text, entry.saved, 'comboTrigger', () => this.keyboard.refreshCombo()),
      ),
    );
    const base = this.layerIndex === 0 ? undefined : snapshot.layers.find((layer) => layer.index === 0);
    const keys = this.slots
      .filter((slot) => slot.key)
      .map((slot) => {
        const value = this.values.get(slot.id);
        return [slot.id, effectiveKey(value, value?.kind === 'transparent' ? this.baseValueAt(slot, base) : null)] as const;
      });
    return comboTargets(keys, triggers);
  }

  /** コンボのボタンの説明（名前・同時に押すキー・出すキー・押せない印） */
  private describeCombo(index: number): Node | null {
    const combo = this.snapshot?.combos?.find((c) => c.index === index);
    if (!combo) return null;
    const view = comboView(combo, this.pending);
    return comboContent({
      index: combo.index,
      name: combo.name,
      description: view.description.value,
      triggers: view.triggers.keys.map((entry) => entry.text).filter((text) => text !== ''),
      output: view.output.text,
      reachable: combo.reachable,
      matches: this.comboTargets(index).size,
    });
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
    this.setPending(addPending(this.pending, change, slot.saved));
    this.options.host.change(change);
    this.renderHeader();
    this.updateSlot(slot);
  }

  /** 「割り当てを消す」: 行ごと消して「書いていない」にする（tasks-v0.2.md の決めたことの 3） */
  private remove(slotId: string): void {
    const slot = this.slots.find((s) => s.id === slotId);
    if (!slot || currentText(slot, this.edits) === '') return;
    const change: RemoveChange = { op: 'remove', address: slot.address };
    this.setPending(addPending(this.pending, change, slot.saved));
    this.options.host.edit(change);
    this.renderHeader();
    this.updateSlot(slot);
  }

  /** 注記を決めた。空なら注記だけを消す */
  private commitNote(slotId: string, note: string): void {
    const slot = this.slots.find((s) => s.id === slotId);
    if (!slot || note === currentNote(slot, this.edits)) return;
    if (note === '') {
      const change: RemoveChange = { op: 'remove', address: slot.address, field: 'note' };
      this.setPending(addPending(this.pending, change, slot.saved));
      this.options.host.edit(change);
    } else {
      const change: Change = { address: slot.address, value: note, field: 'note' };
      this.setPending(addPending(this.pending, change, slot.saved));
      this.options.host.change(change);
    }
    this.renderHeader();
    this.updateSlot(slot);
  }

  /** 位置の名前を変える（ホストが確認してすぐ書く）。名前の決まりに合わなければその理由 */
  private renamePosition(slotId: string, to: string): string | null {
    const slot = this.slots.find((s) => s.id === slotId);
    const key = slot?.key;
    if (!slot || !key) return null;
    if (to === '') return '名前を入れてください';
    if (/^\s|\s$/.test(to)) return '名前の前後に空白は入れられません';
    const clash = this.snapshot?.positionMap.some(
      (entry) => entry.hand === slot.hand && entry.group === key.group && entry.symbol === to && !(entry.row === key.row && entry.col === key.col),
    );
    if (clash) return `同じ段に「${to}」があります`;
    this.options.host.itemEdit({ op: 'renamePosition', hand: slot.hand, row: key.row, col: key.col, to });
    return null;
  }

  private async describe(slotId: string): Promise<Node | null> {
    const slot = this.slots.find((s) => s.id === slotId);
    if (!slot) return null;
    const text = currentText(slot, this.edits);
    if (!text) return null;
    const changed = valueChanged(slot, this.edits);
    const result = await this.inspector.load(slot.context, text).catch(() => undefined);
    const saved = changed ? [] : (this.diagnostics.get(slot.id) ?? []);
    const own = result?.diagnostics ?? [];
    const diagnostics = [...saved, ...own.filter((d) => !saved.some((s) => s.message === d.message))];
    const context = slot.encoder ? slotLabel(slot) : undefined;
    const value = result ? result.value : slot.saved;
    const face = keyFaceNote(value);
    const base = value?.kind === 'transparent' && this.snapshot ? baseLayerValue(this.snapshot, this.layerIndex, slot) : null;
    return describeContent(text, result, {
      context,
      note: currentNote(slot, this.edits),
      diagnostics,
      ...(face ? { mark: face } : {}),
      ...(base ? { base: `${base.display.label}（${base.canonical}）` } : {}),
    });
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
