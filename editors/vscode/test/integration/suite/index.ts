// VS Code の中で動く統合テスト。偽のサーバーとつなぎ、プロファイルを開いて、dirty・revert・見張り・バックアップ・再起動が VS Code の仕組みに乗ることを確かめる。
import * as assert from 'node:assert/strict';
import * as vscode from 'vscode';
import type { CornixExtensionApi } from '../../../src/extension';

type Test = { name: string; fn: () => Promise<void> };
const tests: Test[] = [];
const test = (name: string, fn: () => Promise<void>) => tests.push({ name, fn });

let api: CornixExtensionApi;

test('拡張が動き、サーバーの一覧が取れる', async () => {
  const extension = vscode.extensions.getExtension<CornixExtensionApi>('guccyon.cornix-vscode');
  assert.ok(extension, '拡張が見つからない');
  api = await extension.activate();
  const list = await api.server.request('profile/list', {});
  assert.equal(list.default, 'profiles/default');
});

test('「Cornix: プロファイルを開く」で既定のプロファイルがカスタムエディタで開く', async () => {
  const command = vscode.commands.executeCommand('cornix.openProfile');
  // 複数あるので QuickPick が出る。既定が初期値なので、そのまま決める
  await waitFor('QuickPick', async () => {
    await vscode.commands.executeCommand('workbench.action.acceptSelectedQuickOpenItem');
    return api.profileEditor.openDocuments.length > 0;
  });
  await command;
  const tab = await waitFor('タブ', async () => profileTab());
  assert.equal(tab.label, 'default');
  const document = api.profileEditor.openDocuments[0];
  assert.equal(document?.snapshot.dir, 'profiles/default');
  assert.equal(document?.snapshot.status, 'ok');
});

test('編集画面がキーボード図とレイヤーの欄を描く（変更のたびに描き直す）', async () => {
  const document = api.profileEditor.openDocuments[0];
  assert.ok(document);
  const messages: string[] = [];
  const rendered: unknown[] = [];
  const requests: unknown[] = [];
  const subscription = api.profileEditor.onDidReceiveWebviewMessage(({ message }) => {
    messages.push(message.type);
    if (message.type === 'rendered') rendered.push(message);
    if (message.type === 'request') requests.push({ method: message.method, params: message.params });
  });
  try {
    // 変更を足すとホストが snapshot を送り直し、画面が描き終えると rendered が返る
    const key = document.snapshot.layers[0]?.keys[2];
    assert.ok(key);
    document.applyChange({ address: key.address, value: 'Escape' });
    await waitFor('rendered', async () => rendered.length > 0).catch((e: Error) => {
      throw new Error(`${e.message} ${JSON.stringify(messages)}`);
    });
    // styled: media/webview.css が読めている（media/ の場所を out/webview.js の場所から決めている）
    assert.deepEqual(rendered.at(-1), { type: 'rendered', status: 'ok', layer: 0, keys: 48, encoders: 6, styled: true });
    // 未保存の値の表示と検証のため、画面がホストに keycode/inspect の中継を頼む（profileId はホストが入れる）
    await waitFor('keycode/inspect の中継', async () =>
      requests.some((r) => JSON.stringify(r) === JSON.stringify({ method: 'keycode/inspect', params: { context: 'layerKey', text: 'Escape' } })),
    );
  } finally {
    subscription.dispose();
  }
  await vscode.commands.executeCommand('workbench.action.files.revert');
  await waitFor('revert', async () => profileTab()?.isDirty === false && document.changes.size === 0);
});

test('変更で dirty になり、戻す（revert）と消える', async () => {
  // 元に戻す（Ctrl+Z）は編集画面の Webview にフォーカスがあるときだけ VS Code が edit.undo を呼ぶので、ここでは試さない
  //（テストの中から Webview にフォーカスを移せない）。undo・redo の中身は PendingChanges の単体テストで確かめる
  const document = api.profileEditor.openDocuments[0];
  assert.ok(document);
  const key = document.snapshot.layers[0]?.keys[0];
  assert.ok(key);
  document.applyChange({ address: key.address, value: 'NoKey' });
  await waitFor('dirty', async () => profileTab()?.isDirty === true);
  assert.equal(document.changes.size, 1);

  await vscode.commands.executeCommand('workbench.action.files.revert');
  await waitFor('revert', async () => profileTab()?.isDirty === false && document.changes.size === 0);
});

test('設定ディレクトリのファイルが変わると workspace/didChangeFiles が届き、hold の間は溜める', async () => {
  const document = api.profileEditor.openDocuments[0];
  assert.ok(document);
  const root = workspaceRoot();
  const received: string[][] = [];
  const subscription = api.server.onNotification('profile/didChange', (params) => received.push(Object.keys(params.files)));
  try {
    const write = (name: string) =>
      vscode.workspace.fs.writeFile(vscode.Uri.joinPath(root, 'profiles/default/layers', name), new TextEncoder().encode('---\nname: Test\n'));
    await write('8_watch.yml');
    await waitFor('profile/didChange', async () => received.some((files) => files.includes('layers/8_watch.yml')));

    const hold = document.watcher.hold();
    await write('9_hold.yml');
    await new Promise((resolve) => setTimeout(resolve, 1000));
    assert.ok(!received.some((files) => files.includes('layers/9_hold.yml')), 'hold の間に送った');
    hold.dispose();
    await waitFor('hold を離したあとの profile/didChange', async () => received.some((files) => files.includes('layers/9_hold.yml'))).catch((e) => { throw new Error(`${e.message} ${JSON.stringify(received)}`); });
  } finally {
    subscription.dispose();
  }
});

