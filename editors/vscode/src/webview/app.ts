// 編集画面の全体。上にキーボード図、下にレイヤーの編集画面（ADR 009）。選んでいるレイヤーと欄は上下で共有する。
// ホストから snapshot と未保存の変更（Change の並び）を受けて描き、欄で決めた値を Change としてホストに渡す。
// 未保存の値の表示の文字と検証は keycode/inspect で聞く（onchange の検証。ADR 012）。
import type { Change, Diagnostic, KeyValue, ProfileSnapshot } from '../protocol';
import type { HostMessage, WebviewMessage } from '../webviewMessages';
import { h, nodes } from './dom';
import type { HostClient } from './hostClient';
import { Inspector } from './inspector';
import { KeyboardView } from './keyboardView';
import { LayerEditor } from './layerEditor';
import { addressKey, changeMap, currentText, diagnosticsByAddress, layerSlots, layerTitle, severityOf, type Slot } from './model';
import { attachTooltip, describeContent } from './tooltip';

/** 画面を閉じても覚えておくもの（Webview の getState / setState） */
export type ViewState = { layer?: number };

export type AppOptions = {
  host: HostClient;
  /** 描き終えたら（統合テストが待つ） */
  onRendered?: (message: Extract<WebviewMessage, { type: 'rendered' }>) => void;
  state?: { get(): ViewState | undefined; set(state: ViewState): void };
};

export class App {
  private snapshot: ProfileSnapshot | undefined;
  private snapshotKey = '';
  private changes = new Map<string, Change>();
  private diagnostics = new Map<string, Diagnostic[]>();
  private generalDiagnostics: Diagnostic[] = [];
  private layerIndex: number | undefined;
  private selected: string | undefined;
  private slots: Slot[] = [];
  private readonly inspector: Inspector;

  private readonly keyboard: KeyboardView;
  private readonly editor: LayerEditor;
  private readonly tabs = h('div', { class: 'layer-tabs', role: 'tablist', 'aria-label': 'レイヤー' });
  private readonly header = h('header', { class: 'profile-header' });
  private readonly problems = h('div', { class: 'problems' });
  private readonly banner = h('div', { class: 'banner', role: 'alert', hidden: true });
  private readonly layerInfo = h('div', { class: 'layer-info' });

  constructor(
    private readonly root: HTMLElement,
    private readonly options: AppOptions,
  ) {
    this.inspector = new Inspector(options.host);
    this.layerIndex = options.state?.get()?.layer;
    const decorate = (element: HTMLElement, slot: Slot) => attachTooltip(element, () => this.describe(slot));
    this.keyboard = new KeyboardView({ onSelect: (id) => this.reveal(id), decorate });
    this.editor = new LayerEditor({
      host: options.host,
      onCommit: (slot, text) => this.commit(slot, text),
      onFocus: (id) => this.select(id),
      decorate,
    });
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
  get inputs() {
    return this.editor.inputs;
  }

  setSnapshot(snapshot: ProfileSnapshot, changes: Change[]): void {
    const key = JSON.stringify(snapshot);
    this.changes = changeMap(changes);
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
      this.renderInvalid(snapshot);
      this.rendered();
      return;
    }
    if (!snapshot.layers.some((layer) => layer.index === this.layerIndex)) this.layerIndex = snapshot.layers[0]?.index;
    this.root.replaceChildren(
      h(
        'div',
        { class: 'top-pane' },
        this.header,
        this.banner,
        this.tabs,
        this.keyboard.element,
      ),
      h('div', { class: 'bottom-pane' }, this.layerInfo, this.problems, this.editor.element),
    );
    this.renderHeader();
    this.renderProblems();
    this.renderLayer();
    this.rendered();
  }

  selectLayer(index: number): void {
    if (!this.snapshot?.layers.some((layer) => layer.index === index)) return;
    this.layerIndex = index;
    this.options.state?.set({ layer: index });
    this.renderLayer();
    this.rendered();
  }

