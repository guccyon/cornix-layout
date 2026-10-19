// DOM を作る小さな道具（素の TypeScript で書くため）。
type Attrs = Record<string, string | number | boolean | undefined | null>;
type Child = Node | string | null | undefined | false;

/**
 * h('div', { class: 'x' }, child, ...)。属性が false / null / undefined なら付けない。true なら値なしで付ける。
 * style は CSSOM（element.style.cssText）で付ける（CSP の style-src に 'unsafe-inline' が要らないように）
 */
export function h<K extends keyof HTMLElementTagNameMap>(tag: K, attrs: Attrs = {}, ...children: Child[]): HTMLElementTagNameMap[K] {
  const element = document.createElement(tag);
  for (const [name, value] of Object.entries(attrs)) {
    if (value === false || value === null || value === undefined) continue;
    if (name === 'style') {
      element.style.cssText = String(value);
      continue;
    }
    element.setAttribute(name, value === true ? '' : String(value));
  }
  append(element, children);
  return element;
}

export function append(parent: Node, children: Child[]): void {
  for (const child of children) {
    if (child === null || child === undefined || child === false) continue;
    parent.appendChild(typeof child === 'string' ? document.createTextNode(child) : child);
  }
}

/** replaceChildren に渡せる並び（false / null / undefined を除く） */
export function nodes(...children: Child[]): (Node | string)[] {
  return children.filter((child): child is Node | string => child !== null && child !== undefined && child !== false);
}
