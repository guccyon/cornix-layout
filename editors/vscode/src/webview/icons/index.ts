// アイコン ID（data/shortcut_icons.yaml の simple-icons:<slug>、material-icon-theme:<name>、badge:<文字>）を要素にする。
// SVG は media/icons/ に同梱（ライセンス表記も同じ場所）。バッジは画像を持たず CSS で描く。
import { badgeColor } from './badges';
import { ICON_ASSETS } from './manifest';

let mediaBase = '';

/** media/ の URL（末尾の / 付き）。Webview では out/webview.js の場所から決める */
export function setMediaBase(url: string): void {
  mediaBase = url.endsWith('/') ? url : `${url}/`;
}

export function mediaUrl(file: string): string {
  return `${mediaBase}${file}`;
}

/** アイコンの要素。知らない ID や空なら null */
export function iconElement(id: string | null | undefined, className = 'icon'): HTMLElement | null {
  if (!id) return null;
  const separator = id.indexOf(':');
  const kind = id.slice(0, separator);
  const name = id.slice(separator + 1);
  if (separator < 0 || !name) return null;

  const element = document.createElement('span');
  element.className = className;
  element.dataset.icon = id;
  element.setAttribute('aria-hidden', 'true');

  if (kind === 'badge') {
    element.classList.add('icon-badge');
    element.textContent = name;
    element.style.setProperty('--badge-color', badgeColor(name));
    if (name.length >= 3) element.classList.add('icon-badge-long');
    return element;
  }
  const asset = ICON_ASSETS[id];
  if (!asset) return null;
  const url = `url("${mediaUrl(asset.file)}")`;
  if (asset.kind === 'mask') {
    element.classList.add('icon-mask');
    element.style.setProperty('--icon-url', url);
    if (asset.color) element.style.setProperty('--icon-color', asset.color);
  } else {
    element.classList.add('icon-image');
    element.style.backgroundImage = url;
  }
  return element;
}
