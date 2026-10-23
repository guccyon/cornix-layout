// @vitest-environment happy-dom
// v0.3 の欄と節（tasks-v0.3.md の E2）: 節を畳む・placeholder を出さない・同梱のショートカットを選ぶ／コピー・preset の展開・
// コンボの「図から選ぶ」・押せないコンボの印
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import type { CandidateContext, ComboSnapshot, ProfileSnapshot } from '../../../src/protocol';
import { ComboEditor, PICK_LABEL, PICKING_LABEL, UNREACHABLE_MESSAGE } from '../../../src/webview/comboEditor';
import { KeyInput, PRESET_ROW_LABEL, PRESET_SHORTCUT_CONTEXTS } from '../../../src/webview/keyInput';
import { MacroEditor } from '../../../src/webview/macroEditor';
import { MetadataView } from '../../../src/webview/metadataView';
import { presetEntries } from '../../../src/webview/presetPicker';
import { SettingsEditor } from '../../../src/webview/settingsEditor';
import { ShortcutEditor } from '../../../src/webview/shortcutEditor';
import { TapDanceEditor } from '../../../src/webview/tapDanceEditor';
import { hideTooltip } from '../../../src/webview/tooltip';
import * as data from '../../fake-server/fixtures';
import { FakeHost, fixtureSnapshot, settle } from './fakeHost';
import { at, COMBO, COMBO_FILE, kv, MACRO, PRESET_MACRO, SHORTCUTS, TAP_DANCE } from './itemFixtures';

let host: FakeHost;

function snapshot(overrides: Partial<ProfileSnapshot> = {}): ProfileSnapshot {
  return fixtureSnapshot({ macros: [MACRO, PRESET_MACRO], tapDances: [TAP_DANCE], combos: [COMBO], shortcuts: SHORTCUTS, ...overrides });
}

function mount<T extends { element: HTMLElement }>(section: T): T {
  document.body.append(section.element);
  return section;
}

function byFocus<T extends HTMLElement>(root: HTMLElement, focus: string): T {
  const element = root.querySelector<T>(`[data-focus='${focus}']`);
  if (!element) throw new Error(`${focus} がない`);
  return element;
}

function keydown(target: EventTarget, key: string): void {
  target.dispatchEvent(new KeyboardEvent('keydown', { key, bubbles: true, cancelable: true }));
}

beforeEach(() => {
  host = new FakeHost();
  document.body.replaceChildren();
});

afterEach(() => {
  hideTooltip();
  document.body.replaceChildren();
});

describe('節を畳む', () => {
  it('レイヤー以外の節は最初は畳んであり、開いた状態は snapshot の描き直しで戻らない', () => {
    const macros = mount(new MacroEditor({ host }));
    const settings = mount(new SettingsEditor({ onCommit: () => undefined }));
    const metadata = mount(new MetadataView());
    macros.update(snapshot(), []);
    settings.update(snapshot(), []);
    metadata.update(snapshot());
    const details = [macros, settings, metadata].map((section) => section.element.querySelector('details.section-details') as HTMLDetailsElement);
    expect(details.map((d) => d.open)).toEqual([false, false, false]);
    for (const d of details) d.open = true;
    const next = snapshot({ files: { 'layers/0_base.yml': 'sha256:01' }, diagnostics: [{ severity: 'warning', source: 'semantic', message: 'x', address: at(MACRO.file, 'description') }] });
    macros.update(next, []);
    settings.update(next, []);
    metadata.update({ ...next, metadata: { name: 'changed' } });
    expect(details.map((d) => d.open)).toEqual([true, true, true]);
    expect(details.every((d) => d.isConnected)).toBe(true);
  });
});

describe('割り当てのない欄の placeholder', () => {
  it('中身の画面のキーの欄は、割り当てがなければ空白のまま（「（なし）」を出さない）', () => {
    const tapDances = mount(new TapDanceEditor({ host }));
    tapDances.update(snapshot(), []);
    const doubleTap = byFocus<HTMLInputElement>(tapDances.element, 'action:doubleTap');
    expect(doubleTap.value).toBe('');
    expect(doubleTap.placeholder).toBe('');
  });
});

