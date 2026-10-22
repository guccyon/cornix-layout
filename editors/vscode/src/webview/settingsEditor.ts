// QMK 設定の欄（spec.md の「ファイルの種類ごと」の settings/qmk_settings.yaml）。整数は数値、真偽値はチェックボックスで、説明と既定値を添える。
// 値を決めたら（change）Change をホストに渡す。描き直しはホストからの snapshot と未保存の変更で行う（打ちかけの欄はそのまま残す）。
// v0.3: 節は最初は畳んでおく（details は作り直さないので、開いた状態は描き直しで戻らない）。
import type { Change, Diagnostic, ProfileSnapshot, QmkSettingSnapshot } from '../protocol';
import { h, nodes } from './dom';
import { addressKey, changeMap, diagnosticsByAddress, severityOf } from './model';

export type SettingsEditorOptions = {
  /** 値を決めた */
  onCommit: (change: Change) => void;
};

type Row = {
  setting: QmkSettingSnapshot;
  element: HTMLElement;
  input: HTMLInputElement;
  message: HTMLElement;
  info: HTMLElement;
  /** 打ったが決めていない（描き直しで上書きしない） */
  typing: boolean;
  /** この欄だけで分かる誤り（整数でない・空） */
  local: string | undefined;
};

const GROUP_LABELS: Record<string, string> = { keyboard: 'キーボード（keyboard）', vial: 'Vial（vial）' };

export class SettingsEditor {
  readonly element: HTMLElement;
  private readonly body: HTMLElement;
  private readonly rows = new Map<string, Row>();
  private structure = '';
  private changes = new Map<string, Change>();
  private diagnostics = new Map<string, Diagnostic[]>();

  constructor(private readonly options: SettingsEditorOptions) {
    this.body = h('div', { class: 'settings-body' });
    this.element = h(
      'section',
      { class: 'settings-editor', 'aria-label': 'QMK 設定' },
      h('details', { class: 'section-details' }, h('summary', {}, h('h2', {}, 'QMK 設定')), this.body),
    );
  }

  /** v0.4: 検証の結果の行から移る。節を開いてその設定の欄へ（address は settings/qmk_settings.yaml の [group, name]）。移ったら true */
  revealAddress(address: { file: string; path: (string | number)[] }): boolean {
    const row = [...this.rows.values()].find((r) => r.setting.address.file === address.file && r.setting.address.path.join('.') === address.path.join('.'));
    if (!row) return false;
    const details = this.element.querySelector('details');
    if (details) details.open = true;
    row.element.scrollIntoView?.({ block: 'nearest', behavior: 'smooth' });
    row.input.focus();
    return true;
  }

  /** 開いている入力欄（テスト用） */
  input(key: string): HTMLInputElement | undefined {
    return this.rows.get(key)?.input;
  }

  update(snapshot: ProfileSnapshot, changes: Change[]): void {
    this.changes = changeMap(changes);
    this.diagnostics = diagnosticsByAddress(snapshot).byAddress;
    const settings = snapshot.status === 'ok' ? snapshot.settings : [];
    this.element.hidden = settings.length === 0;
    const structure = JSON.stringify(settings.map((s) => [addressKey(s.address), s.type, s.group]));
    if (structure !== this.structure) {
      this.structure = structure;
      this.build(settings);
    }
    for (const setting of settings) {
      const row = this.rows.get(addressKey(setting.address));
      if (row) {
        row.setting = setting;
        this.render(row);
      }
    }
  }

  private build(settings: QmkSettingSnapshot[]): void {
    this.rows.clear();
    this.body.replaceChildren();
    const groups = [...new Set(settings.map((s) => s.group))];
    for (const group of groups) {
      const list = h('div', { class: 'settings-group' }, h('h3', {}, GROUP_LABELS[group] ?? group));
      for (const setting of settings.filter((s) => s.group === group)) list.append(this.row(setting));
      this.body.append(list);
    }
  }

