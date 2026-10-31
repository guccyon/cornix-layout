// @vitest-environment happy-dom
// QMK 設定の欄とメタデータの表示、App の下のペインへの置き方、保存前の検証の結果の出し方
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { CORNIX } from '../../../src/keyboard/cornix';
import type { Change } from '../../../src/protocol';
import { App } from '../../../src/webview/app';
import { MetadataView } from '../../../src/webview/metadataView';
import { addressKey } from '../../../src/webview/model';
import { SettingsEditor } from '../../../src/webview/settingsEditor';
import { hideTooltip } from '../../../src/webview/tooltip';
import { FakeHost, fixtureSnapshot } from './fakeHost';

const settingsFile = 'settings/qmk_settings.yaml';
const tapping = addressKey({ file: settingsFile, path: ['keyboard', 'tapping_term'] });
const permissive = addressKey({ file: settingsFile, path: ['keyboard', 'permissive_hold'] });
const flowTap = addressKey({ file: settingsFile, path: ['keyboard', 'flow_tap'] });

let commits: Change[];
let editor: SettingsEditor;

function row(key: string): HTMLElement {
  const element = editor.element.querySelector<HTMLElement>(`[data-setting='${key}']`);
  if (!element) throw new Error(`${key} の欄がない`);
  return element;
}

function type(input: HTMLInputElement, value: string): void {
  input.value = value;
  input.dispatchEvent(new Event('input'));
  input.dispatchEvent(new Event('change'));
}

beforeEach(() => {
  commits = [];
  editor = new SettingsEditor({ onCommit: (change) => commits.push(change) });
  document.body.replaceChildren(editor.element);
});

afterEach(() => {
  hideTooltip();
  document.body.replaceChildren();
});

describe('QMK 設定の欄', () => {
  it('revealAddress: 節を開いてその設定の欄にフォーカスする。ほかのファイルなら何もしない', () => {
    editor.update(fixtureSnapshot(), []);
    expect(editor.revealAddress({ file: 'macros/a.yml', path: [] })).toBe(false);
    expect(editor.revealAddress({ file: settingsFile, path: ['keyboard', 'tapping_term'] })).toBe(true);
    expect(editor.element.querySelector('details')!.open).toBe(true);
    expect(document.activeElement?.closest<HTMLElement>('[data-setting]')?.dataset.setting).toBe(tapping);
  });

  it('整数は数値の欄、真偽値はチェックボックスで、グループごとに並べ、説明と既定値を添える', () => {
    editor.update(fixtureSnapshot(), []);
    expect([...editor.element.querySelectorAll('.settings-group h3')].map((e) => e.textContent)).toEqual(['Vial（vial）', 'キーボード（keyboard）']);
    expect(editor.input(tapping)?.type).toBe('number');
    expect(editor.input(tapping)?.value).toBe('180');
    expect(editor.input(permissive)?.type).toBe('checkbox');
    expect(editor.input(permissive)?.checked).toBe(false);
    expect(row(tapping).querySelector('.setting-description')?.textContent).toBe('タップとホールドを分ける時間（ミリ秒）');
    expect(row(tapping).querySelector('.setting-default')?.textContent).toBe('既定値: 200');
    expect(row(permissive).querySelector('.setting-default')?.textContent).toBe('既定値: オフ');
    // ファイルにない設定は空の欄と「書いていません」
    expect(editor.input(flowTap)?.value).toBe('');
    expect(row(flowTap).querySelector('.setting-unset')).not.toBeNull();
  });

  it('値を決めると数値・真偽値の Change を渡し、変えた印を付ける', () => {
    editor.update(fixtureSnapshot(), []);
    type(editor.input(tapping)!, '200');
    const checkbox = editor.input(permissive)!;
    checkbox.checked = true;
    checkbox.dispatchEvent(new Event('change'));
    expect(commits).toEqual([
      { address: { file: settingsFile, path: ['keyboard', 'tapping_term'] }, value: 200 },
      { address: { file: settingsFile, path: ['keyboard', 'permissive_hold'] }, value: true },
    ]);
    expect(row(tapping).classList.contains('changed')).toBe(true);
    // ホストから同じ変更の並びが返ってきても値はそのまま
    editor.update(fixtureSnapshot(), commits);
    expect(editor.input(tapping)?.value).toBe('200');
    expect(editor.input(permissive)?.checked).toBe(true);
    // 元の値に戻すと印が消える
    type(editor.input(tapping)!, '180');
    expect(row(tapping).classList.contains('changed')).toBe(false);
  });

  it('整数でない・空の値は渡さずに欄をエラーにする（Escape で戻す）', () => {
    editor.update(fixtureSnapshot(), []);
    type(editor.input(tapping)!, '1.5');
    expect(commits).toEqual([]);
    expect(row(tapping).classList.contains('error')).toBe(true);
    expect(row(tapping).querySelector('.setting-message')?.textContent).toBe('整数を入れてください');
    type(editor.input(tapping)!, '');
    expect(row(tapping).querySelector('.setting-message')?.textContent).toContain('空にはできません');
    editor.input(tapping)!.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape' }));
    expect(editor.input(tapping)?.value).toBe('180');
    expect(row(tapping).classList.contains('error')).toBe(false);
    // ファイルにない設定を空のまま決めても何もしない
    type(editor.input(flowTap)!, '');
    expect(row(flowTap).classList.contains('error')).toBe(false);
  });

  it('数でない文字（badInput）は「整数を入れてください」', () => {
    editor.update(fixtureSnapshot(), []);
    const input = editor.input(tapping)!;
    Object.defineProperty(input, 'validity', { value: { badInput: true } });
    type(input, '');
    expect(commits).toEqual([]);
    expect(row(tapping).querySelector('.setting-message')?.textContent).toBe('整数を入れてください');
  });

  it('ファイルにない真偽値の設定は既定値で描き、決めていない印を付ける', () => {
    const settings = fixtureSnapshot().settings.map((s) => (s.name === 'permissive_hold' ? { ...s, value: null, default: true } : s));
    editor.update(fixtureSnapshot({ settings }), []);
    expect(editor.input(permissive)?.checked).toBe(true);
    expect(editor.input(permissive)?.indeterminate).toBe(true);
    expect(row(permissive).querySelector('.setting-unset')).not.toBeNull();
  });

  it('検証の結果（diagnostics）をその設定の欄に出す', () => {
    const address = { file: settingsFile, path: ['keyboard', 'tapping_term'] };
    editor.update(fixtureSnapshot({ diagnostics: [{ severity: 'warning', source: 'semantic', message: '短すぎます', address }] }), []);
    expect(row(tapping).classList.contains('warning')).toBe(true);
    expect(row(tapping).querySelector('.setting-message')?.textContent).toBe('短すぎます');
  });

  it('読めないプロファイルでは出さない', () => {
    editor.update(fixtureSnapshot({ status: 'invalid', settings: [] }), []);
    expect(editor.element.hidden).toBe(true);
  });
});