describe('同梱のショートカットの木', () => {
  it("kind: 'shortcut' はキーの組の項目だけ（macro: true は出さない）を、insertText と text 付きで出す", () => {
    expect(presetEntries(data.SHORTCUT_TREE, '', 'shortcut')).toEqual([
      { app: 'VS Code', icon: 'material-icon-theme:vscode', category: '基本操作', label: 'コマンドパレット', name: "Shortcut('VS Code:基本操作:コマンドパレット')", text: 'Shift + Command + P' },
      { app: 'Figma', icon: 'simple-icons:figma', category: 'ツール', label: 'フレーム', name: "Shortcut('Figma:ツール:フレーム')", text: 'F' },
    ]);
    expect(presetEntries(data.SHORTCUT_TREE).map((e) => e.label)).toEqual(['キーボードショートカット']);
    expect(presetEntries(data.SHORTCUT_TREE, 'figma', 'shortcut').map((e) => e.label)).toEqual(['フレーム']);
  });
});

describe('キー入力欄の「同梱から選ぶ…」', () => {
  let commits: string[];

  function makeInput(context: CandidateContext, presetShortcuts = true): KeyInput {
    const input = new KeyInput({ context, host, label: 'テスト', onCommit: (text) => commits.push(text), debounceMs: 0, presetShortcuts });
    document.body.replaceChildren(input.element);
    input.setValue('Q');
    input.input.focus();
    return input;
  }

  function rows(input: KeyInput): HTMLElement[] {
    return [...input.element.querySelectorAll<HTMLElement>('.candidates [role="option"]')];
  }

  beforeEach(() => {
    commits = [];
  });

  it('候補の一覧のいちばん下に置き、選ぶと階層の選択を開いて Shortcut(...) を入れる', async () => {
    const input = makeInput('layerKey');
    input.input.value = 'Sp';
    input.input.dispatchEvent(new Event('input'));
    await settle(10);
    const list = rows(input);
    expect(list.at(-1)?.textContent).toContain(PRESET_ROW_LABEL);
    // 最初に選んでおくのは候補（「同梱から選ぶ…」ではない）
    expect(list.at(-1)?.classList.contains('active')).toBe(false);
    // 矢印で「同梱から選ぶ…」まで行って Enter
    keydown(input.input, 'ArrowUp');
    expect(list.at(-1)?.classList.contains('active')).toBe(true);
    keydown(input.input, 'Enter');
    await settle(0);
    expect(input.isOpen).toBe(false);
    expect(input.isPickingPreset).toBe(true);
    // 打ちかけの文字は捨てて、決まっている値に戻す（決めない）
    expect(input.input.value).toBe('Q');
    expect(commits).toEqual([]);
    // 手順の定義（macro: true）は出さない
    const items = [...input.element.querySelectorAll<HTMLButtonElement>('.preset-item')];
    expect(items.map((e) => e.dataset.preset)).toEqual(["Shortcut('VS Code:基本操作:コマンドパレット')", "Shortcut('Figma:ツール:フレーム')"]);
    expect(items[0]?.textContent).toContain('Shift + Command + P');
    items[0]!.click();
    expect(commits).toEqual(["Shortcut('VS Code:基本操作:コマンドパレット')"]);
    expect(input.input.value).toBe("Shortcut('VS Code:基本操作:コマンドパレット')");
    expect(input.isPickingPreset).toBe(false);
    expect(document.activeElement).toBe(input.input);
  });

  it('候補が空でも出し、押しても開ける。Escape で閉じて欄に戻る', async () => {
    const input = makeInput('tapDanceAction');
    input.input.value = 'zzzz';
    input.input.dispatchEvent(new Event('input'));
    await settle(10);
    expect(input.element.querySelector('.candidates-empty')).not.toBeNull();
    const row = rows(input).at(-1)!;
    expect(row.classList.contains('presets-row')).toBe(true);
    row.click();
    await settle(0);
    expect(input.isPickingPreset).toBe(true);
    keydown(input.element.querySelector('.preset-search')!, 'Escape');
    expect(input.isPickingPreset).toBe(false);
    expect(document.activeElement).toBe(input.input);
    expect(commits).toEqual([]);
  });

  it('Shortcut(...) を書けない context（マクロのキー・コンボのトリガー・ショートカットの値）と、presetShortcuts のない欄では出さない', async () => {
    expect([...PRESET_SHORTCUT_CONTEXTS].sort()).toEqual(['comboOutput', 'encoder', 'layerKey', 'tapDanceAction']);
    for (const [context, flag] of [
      ['macroKey', true],
      ['comboTrigger', true],
      ['shortcutValue', true],
      ['layerKey', false],
    ] as const) {
      const input = makeInput(context, flag);
      input.input.value = 'Sp';
      input.input.dispatchEvent(new Event('input'));
      await settle(10);
      expect(input.isOpen).toBe(true);
      expect(input.element.querySelector('.presets-row')).toBeNull();
      input.dispose();
    }
  });
});

