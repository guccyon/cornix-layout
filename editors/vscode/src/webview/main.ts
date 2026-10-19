// 編集画面（Webview）の入口。ホストとのメッセージ（webviewMessages.ts）をつなぎ、App に描かせる。
import type { HostMessage, WebviewMessage } from '../webviewMessages';
import { App, type ViewState } from './app';
import { MessageHostClient } from './hostClient';
import { mediaUrl, setMediaBase } from './icons';

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
const app = new App(document.getElementById('app') as HTMLElement, {
  host,
  onRendered: (message) => vscode.postMessage(message),
  state: { get: () => vscode.getState(), set: (state) => vscode.setState(state) },
});

window.addEventListener('message', (event: MessageEvent<HostMessage>) => {
  if (host.handle(event.data)) return;
  app.receive(event.data);
});

void styled.then(() => vscode.postMessage({ type: 'ready' }));
