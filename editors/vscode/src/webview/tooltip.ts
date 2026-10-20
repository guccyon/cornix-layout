// 説明（keycode/inspect の description）。画面に 1 つだけ置き、マウスを載せた要素かフォーカスした要素の下に出す。
// 出している間は、その要素に aria-describedby で説明を結ぶ。
import type { Diagnostic, InspectResult } from '../protocol';
import { h } from './dom';

const SHOW_DELAY_MS = 350;
export const TOOLTIP_ID = 'cornix-tooltip';

let tooltip: HTMLElement | undefined;
let current: HTMLElement | undefined;

function element(): HTMLElement {
  if (!tooltip || !tooltip.isConnected) {
    tooltip = h('div', { class: 'tooltip', role: 'tooltip', id: TOOLTIP_ID, hidden: true });
    document.body.append(tooltip);
  }
  return tooltip;
}

export function showTooltip(anchor: HTMLElement, content: Node): void {
  // 作り直しで消えた要素には出さない（mouseleave が来ず、出たまま残るため）
  if (!anchor.isConnected) return;
  if (current && current !== anchor) current.removeAttribute('aria-describedby');
  const tip = element();
  tip.replaceChildren(content);
  tip.hidden = false;
  current = anchor;
  anchor.setAttribute('aria-describedby', TOOLTIP_ID);
  const rect = anchor.getBoundingClientRect();
  const width = tip.offsetWidth;
  const left = Math.max(4, Math.min(rect.left, window.innerWidth - width - 4));
  const below = rect.bottom + 6;
  const top = below + tip.offsetHeight > window.innerHeight && rect.top > tip.offsetHeight + 6 ? rect.top - tip.offsetHeight - 6 : below;
  tip.style.left = `${left}px`;
  tip.style.top = `${top}px`;
}

/** 説明を消す。anchor を渡したら、その要素の説明を出しているときだけ消す */
export function hideTooltip(anchor?: HTMLElement): void {
  if (anchor && anchor !== current) return;
  current?.removeAttribute('aria-describedby');
  current = undefined;
  if (tooltip) tooltip.hidden = true;
}

export type TooltipOptions = {
  /** フォーカスしたときにも出すか。'visible' はキーボードでのフォーカス（:focus-visible）のときだけ */
  focus?: 'always' | 'visible';
  /** 今出してよいか（入力欄は候補の一覧を開いている間は出さない） */
  canShow?: () => boolean;
};

/** 載せて（フォーカスして）しばらくしたら content() の結果を出す。null なら出さない */
export function attachTooltip(target: HTMLElement, content: () => Promise<Node | null>, options: TooltipOptions = {}): void {
  let timer: ReturnType<typeof setTimeout> | undefined;
  let hovering = false;
  let focused = false;
  const wanted = () => (hovering || focused) && (options.canShow?.() ?? true);
  const schedule = (delay: number) => {
    if (timer) clearTimeout(timer);
    timer = setTimeout(() => {
      if (!wanted()) return;
      void content().then(
        (node) => {
          if (wanted() && node) showTooltip(target, node);
        },
        () => undefined,
      );
    }, delay);
  };
  const stop = () => {
    if (hovering || focused) return;
    if (timer) clearTimeout(timer);
    hideTooltip(target);
  };
  target.addEventListener('mouseenter', () => {
    hovering = true;
    schedule(SHOW_DELAY_MS);
  });
  target.addEventListener('mouseleave', () => {
    hovering = false;
    stop();
  });
  target.addEventListener('mousedown', () => {
    hovering = false;
    if (timer) clearTimeout(timer);
    hideTooltip(target);
  });
  if (options.focus) {
    target.addEventListener('focus', () => {
      if (options.focus === 'visible' && !matchesFocusVisible(target)) return;
      focused = true;
      schedule(0);
    });
    target.addEventListener('blur', () => {
      focused = false;
      stop();
    });
  }
}

function matchesFocusVisible(element: HTMLElement): boolean {
  try {
    return element.matches(':focus-visible');
  } catch {
    return false;
  }
}

/** 説明の中身: どの欄か・題・図の印の意味・説明の行・注記・その欄の問題 */
export function describeContent(
  text: string,
  result: InspectResult | undefined,
  options: { context?: string | undefined; note?: string | undefined; mark?: string; diagnostics?: readonly Diagnostic[] } = {},
): Node | null {
  if (!text && !options.diagnostics?.length) return null;
  const root = h('div', { class: 'tooltip-body' });
  // どの欄の説明か（図では印でしか分からないエンコーダの操作など）
  if (options.context) root.append(h('div', { class: 'tooltip-context' }, options.context));
  const title = result?.description?.title ?? result?.value?.canonical ?? text;
  root.append(h('div', { class: 'tooltip-title' }, title));
  if (result?.value && result.value.text !== title) root.append(h('div', { class: 'tooltip-code' }, result.value.text));
  if (options.mark) root.append(h('div', { class: 'tooltip-mark' }, options.mark));
  for (const line of result?.description?.lines ?? []) root.append(h('div', { class: 'tooltip-line' }, line));
  const note = options.note ?? result?.value?.note;
  if (note) root.append(h('div', { class: 'tooltip-note' }, `注記: ${note}`));
  const diagnostics = options.diagnostics ?? result?.diagnostics ?? [];
  for (const diagnostic of diagnostics) {
    root.append(h('div', { class: `tooltip-diagnostic ${diagnostic.severity}` }, `${diagnostic.severity === 'error' ? 'エラー' : '警告'}: ${diagnostic.message}`));
  }
  return root;
}