describe('ショートカットの節の「追加」の同梱から（v0.3 の「同梱からコピー」）', () => {
  it('選んだものを名前はラベル・値は同梱の表記で足す', async () => {
    const shortcuts = mount(new ShortcutEditor({ host }));
    shortcuts.update(snapshot(), []);
    expect(shortcuts.element.querySelector("[data-focus='shortcut-preset-pick']")).toBeNull();
    byFocus<HTMLButtonElement>(shortcuts.element, 'add-menu').click();
    await settle(0);
    const items = [...shortcuts.element.querySelectorAll<HTMLButtonElement>('.add-menu-bundled .preset-item')];
    expect(items.map((e) => e.firstChild?.textContent)).toEqual(['コマンドパレット', 'フレーム']);
    items[1]!.click();
    expect(host.itemEdits).toEqual([{ op: 'create', kind: 'shortcut', name: 'フレーム', value: 'F' }]);
    expect(shortcuts.formOpen).toBe(false);
  });

  it('同じ名前があれば、名前と値を入れた追加の欄を開いてエラーを見せる', async () => {
    const shortcuts = mount(new ShortcutEditor({ host }));
    shortcuts.update(snapshot({ shortcuts: [...SHORTCUTS, { name: 'コマンドパレット', address: at('shortcuts.yaml', 'shortcuts', 'コマンドパレット'), value: kv('Shift + Command + P') }] }), []);
    byFocus<HTMLButtonElement>(shortcuts.element, 'add-menu').click();
    await settle(0);
    shortcuts.element.querySelector<HTMLButtonElement>('.add-menu-bundled .preset-item')!.click();
    expect(host.itemEdits).toEqual([]);
    expect(shortcuts.formOpen).toBe(true);
    const form = shortcuts.element.querySelector('.item-name-form')!;
    expect(form.querySelector<HTMLInputElement>('.item-name-input')?.value).toBe('コマンドパレット');
    expect(form.querySelector<HTMLInputElement>('.key-input-field')?.value).toBe('Shift + Command + P');
    expect(form.textContent).toContain('ショートカット「コマンドパレット」はすでにあります');
    // 名前を変えて足す
    const name = form.querySelector<HTMLInputElement>('.item-name-input')!;
    name.value = 'パレット';
    keydown(name, 'Enter');
    expect(host.itemEdits).toEqual([{ op: 'create', kind: 'shortcut', name: 'パレット', value: 'Shift + Command + P' }]);
  });
});

describe('マクロの「手順に展開」', () => {
  it('preset: のマクロにだけボタンを置き、押すと itemEdit の expandPreset を渡す', () => {
    const macros = mount(new MacroEditor({ host }));
    macros.update(snapshot(), []);
    expect(macros.element.querySelector("[data-focus='expand-preset']")).toBeNull();
    macros.select('Copy Selected');
    byFocus<HTMLButtonElement>(macros.element, 'expand-preset').click();
    expect(host.itemEdits).toEqual([{ op: 'expandPreset', kind: 'macro', name: 'Copy Selected' }]);
  });
});

