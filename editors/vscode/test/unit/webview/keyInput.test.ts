// @vitest-environment happy-dom
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { KeyInput } from '../../../src/webview/keyInput';
import { FakeHost, settle } from './fakeHost';

let host: FakeHost;
let commits: string[];
let input: KeyInput;

function type(text: string): void {
  input.input.value = text;
  input.input.dispatchEvent(new Event('input'));
}

function key(name: string): void {
  input.input.dispatchEvent(new KeyboardEvent('keydown', { key: name, bubbles: true, cancelable: true }));
}

function options(): string[] {
  return [...input.element.querySelectorAll<HTMLElement>('[role="option"]')].map((o) => o.dataset.insertText ?? '');
}

beforeEach(() => {
  host = new FakeHost();
  commits = [];
  input = new KeyInput({ context: 'layerKey', host, label: 'テスト', onCommit: (text) => commits.push(text), debounceMs: 20 });
  document.body.replaceChildren(input.element);
  input.setValue('Q');
  input.input.focus();
});

afterEach(() => {
  document.body.replaceChildren();
});

describe('KeyInput の候補', () => {
  it('打つたびに間引いて聞き、最後の文字の候補だけを出す', async () => {
    type('c');
    type('cm');
    type('cmd');
    await settle();
    const queries = host.requests.filter((r) => r.method === 'keycode/candidates').map((r) => (r.params as { query: string }).query);
    expect(queries).toEqual(['cmd']);
    expect(host.requests[0]?.params).toMatchObject({ context: 'layerKey', limit: 50 });
    expect(input.isOpen).toBe(true);
  });

  it('古い要求の結果は、あとから返ってきても捨てる', async () => {
    host.holding = true;
    type('esc');
    await settle(40);
    type('spa');
    await settle(40);
    expect(host.heldCount).toBe(2);
    host.release(1); // 新しいほう（spa）を先に返す
    await settle(0);
    expect(options()).toContain('Space');
    host.release(0); // 古いほう（esc）
    await settle(0);
    expect(options()).toContain('Space');
    expect(options()).not.toContain('Escape');
  });

  it('typed は候補になければ先頭に「入力どおり」として出し、選ぶと打った表記のまま入れる', async () => {
    type('Cmd');
    await settle();
    expect(options()[0]).toBe('Cmd');
    expect(input.element.querySelector('.candidate.typed')?.textContent).toContain('入力どおり → LGui');
    key('Enter');
    expect(commits).toEqual(['Cmd']);
    expect(input.input.value).toBe('Cmd');
    expect(input.isOpen).toBe(false);
  });

  it('候補を選ぶと insertText を入れる（矢印で動かして Enter・クリック）', async () => {
    type('Cmd');
    await settle();
    key('ArrowDown');
    key('Enter');
    expect(commits).toEqual(['LGui']);
    expect(input.input.value).toBe('LGui');

    type('コマンドパレット');
    await settle();
    input.element.querySelector<HTMLElement>('[data-insert-text^="Shortcut"]')?.click();
    expect(commits.at(-1)).toBe("Shortcut('VS Code:基本操作:コマンドパレット')");
  });

  it('warning のある候補には印と理由を付け、アイコンのある候補にはアイコンを出す', async () => {
    type('re');
    await settle();
    const repeat = input.element.querySelector<HTMLElement>('[data-insert-text="Repeat"]');
    expect(repeat?.classList.contains('has-warning')).toBe(true);
    expect(repeat?.querySelector('.candidate-warning')?.getAttribute('aria-label')).toBe('Cornix は Repeat Key に対応していません');

    type('パレット');
    await settle();
    expect(input.element.querySelector('[data-icon="material-icon-theme:vscode"]')).not.toBeNull();
  });

  it('limit で切ったときは、続けて打つよう添える', async () => {
    host.limit = 5;
    type('');
    input.open();
    await settle();
    expect(input.element.querySelector('.candidates-more')).not.toBeNull();
  });
});

describe('KeyInput の決め方', () => {
  it('手で打った表記は解釈できればそのまま決める（欄を離れたとき）', () => {
    type('Shift + Command + P');
    input.input.dispatchEvent(new Event('blur'));
    expect(commits).toEqual(['Shift + Command + P']);
    expect(input.value).toBe('Shift + Command + P');
  });

  it('前と同じ値なら onCommit を呼ばない', () => {
    type('Q');
    key('Enter');
    expect(commits).toEqual([]);
  });

  it('空にしたら元の値に戻し、NoKey を選ぶよう添える', () => {
    type('  ');
    key('Enter');
    expect(commits).toEqual([]);
    expect(input.input.value).toBe('Q');
    expect(input.element.querySelector('.message-line.hint')?.textContent).toContain('NoKey');
  });

  it('Escape は候補を閉じ、閉じていれば打つ前の値に戻す', async () => {
    type('Esc');
    await settle();
    key('Escape');
    expect(input.isOpen).toBe(false);
    expect(input.input.value).toBe('Esc');
    key('Escape');
    expect(input.input.value).toBe('Q');
    expect(commits).toEqual([]);
  });

  it('打っている途中は外からの値で書き換えない', () => {
    type('Es');
    input.setValue('A');
    expect(input.input.value).toBe('Es');
    input.input.dispatchEvent(new Event('blur'));
    expect(commits).toEqual(['Es']);
  });

  it('検証の結果を印とメッセージにする', () => {
    input.setDiagnostics([{ severity: 'error', source: 'structure', message: '読めない表記です' }]);
    expect(input.element.classList.contains('error')).toBe(true);
    expect(input.input.getAttribute('aria-invalid')).toBe('true');
    expect(input.element.querySelector('.message-line.error')?.textContent).toBe('読めない表記です');
    input.setDiagnostics([{ severity: 'warning', source: 'semantic', message: '未対応のキーです' }]);
    expect(input.element.classList.contains('error')).toBe(false);
    expect(input.element.classList.contains('warning')).toBe(true);
  });
});
