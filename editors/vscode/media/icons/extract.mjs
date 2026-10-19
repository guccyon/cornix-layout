// data/shortcut_icons.yaml のアイコン ID に要る SVG だけを npm のパッケージから取り出し、
// media/icons/ と src/webview/icons/manifest.ts（ID → ファイル・色）を作り直す。
//
// 使い方（取り出した素材はコミットする。ビルドやテストでは動かさない）:
//   mkdir -p /tmp/cornix-icons && cd /tmp/cornix-icons
//   npm pack simple-icons@16.35.0 material-icon-theme@5.39.0
//   mkdir si mit && tar xzf simple-icons-16.35.0.tgz -C si && tar xzf material-icon-theme-5.39.0.tgz -C mit
//   node <editors/vscode>/media/icons/extract.mjs /tmp/cornix-icons/si/package /tmp/cornix-icons/mit/package
//
// - simple-icons:<slug>        → media/icons/simple-icons/<slug>.svg（単色。画面では CSS の mask で色を付ける）
//                                 色は simple-icons の data の hex。黒・白に近い色はテーマの前景色にする（色を null にする）
// - material-icon-theme:<name> → media/icons/material-icon-theme/<name>.svg（多色のまま img で出す）
// - badge:<文字>                → 画像を作らない（画面が CSS で描く。色は src/webview/icons/badges.ts）
import * as fs from 'node:fs';
import * as path from 'node:path';
import { fileURLToPath } from 'node:url';

const [simpleIconsDir, materialDir] = process.argv.slice(2);
if (!simpleIconsDir || !materialDir) {
  console.error('使い方: node extract.mjs <simple-icons のパッケージ> <material-icon-theme のパッケージ>');
  process.exit(1);
}

const here = path.dirname(fileURLToPath(import.meta.url));
const extensionRoot = path.resolve(here, '../..');
const repoRoot = path.resolve(extensionRoot, '../..');

// data/shortcut_icons.yaml の `  アプリ名: ID` の行だけを読む（YAML のライブラリを足さないため素朴に読む）
const ids = new Set();
for (const line of fs.readFileSync(path.join(repoRoot, 'data/shortcut_icons.yaml'), 'utf-8').split('\n')) {
  const match = /^\s+[^#:]+:\s*((?:simple-icons|material-icon-theme|badge):[^\s#]+)/.exec(line);
  if (match) ids.add(match[1]);
}

const siVersion = JSON.parse(fs.readFileSync(path.join(simpleIconsDir, 'package.json'), 'utf-8')).version;
const mitVersion = JSON.parse(fs.readFileSync(path.join(materialDir, 'package.json'), 'utf-8')).version;
const siData = JSON.parse(fs.readFileSync(path.join(simpleIconsDir, 'data/simple-icons.json'), 'utf-8'));
const siIcons = Array.isArray(siData) ? siData : siData.icons;

/** 黒や白に近い色はテーマによって見えなくなるので、テーマの前景色にする */
function themedColor(hex) {
  const [r, g, b] = [0, 2, 4].map((i) => parseInt(hex.slice(i, i + 2), 16) / 255);
  const lin = (c) => (c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4);
  const luminance = 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b);
  return luminance < 0.05 || luminance > 0.85 ? null : `#${hex}`;
}

const outDir = path.join(here);
fs.rmSync(path.join(outDir, 'simple-icons'), { recursive: true, force: true });
fs.rmSync(path.join(outDir, 'material-icon-theme'), { recursive: true, force: true });
fs.mkdirSync(path.join(outDir, 'simple-icons'), { recursive: true });
fs.mkdirSync(path.join(outDir, 'material-icon-theme'), { recursive: true });

const manifest = {};
for (const id of [...ids].sort()) {
  const [kind, name] = id.split(':');
  if (kind === 'simple-icons') {
    const info = siIcons.find((icon) => icon.slug === name);
    if (!info) throw new Error(`simple-icons ${siVersion} に ${name} がありません`);
    fs.copyFileSync(path.join(simpleIconsDir, 'icons', `${name}.svg`), path.join(outDir, 'simple-icons', `${name}.svg`));
    manifest[id] = { kind: 'mask', file: `icons/simple-icons/${name}.svg`, color: themedColor(info.hex), title: info.title };
  } else if (kind === 'material-icon-theme') {
    const file = path.join(materialDir, 'icons', `${name}.svg`);
    if (!fs.existsSync(file)) throw new Error(`material-icon-theme ${mitVersion} に ${name}.svg がありません`);
    fs.copyFileSync(file, path.join(outDir, 'material-icon-theme', `${name}.svg`));
    manifest[id] = { kind: 'image', file: `icons/material-icon-theme/${name}.svg`, color: null, title: name };
  }
}

fs.copyFileSync(path.join(simpleIconsDir, 'LICENSE.md'), path.join(outDir, 'simple-icons', 'LICENSE.md'));
fs.copyFileSync(path.join(simpleIconsDir, 'DISCLAIMER.md'), path.join(outDir, 'simple-icons', 'DISCLAIMER.md'));
fs.copyFileSync(path.join(materialDir, 'LICENSE'), path.join(outDir, 'material-icon-theme', 'LICENSE'));

const source = `// media/icons/extract.mjs が作るファイル。手で直さない（素材の版: simple-icons ${siVersion}、material-icon-theme ${mitVersion}）。
// アイコン ID → media/ からの相対パスと色。mask は単色の SVG を CSS の mask で塗る（color が null ならテーマの前景色）、image は多色のまま出す
export type IconAsset = { kind: 'mask' | 'image'; file: string; color: string | null; title: string };

export const ICON_ASSETS: Record<string, IconAsset> = ${JSON.stringify(manifest, null, 2)};
`;
fs.writeFileSync(path.join(extensionRoot, 'src/webview/icons/manifest.ts'), source);
console.log(`${Object.keys(manifest).length} 個を取り出しました（バッジ ${[...ids].filter((id) => id.startsWith('badge:')).length} 個は CSS）`);
