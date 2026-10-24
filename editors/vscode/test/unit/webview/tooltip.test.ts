// @vitest-environment happy-dom
// 説明の置き場所。avoid を渡したら、その要素に重ならない所に出す（コンボのボタンの説明が図のキーを隠さないように）
import { afterEach, describe, expect, it } from 'vitest';
import { hideTooltip, showTooltip } from '../../../src/webview/tooltip';

const rect = (top: number, bottom: number) => ({ top, bottom, left: 10, right: 60, width: 50, height: bottom - top, x: 10, y: top, toJSON: () => ({}) }) as DOMRect;

function box(top: number, bottom: number): HTMLElement {
  const element = document.createElement('div');
  element.getBoundingClientRect = () => rect(top, bottom);
  document.body.append(element);
  return element;
}

function tip(): HTMLElement {
  return document.querySelector<HTMLElement>('.tooltip')!;
}

afterEach(() => {
  hideTooltip();
  document.body.replaceChildren();
});

describe('showTooltip の置き場所', () => {
  it('avoid がなければ anchor のすぐ下', () => {
    showTooltip(box(10, 30), document.createTextNode('説明'));
    expect(tip().style.top).toBe('36px');
  });

  it('avoid の下に入れば、その下に出す', () => {
    Object.defineProperty(window, 'innerHeight', { value: 800, configurable: true });
    showTooltip(box(10, 30), document.createTextNode('説明'), box(40, 400));
    expect(tip().style.top).toBe('406px');
  });

  it('avoid の下に入らなければ anchor の上、それも入らなければいつもの所', () => {
    Object.defineProperty(window, 'innerHeight', { value: 300, configurable: true });
    const tall = document.createElement('div');
    const original = Object.getOwnPropertyDescriptor(HTMLElement.prototype, 'offsetHeight');
    Object.defineProperty(HTMLElement.prototype, 'offsetHeight', { value: 50, configurable: true });
    showTooltip(box(200, 220), tall, box(230, 290));
    expect(tip().style.top).toBe('144px');
    showTooltip(box(10, 30), tall, box(40, 290));
    expect(tip().style.top).toBe('36px');
    if (original) Object.defineProperty(HTMLElement.prototype, 'offsetHeight', original);
    else delete (HTMLElement.prototype as { offsetHeight?: number }).offsetHeight;
  });
});
