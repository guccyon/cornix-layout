// 編集画面（Webview）の入口。ホストとのメッセージ（webviewMessages.ts）をつなぎ、App に描かせる。
import type { KeyboardSpec } from '../keyboard/spec';
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

type Screen = { app: App; receive(message: HostMessage): void };

/** 画面を組み立てる。KeyboardSpec（ホストが ready のあと最初に送る keyboard。ADR 026）を受けてから作る */
function buildScreen(keyboard: KeyboardSpec): Screen {
  // v0.2 の中身の節（サーバーが snapshot に macros などを返さなければ出さない）。
  // コンボの「図から選ぶ」は上の図で選ぶ（v0.3。app は下で作るので、押されたときに読む）
  const items = [
    new MacroEditor({ host, keyboard }),
    new TapDanceEditor({ host, keyboard }),
    new ComboEditor({ host, keyboard, pickKey: (onPick) => app.pickKey(onPick) }),
    new ShortcutEditor({ host, keyboard }),
  ];
  const settings = new SettingsEditor({ onCommit: (change) => host.change(change) });
  const metadata = new MetadataView();
  const app: App = new App(document.getElementById('app') as HTMLElement, {
    host,
    keyboard,
    sections: [...items.map((item) => item.element), settings.element, metadata.element],
    onRendered: (message) => vscode.postMessage(message),
    state: { get: () => vscode.getState(), set: (state) => vscode.setState(state) },
    // v0.4: 検証の結果の行から下の節（マクロなど・QMK 設定）へ
    revealProblem: (diagnostic) => {
      const file = diagnostic.address?.file ?? diagnostic.file;
      if (!file) return false;
      if (diagnostic.address && settings.revealAddress(diagnostic.address)) return true;
      return items.some((item) => item.revealFile(file));
    },
  });
  return {
    app,
    receive(message) {
      if (message.type === 'snapshot') {
        for (const item of items) item.update(message.snapshot, message.changes, message.pending);
        settings.update(message.snapshot, message.changes);
        metadata.update(message.snapshot);
      }
      app.receive(message);
    },
  };
}

let screen: Screen | undefined;
/** keyboard より前に届いたもの（ホストは keyboard を先に送るので、ふつうは空） */
const early: HostMessage[] = [];

window.addEventListener('message', (event: MessageEvent<HostMessage>) => {
  if (host.handle(event.data)) return;
  if (event.data.type === 'keyboard') {
    // 開き直しなどで 2 回目が来ても作り直さない（spec は今は常に同じ）
    if (screen) return;
    screen = buildScreen(event.data.spec);
    for (const message of early.splice(0)) screen.receive(message);
    return;
  }
  if (screen) screen.receive(event.data);
  else early.push(event.data);
});

void styled.then(() => vscode.postMessage({ type: 'ready' }));