describe('メタデータの表示', () => {
  it('metadata.yaml の中身を読むだけの表で出し、position_map は出さない', () => {
    const view = new MetadataView();
    view.update(fixtureSnapshot());
    const terms = [...view.element.querySelectorAll('.metadata-table > tbody > tr > th')].map((e) => e.textContent);
    expect(terms).toEqual(['keyboard', 'version', 'vial_protocol', 'via_protocol']);
    expect(view.element.querySelector('td')?.textContent).toBe('cornix');
    expect(view.element.querySelector('input')).toBeNull();
    expect(view.element.textContent).not.toContain('position_map');
    expect(view.element.querySelector('.position-row')).toBeNull();
  });

  it('入れ子の Hash と配列は JSON ではなく表の中の表で出す', () => {
    const view = new MetadataView();
    view.update(
      fixtureSnapshot({
        metadata: {
          keyboard: 'cornix',
          extra_keys: { layout_options: 0, alt_repeat_key: [], key_override: [] },
          file_naming: { layers: { pattern: '{index}_{name}.yaml', index_range: [0, 9] } },
          combos: [{ name: 'a', keys: ['Q', 'W'] }],
        },
      }),
    );
    expect(view.element.textContent).not.toContain('{"');
    const cell = (name: string) =>
      [...view.element.querySelectorAll<HTMLElement>('.metadata-table > tbody > tr')].find((row) => row.querySelector(':scope > th')?.textContent === name)!
        .querySelector(':scope > td')!;
    const extra = cell('extra_keys').querySelector(':scope > .metadata-table')!;
    expect([...extra.querySelectorAll(':scope > tbody > tr > th')].map((e) => e.textContent)).toEqual(['layout_options', 'alt_repeat_key', 'key_override']);
    expect(cell('alt_repeat_key').textContent).toBe('（空）');
    expect(cell('pattern').textContent).toBe('{index}_{name}.yaml');
    expect([...cell('index_range').querySelectorAll('.metadata-item')].map((e) => e.textContent)).toEqual(['0', '9']);
    expect(cell('layers').querySelector('.metadata-table')).not.toBeNull();
    expect(cell('combos').querySelector(':scope > .metadata-table > tbody > tr > th')?.textContent).toBe('1');
  });
});

describe('App の下のペイン', () => {
  it('QMK 設定とメタデータをレイヤーの欄のあとに置き、読めないプロファイルの表示では出さない', () => {
    const root = document.createElement('div');
    document.body.replaceChildren(root);
    const metadata = new MetadataView();
    const app = new App(root, { keyboard: CORNIX, host: new FakeHost(), sections: [editor.element, metadata.element] });
    app.receive({ type: 'snapshot', snapshot: fixtureSnapshot(), changes: [] });
    const bottom = root.querySelector('.bottom-pane');
    // v0.4: 一番下は節「デバイス転送」（App が置く）
    expect([...(bottom?.children ?? [])].slice(-3, -1)).toEqual([editor.element, metadata.element]);
    app.receive({ type: 'snapshot', snapshot: fixtureSnapshot({ status: 'invalid', layers: [], settings: [], positionMap: [] }), changes: [] });
    expect(root.contains(editor.element)).toBe(false);
    expect(root.querySelector('.invalid')).not.toBeNull();
  });

  it('保存前の検証の結果（ホストが snapshot の diagnostics に入れる）は、変えていない参照している側の欄にも出る', () => {
    const root = document.createElement('div');
    document.body.replaceChildren(root);
    const app = new App(root, { keyboard: CORNIX, host: new FakeHost() });
    const fn = { file: 'layers/0_base.yml', path: ['mapping', 'left_hand', 'row3', 'fn'] };
    const q = { file: 'layers/0_base.yml', path: ['mapping', 'left_hand', 'row0', 'Q'] };
    app.receive({
      type: 'snapshot',
      snapshot: fixtureSnapshot({ diagnostics: [{ severity: 'warning', source: 'semantic', message: 'ほかの項目の問題', address: fn }] }),
      changes: [{ address: q, value: 'MO(9)' }],
    });
    const field = root.querySelector<HTMLElement>(`.field[data-slot='${addressKey(fn)}']`);
    expect(field?.querySelector('.key-input')?.classList.contains('warning')).toBe(true);
    expect(field?.textContent).toContain('ほかの項目の問題');
  });
});