  /** 欄を選ぶ（上下で共有） */
  select(slotId: string | undefined): void {
    this.selected = slotId;
    this.keyboard.setSelected(slotId);
    this.editor.setSelected(slotId);
  }

  /** 図のキーを押した: 下の該当の欄へ移る */
  reveal(slotId: string): void {
    this.select(slotId);
    this.editor.reveal(slotId);
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

  private renderLayer(): void {
    const snapshot = this.snapshot;
    if (!snapshot) return;
    const layer = snapshot.layers.find((l) => l.index === this.layerIndex);
    this.tabs.replaceChildren(
      ...snapshot.layers.map((l) => {
        const selected = l.index === this.layerIndex;
        const tab = h(
          'button',
          { type: 'button', class: `layer-tab${selected ? ' selected' : ''}`, role: 'tab', 'aria-selected': String(selected), title: l.file },
          layerTitle(l),
        );
        tab.addEventListener('click', () => this.selectLayer(l.index));
        return tab;
      }),
    );
    if (!layer) {
      this.slots = [];
      this.keyboard.setSlots([]);
      this.editor.setSlots([]);
      this.layerInfo.replaceChildren(h('p', {}, 'レイヤーがありません'));
      return;
    }
    this.layerInfo.replaceChildren(
      ...nodes(
        h('h2', {}, `レイヤー ${layerTitle(layer)}`, h('span', { class: 'layer-file' }, layer.file)),
        layer.description && h('p', { class: 'layer-description' }, layer.description),
      ),
    );
    this.slots = layerSlots(layer, snapshot.positionMap);
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
    const details = h('details', { class: 'problems-list' }, h('summary', {}, `ファイルの問題（${list.length} 件）`));
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
    this.root.replaceChildren(
      h(
        'div',
        { class: 'invalid' },
        h('header', { class: 'profile-header' }, h('span', { class: 'profile-name' }, snapshot.name), h('span', { class: 'profile-dir' }, snapshot.dir)),
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
    this.keyboard.update(slot.id, { text, value, severity: severityOf(diagnostics), changed });
    this.editor.update(slot.id, text, diagnostics, changed);
  }

  private refresh(slotId: string): void {
    const slot = this.slots.find((s) => s.id === slotId);
    if (slot) this.updateSlot(slot);
  }

  /** 欄で値を決めた: ホストに Change を渡し、すぐに検証する（ホストからの snapshot を待たずに描く） */
  private commit(slot: Slot, text: string): void {
    const change: Change = { address: slot.address, value: text };
    if (text === (slot.saved?.text ?? '')) this.changes.delete(slot.id);
    else this.changes.set(addressKey(slot.address), change);
    this.options.host.change(change);
    this.renderHeader();
    this.updateSlot(slot);
  }

  private async describe(slot: Slot): Promise<Node | null> {
    const text = currentText(slot, this.changes);
    if (!text) return null;
    const changed = this.changes.has(slot.id);
    const result = await this.inspector.load(slot.context, text).catch(() => undefined);
    const saved = changed ? [] : (this.diagnostics.get(slot.id) ?? []);
    const own = result?.diagnostics ?? [];
    const diagnostics = [...saved, ...own.filter((d) => !saved.some((s) => s.message === d.message))];
    return describeContent(text, result, { note: changed ? undefined : slot.saved?.note, diagnostics });
  }

  private rendered(): void {
    const keys = this.slots.filter((slot) => slot.key).length;
    this.options.onRendered?.({
      type: 'rendered',
      status: this.snapshot?.status ?? 'invalid',
      layer: this.layerIndex ?? null,
      keys,
      encoders: this.slots.length - keys,
      // media/webview.css の .board は position: relative
      styled: !!this.root.querySelector('.board') && getComputedStyle(this.root.querySelector('.board')!).position === 'relative',
    });
  }
}