describe('コンボの「図から選ぶ」', () => {
  type Picking = { onPick: (text: string) => void; stopped: number };

  function comboWith(pickings: Picking[]): ComboEditor {
    const combos = mount(
      new ComboEditor({
        host,
        pickKey: (onPick) => {
          const picking: Picking = { onPick, stopped: 0 };
          pickings.push(picking);
          return () => picking.stopped++;
        },
      }),
    );
    return combos;
  }

  it('選んでいる間はボタンの文字を変え、選んだ表記を同時に押すキーの末尾に足す', () => {
    const pickings: Picking[] = [];
    const combos = comboWith(pickings);
    combos.update(snapshot(), []);
    const button = () => byFocus<HTMLButtonElement>(combos.element, 'pick-trigger');
    expect(button().textContent).toBe(PICK_LABEL);
    button().click();
    expect(pickings).toHaveLength(1);
    expect(combos.isPicking).toBe(true);
    expect(button().textContent).toBe(PICKING_LABEL);
    expect(button().getAttribute('aria-pressed')).toBe('true');
    pickings[0]!.onPick('E');
    expect(host.edits).toEqual([{ op: 'insert', address: at(COMBO_FILE, 'trigger_keys'), index: 2, value: 'E' }]);
    expect(combos.isPicking).toBe(false);
    expect(button().textContent).toBe(PICK_LABEL);
    // 抜けたあと（App が抜けてから呼ぶ）に止める関数は呼ばない
    expect(pickings[0]!.stopped).toBe(0);
  });

  it('NoKey の欄があればそこに入れる', () => {
    const pickings: Picking[] = [];
    const combos = comboWith(pickings);
    const fresh: ComboSnapshot = { ...COMBO, triggers: [COMBO.triggers[0]!, { address: at(COMBO_FILE, 'trigger_keys', 1), value: kv('NoKey') }] };
    combos.update(snapshot({ combos: [fresh] }), []);
    byFocus<HTMLButtonElement>(combos.element, 'pick-trigger').click();
    pickings[0]!.onPick('E');
    expect(host.changes).toEqual([{ address: at(COMBO_FILE, 'trigger_keys', 1), value: 'E' }]);
    expect(host.edits).toEqual([]);
  });

  it('もう一度押すか Esc で選ばずに抜ける。4 つともキーがあれば押せない。pickKey がなければ出さない', () => {
    const pickings: Picking[] = [];
    const combos = comboWith(pickings);
    combos.update(snapshot(), []);
    const button = () => byFocus<HTMLButtonElement>(combos.element, 'pick-trigger');
    button().click();
    button().click();
    expect(pickings[0]!.stopped).toBe(1);
    expect(combos.isPicking).toBe(false);
    expect(button().textContent).toBe(PICK_LABEL);
    button().click();
    keydown(document.body, 'Escape');
    expect(pickings[1]!.stopped).toBe(1);
    expect(combos.isPicking).toBe(false);
    expect(button().getAttribute('aria-pressed')).toBe('false');

    const full: ComboSnapshot = { ...COMBO, triggers: ['Q', 'W', 'E', 'R'].map((key, i) => ({ address: at(COMBO_FILE, 'trigger_keys', i), value: kv(key) })) };
    combos.update(snapshot({ combos: [full] }), []);
    expect(button().disabled).toBe(true);

    const plain = mount(new ComboEditor({ host }));
    plain.update(snapshot(), []);
    expect(plain.element.querySelector("[data-focus='pick-trigger']")).toBeNull();
  });
});

describe('押せないコンボの印', () => {
  it('reachable が false のコンボは、一覧の行に ⚠ と説明を出す（true・なしなら出さない。詳細はサーバーの警告に任せる）', () => {
    const combos = mount(new ComboEditor({ host }));
    const other: ComboSnapshot = { ...COMBO, index: 1, name: 'Right Bracket', file: 'combos/01_right_bracket.yml', reachable: true };
    combos.update(snapshot({ combos: [{ ...COMBO, reachable: false }, other] }), []);
    const rows = [...combos.element.querySelectorAll<HTMLElement>('.item-row')];
    expect(rows.map((r) => r.querySelector('.item-mark')?.textContent ?? null)).toEqual(['⚠', null]);
    expect(rows[0]!.querySelector('.item-mark')?.getAttribute('title')).toBe(UNREACHABLE_MESSAGE);
    combos.update(snapshot(), []);
    expect(combos.element.querySelector('.item-mark')).toBeNull();
  });
});
