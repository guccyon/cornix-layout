// 編集画面（Webview）の入口。ホストとのメッセージ（webviewMessages.ts）をつなぎ、App に描かせる。
import type { HostMessage, WebviewMessage } from '../webviewMessages';
import { App, type ViewState } from './app';
import { ComboEditor } from './comboEditor';
import { MessageHostClient } from './hostClient';
import { mediaUrl, setMediaBase } from './icons';
import { MacroEditor } from './macroEditor';
import { MetadataView } from './metadataView';
import { SettingsEditor } from './settingsEditor';
import { ShortcutEditor } from './shortcutEditor';
import { TapDanceEditor } from './tapDanceEditor';

declare function acquireVsCodeApi(): {
  postMessage(message: WebviewMessage): void;
  getState(): ViewState | undefined;
  setState(state: ViewState): void;
};

const vscode = acquireVsCodeApi();

// media/ の場所は、この script（out/webview.js）の場所から決める（どちらも拡張の localResourceRoots）
const script = document.currentScript as HTMLScriptElement | null;
if (script?.src) setMediaBase(new URL('../media/', script.src).toString());
const stylesheet = Object.assign(document.createElement('link'), { rel: 'stylesheet', href: mediaUrl('webview.css') });
// 見た目が崩れたまま描かないよう、stylesheet を読み終えて（読めなくても）から snapshot をもらう
const styled = new Promise<void>((resolve) => {
  stylesheet.addEventListener('load', () => resolve());
  stylesheet.addEventListener('error', () => resolve());
});
document.head.append(stylesheet);

const host = new MessageHostClient((message) => vscode.postMessage(message));
// v0.2 の中身の節（サーバーが snapshot に macros などを返さなければ出さない）。
// コンボの「図から選ぶ」は上の図で選ぶ（v0.3。app は下で作るので、押されたときに読む）
const items = [
  new MacroEditor({ host }),
  new TapDanceEditor({ host }),
  new ComboEditor({ host, pickKey: (onPick) => app.pickKey(onPick) }),
  new ShortcutEditor({ host }),
];
const settings = new SettingsEditor({ onCommit: (change) => host.change(change) });
const metadata = new MetadataView();
const app = new App(document.getElementById('app') as HTMLElement, {
  host,
  sections: [...items.map((item) => item.element), settings.element, metadata.element],
  onRendered: (message) => vscode.postMessage(message),
  state: { get: () => vscode.getState(), set: (state) => vscode.setState(state) },
  // v0.4: 「実機との差分」の行から下の節へ
  revealItem: (change) => {
    if (change.kind === 'setting') settings.reveal(change.name ?? '');
    else items.find((item) => item.kind === change.kind)?.reveal({ index: change.index, name: change.name });
  },
});

window.addEventListener('message', (event: MessageEvent<HostMessage>) => {
  if (host.handle(event.data)) return;
  if (event.data.type === 'snapshot') {
    for (const item of items) item.update(event.data.snapshot, event.data.changes, event.data.pending);
    settings.update(event.data.snapshot, event.data.changes);
    metadata.update(event.data.snapshot);
  }
  app.receive(event.data);
});

void styled.then(() => vscode.postMessage({ type: 'ready' }));
