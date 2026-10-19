// 編集画面（Webview）の仮のもの。profile/open の結果を JSON で見せるだけ。
// 本当の画面（キーボード図・レイヤーの編集・キー入力欄）は段 2 の画面の作業（G）がこのディレクトリに作る。
import type { Change, ProfileSnapshot } from '../protocol';
import type { HostMessage, WebviewMessage } from '../webviewMessages';

declare function acquireVsCodeApi(): { postMessage(message: WebviewMessage): void };

const vscode = acquireVsCodeApi();
const app = document.getElementById('app') as HTMLElement;

window.addEventListener('message', (event: MessageEvent<HostMessage>) => {
  const message = event.data;
  if (message.type === 'snapshot') render(message.snapshot, message.changes);
  if (message.type === 'error') app.textContent = message.message;
});

vscode.postMessage({ type: 'ready' });

function render(snapshot: ProfileSnapshot, changes: Change[]): void {
  app.replaceChildren();
  const heading = document.createElement('h2');
  heading.textContent = `${snapshot.name}（${snapshot.dir}）`;
  const status = document.createElement('p');
  status.textContent = `状態: ${snapshot.status} ／ レイヤー ${snapshot.layers.length} ／ 未保存の変更 ${changes.length} 件（仮の画面）`;
  app.append(heading, status);

  // 仮: dirty と元に戻すの仕組みを試すためのボタン。最初のレイヤーの最初のキーを NoKey にする
  const key = snapshot.layers[0]?.keys[0];
  if (key) {
    const button = document.createElement('button');
    button.textContent = `仮の変更: ${key.address.path.join('.')} を NoKey にする`;
    button.addEventListener('click', () => vscode.postMessage({ type: 'change', change: { address: key.address, value: 'NoKey' } }));
    app.append(button);
  }

  const pre = document.createElement('pre');
  pre.style.whiteSpace = 'pre-wrap';
  pre.textContent = JSON.stringify({ changes, snapshot }, null, 2);
  app.append(pre);
}
