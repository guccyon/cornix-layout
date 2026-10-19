// マウスを載せたときの説明（keycode/inspect の description）。画面に 1 つだけ置き、載せた要素の下に出す。
import type { Diagnostic, InspectResult } from '../protocol';
import { h } from './dom';

const SHOW_DELAY_MS = 350;

let tooltip: HTMLElement | undefined;
let current: HTMLElement | undefined;

function element(): HTMLElement {
  if (!tooltip || !tooltip.isConnected) {
    tooltip = h('div', { class: 'tooltip', role: 'tooltip', hidden: true });
    document.body.append(tooltip);
  }
  return tooltip;
}

export function showTooltip(anchor: HTMLElement, content: Node): void {
  const tip = element();
  tip.replaceChildren(content);
  tip.hidden = false;
  current = anchor;
  const rect = anchor.getBoundingClientRect();
  const width = tip.offsetWidth;
  const left = Math.max(4, Math.min(rect.left, window.innerWidth - width - 4));
  const below = rect.bottom + 6;
  const top = below + tip.offsetHeight > window.innerHeight && rect.top > tip.offsetHeight + 6 ? rect.top - tip.offsetHeight - 6 : below;
  tip.style.left = `${left}px`;
  tip.style.top = `${top}px`;
}

export function hideTooltip(anchor?: HTMLElement): void {
  if (anchor && anchor !== current) return;
  current = undefined;
  if (tooltip) tooltip.hidden = true;
}

/** 載せてしばらくしたら content() の結果を出す。null なら出さない */
export function attachTooltip(target: HTMLElement, content: () => Promise<Node | null>): void {
  let timer: ReturnType<typeof setTimeout> | undefined;
  let hovering = false;
  target.addEventListener('mouseenter', () => {
    hovering = true;
    timer = setTimeout(() => {
      void content().then(
        (node) => {
          if (hovering && node) showTooltip(target, node);
        },
        () => undefined,
      );
    }, SHOW_DELAY_MS);
  });
  const leave = () => {
    hovering = false;
    if (timer) clearTimeout(timer);
    hideTooltip(target);
  };
  target.addEventListener('mouseleave', leave);
  target.addEventListener('mousedown', leave);
}

/** 説明の中身: 題・説明の行・注記・その欄の問題 */
export function describeContent(
  text: string,
  result: InspectResult | undefined,
  options: { note?: string | undefined; diagnostics?: readonly Diagnostic[] } = {},
): Node | null {
  if (!text && !options.diagnostics?.length) return null;
  const root = h('div', { class: 'tooltip-body' });
  const title = result?.description?.title ?? result?.value?.canonical ?? text;
  root.append(h('div', { class: 'tooltip-title' }, title));
  if (result?.value && result.value.text !== title) root.append(h('div', { class: 'tooltip-code' }, result.value.text));
  for (const line of result?.description?.lines ?? []) root.append(h('div', { class: 'tooltip-line' }, line));
  const note = options.note ?? result?.value?.note;
  if (note) root.append(h('div', { class: 'tooltip-note' }, `注記: ${note}`));
  const diagnostics = options.diagnostics ?? result?.diagnostics ?? [];
  for (const diagnostic of diagnostics) {
    root.append(h('div', { class: `tooltip-diagnostic ${diagnostic.severity}` }, `${diagnostic.severity === 'error' ? 'エラー' : '警告'}: ${diagnostic.message}`));
  }
  return root;
}