test('バックアップから戻すと未保存の変更と、そのときのファイルの版が戻る', async () => {
  const document = api.profileEditor.openDocuments[0];
  assert.ok(document);
  const key = document.snapshot.layers[0]?.keys[1];
  assert.ok(key);
  document.applyChange({ address: key.address, value: 'NoKey' });
  const token = new vscode.CancellationTokenSource().token;
  const destination = vscode.Uri.joinPath(workspaceRoot(), '.backup-test.json');
  const backup = await api.profileEditor.backupCustomDocument(document, { destination });
  const restored = await api.profileEditor.openCustomDocument(document.uri, { backupId: backup.id, untitledDocumentData: undefined }, token);
  try {
    assert.deepEqual(restored.changes.list(), [{ address: key.address, value: 'NoKey' }]);
    assert.deepEqual(restored.backupFiles, document.snapshot.files);
  } finally {
    restored.dispose();
    backup.delete();
  }
  await vscode.commands.executeCommand('workbench.action.files.revert');
  await waitFor('revert', async () => profileTab()?.isDirty === false && document.changes.size === 0);
});

test('開いたままサーバーが落ちても、再起動すると profile/open からやり直す', async () => {
  const document = api.profileEditor.openDocuments[0];
  assert.ok(document);
  // 偽のサーバーは CORNIX_FAKE_EXIT_ON のメソッドが来ると落ちる（環境変数は拡張が起動する子プロセスに引き継がれる）
  process.env.CORNIX_FAKE_EXIT_ON = 'keycode/shortcutTree';
  try {
    // 新しいサーバーの profileId は前と同じ "p1" のこともあるので、snapshot が取り直されたかで見る
    const first = document.snapshot;
    await api.server.restart();
    await waitFor('再起動のあとの開き直し', async () => document.snapshot !== first);
    await assert.rejects(api.server.request('keycode/shortcutTree', {}));
    await waitFor('止まる', async () => !api.server.isRunning);
  } finally {
    delete process.env.CORNIX_FAKE_EXIT_ON;
  }
  const before = document.snapshot;
  let restarted = false;
  const subscription = api.server.onDidRestart(() => (restarted = true));
  await api.server.restart();
  subscription.dispose();
  assert.ok(restarted);
  await waitFor('落ちたあとの開き直し', async () => document.snapshot !== before);
  const tree = await api.server.request('keycode/shortcutTree', {});
  assert.ok(tree.apps.length > 0);
});

test('閉じると一覧から消える', async () => {
  await vscode.commands.executeCommand('workbench.action.closeAllEditors');
  await waitFor('閉じる', async () => api.profileEditor.openDocuments.length === 0);
});

test('cornix が見つからなければ CornixUnavailableError になり、設定を直せばつながる', async () => {
  const config = vscode.workspace.getConfiguration('cornix');
  const original = config.get<string>('path');
  await config.update('path', '/nonexistent/cornix', vscode.ConfigurationTarget.Workspace);
  try {
    await waitFor('止まる', async () => !api.server.isStartingOrRunning);
    await assert.rejects(api.server.request('profile/list', {}), (error: Error) => error.name === 'CornixUnavailableError');
  } finally {
    await config.update('path', original, vscode.ConfigurationTarget.Workspace);
  }
  const list = await api.server.request('profile/list', {});
  assert.equal(list.profiles.length, 2);
});

function workspaceRoot(): vscode.Uri {
  const root = vscode.workspace.workspaceFolders?.[0]?.uri;
  assert.ok(root, 'ワークスペースがない');
  return root;
}

function profileTab(): vscode.Tab | undefined {
  return vscode.window.tabGroups.all
    .flatMap((group) => group.tabs)
    .find((tab) => tab.input instanceof vscode.TabInputCustom && tab.input.viewType === 'cornix.profileEditor');
}

async function waitFor<T>(what: string, check: () => Promise<T | undefined | false>, timeoutMs = 10000): Promise<T> {
  const deadline = Date.now() + timeoutMs;
  for (;;) {
    const value = await check();
    if (value) return value;
    if (Date.now() > deadline) throw new Error(`${what} を待ちきれませんでした`);
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
}

export async function run(): Promise<void> {
  const failures: string[] = [];
  for (const { name, fn } of tests) {
    try {
      await fn();
      console.log(`  ✓ ${name}`);
    } catch (error) {
      console.log(`  ✗ ${name}\n    ${error instanceof Error ? (error.stack ?? error.message) : String(error)}`);
      failures.push(name);
      break; // 後のテストは前のテストの状態に依存する
    }
  }
  if (failures.length > 0) throw new Error(`${failures.length} 件の統合テストが失敗しました`);
}
