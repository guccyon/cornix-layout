// media/icons/extract.mjs が作るファイル。手で直さない（素材の版: simple-icons 16.35.0、material-icon-theme 5.39.0）。
// アイコン ID → media/ からの相対パスと色。mask は単色の SVG を CSS の mask で塗る（color が null ならテーマの前景色）、image は多色のまま出す
export type IconAsset = { kind: 'mask' | 'image'; file: string; color: string | null; title: string };

export const ICON_ASSETS: Record<string, IconAsset> = {
  "material-icon-theme:powerpoint": {
    "kind": "image",
    "file": "icons/material-icon-theme/powerpoint.svg",
    "color": null,
    "title": "powerpoint"
  },
  "material-icon-theme:vscode": {
    "kind": "image",
    "file": "icons/material-icon-theme/vscode.svg",
    "color": null,
    "title": "vscode"
  },
  "material-icon-theme:word": {
    "kind": "image",
    "file": "icons/material-icon-theme/word.svg",
    "color": null,
    "title": "word"
  },
  "simple-icons:androidstudio": {
    "kind": "mask",
    "file": "icons/simple-icons/androidstudio.svg",
    "color": "#3DDC84",
    "title": "Android Studio"
  },
  "simple-icons:blender": {
    "kind": "mask",
    "file": "icons/simple-icons/blender.svg",
    "color": "#E87D0D",
    "title": "Blender"
  },
  "simple-icons:davinciresolve": {
    "kind": "mask",
    "file": "icons/simple-icons/davinciresolve.svg",
    "color": null,
    "title": "DaVinci Resolve"
  },
  "simple-icons:discord": {
    "kind": "mask",
    "file": "icons/simple-icons/discord.svg",
    "color": "#5865F2",
    "title": "Discord"
  },
  "simple-icons:figma": {
    "kind": "mask",
    "file": "icons/simple-icons/figma.svg",
    "color": "#F24E1E",
    "title": "Figma"
  },
  "simple-icons:kicad": {
    "kind": "mask",
    "file": "icons/simple-icons/kicad.svg",
    "color": "#314CB0",
    "title": "KiCad"
  },
  "simple-icons:linux": {
    "kind": "mask",
    "file": "icons/simple-icons/linux.svg",
    "color": "#FCC624",
    "title": "Linux"
  },
  "simple-icons:macos": {
    "kind": "mask",
    "file": "icons/simple-icons/macos.svg",
    "color": null,
    "title": "macOS"
  },
  "simple-icons:note": {
    "kind": "mask",
    "file": "icons/simple-icons/note.svg",
    "color": null,
    "title": "Note"
  },
  "simple-icons:notion": {
    "kind": "mask",
    "file": "icons/simple-icons/notion.svg",
    "color": null,
    "title": "Notion"
  },
  "simple-icons:raycast": {
    "kind": "mask",
    "file": "icons/simple-icons/raycast.svg",
    "color": "#FF6363",
    "title": "Raycast"
  },
  "simple-icons:spotify": {
    "kind": "mask",
    "file": "icons/simple-icons/spotify.svg",
    "color": "#1ED760",
    "title": "Spotify"
  },
  "simple-icons:unity": {
    "kind": "mask",
    "file": "icons/simple-icons/unity.svg",
    "color": null,
    "title": "Unity"
  },
  "simple-icons:xcode": {
    "kind": "mask",
    "file": "icons/simple-icons/xcode.svg",
    "color": "#147EFB",
    "title": "Xcode"
  },
  "simple-icons:zoom": {
    "kind": "mask",
    "file": "icons/simple-icons/zoom.svg",
    "color": "#0B5CFF",
    "title": "Zoom"
  }
};
