// 一覧の中のフォーカスを上下・Home/End で動かす（「…」メニュー・追加の一覧・番号の選択で共通）。
// 端では回り込む。キーを受け持ったら true（呼ぶ側で preventDefault する）

export function moveFocusInList(items: HTMLElement[], key: string, from: Element | null = document.activeElement): boolean {
  if (items.length === 0) return false;
  const index = from instanceof HTMLElement ? items.indexOf(from) : -1;
  let next: number;
  switch (key) {
    case 'ArrowDown':
      next = index < 0 ? 0 : (index + 1) % items.length;
      break;
    case 'ArrowUp':
      next = index < 0 ? items.length - 1 : (index - 1 + items.length) % items.length;
      break;
    case 'Home':
      next = 0;
      break;
    case 'End':
      next = items.length - 1;
      break;
    default:
      return false;
  }
  items[next]!.focus();
  return true;
}

/** 要素が閉じた details の中に隠れていないか（その details の summary は見えている） */
export function isShownInDetails(element: HTMLElement, root: HTMLElement): boolean {
  let node: HTMLElement | null = element;
  while (node && node !== root) {
    const parent: HTMLElement | null = node.parentElement;
    if (parent instanceof HTMLDetailsElement && !parent.open && !(node.tagName === 'SUMMARY')) return false;
    node = parent;
  }
  return true;
}