  private row(setting: QmkSettingSnapshot): HTMLElement {
    const key = addressKey(setting.address);
    const id = `setting-${setting.group}-${setting.name}`;
    const input =
      setting.type === 'boolean'
        ? h('input', { type: 'checkbox', id, class: 'setting-checkbox' })
        : h('input', { type: 'number', id, class: 'setting-number', step: 1, inputmode: 'numeric' });
    const message = h('div', { class: 'setting-message', 'aria-live': 'polite' });
    const info = h('div', { class: 'setting-info' });
    const element = h(
      'div',
      { class: 'setting', 'data-setting': key },
      h('label', { class: 'setting-name', for: id }, setting.name),
      h('div', { class: 'setting-control' }, input),
      info,
      message,
    );
    const row: Row = { setting, element, input, message, info, typing: false, local: undefined };
    this.rows.set(key, row);
    if (setting.type === 'boolean') {
      input.addEventListener('change', () => this.commit(row, input.checked));
    } else {
      input.addEventListener('input', () => {
        row.typing = true;
      });
      input.addEventListener('change', () => this.commitNumber(row));
      input.addEventListener('keydown', (event) => {
        if (event.key !== 'Escape') return;
        row.typing = false;
        row.local = undefined;
        this.render(row);
      });
    }
    return element;
  }

  private commitNumber(row: Row): void {
    const text = row.input.value.trim();
    row.typing = false;
    // type="number" の欄は数でない文字を打つと value が空になる（badInput）
    if (row.input.validity.badInput) {
      row.local = '整数を入れてください';
      this.renderMessage(row);
      return;
    }
    if (text === '') {
      // v0.1 には設定を消す操作がない（ファイルから消すのはテキストで）
      const current = this.changes.get(addressKey(row.setting.address))?.value ?? row.setting.value;
      row.local = current === null ? undefined : '空にはできません（設定を消すときはテキストで直してください）';
      this.render(row);
      return;
    }
    if (!/^-?\d+$/.test(text)) {
      row.local = '整数を入れてください';
      this.renderMessage(row);
      return;
    }
    this.commit(row, Number(text));
  }

  private commit(row: Row, value: number | boolean): void {
    row.local = undefined;
    const key = addressKey(row.setting.address);
    const change: Change = { address: row.setting.address, value };
    // ホストの snapshot を待たずに印を描く（ホストは保存済みの値と同じなら変更から外す）
    if (value === row.setting.value) this.changes.delete(key);
    else this.changes.set(key, change);
    this.options.onCommit(change);
    this.render(row);
  }

  private render(row: Row): void {
    const { setting, input } = row;
    const key = addressKey(setting.address);
    const change = this.changes.get(key);
    const value = change ? change.value : setting.value;
    if (setting.type === 'boolean') {
      // ファイルにない設定は既定値で描き、どちらとも決めていない印（indeterminate）を付ける。
      // 押すとその値を書く（既定値と同じ値でも「書いていない」とは違う変更として残す）
      input.checked = value === null ? setting.default === true : value === true;
      input.indeterminate = value === null;
    } else if (!row.typing && !row.local) {
      input.value = typeof value === 'number' ? String(value) : '';
      input.placeholder = typeof setting.default === 'number' ? `既定 ${setting.default}` : '';
    }
    row.element.classList.toggle('changed', change !== undefined);
    row.info.replaceChildren(
      ...nodes(
        setting.description && h('span', { class: 'setting-description' }, setting.description),
        setting.default !== null && h('span', { class: 'setting-default' }, `既定値: ${formatValue(setting.default)}`),
        value === null && h('span', { class: 'setting-unset' }, 'ファイルに書いていません'),
      ),
    );
    this.renderMessage(row);
  }

  private renderMessage(row: Row): void {
    const diagnostics = this.diagnostics.get(addressKey(row.setting.address)) ?? [];
    const severity = row.local ? 'error' : severityOf(diagnostics);
    row.element.classList.toggle('error', severity === 'error');
    row.element.classList.toggle('warning', severity === 'warning');
    row.input.setAttribute('aria-invalid', String(severity === 'error'));
    const lines = [
      ...(row.local ? [h('div', { class: 'message-line error' }, row.local)] : []),
      ...diagnostics.map((d) => h('div', { class: `message-line ${d.severity}` }, d.message)),
    ];
    row.message.replaceChildren(...lines);
  }
}

function formatValue(value: number | boolean): string {
  if (typeof value === 'boolean') return value ? 'オン' : 'オフ';
  return String(value);
}
