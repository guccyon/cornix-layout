// VS Code の中で動く統合テスト（最小限）。偽のサーバーとつなぎ、プロファイルを開いて、dirty と元に戻すが VS Code の仕組みに乗ることを確かめる。
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

test('閉じると一覧から消える', async () => {
  await vscode.commands.executeCommand('workbench.action.closeAllEditors');
  await waitFor('閉じる', async () => api.profileEditor.openDocuments.length === 0);
});

test('サーバーが落ちたら止まったことが分かり、再起動でつなぎ直せる', async () => {
  // 偽のサーバーは CORNIX_FAKE_EXIT_ON のメソッドが来ると落ちる（環境変数は拡張が起動する子プロセスに引き継がれる）
  process.env.CORNIX_FAKE_EXIT_ON = 'keycode/shortcutTree';
  try {
    await api.server.restart();
    await assert.rejects(api.server.request('keycode/shortcutTree', {}));
    await waitFor('止まる', async () => !api.server.isRunning);
  } finally {
    delete process.env.CORNIX_FAKE_EXIT_ON;
  }
  let restarted = false;
  const subscription = api.server.onDidRestart(() => (restarted = true));
  await api.server.restart();
  subscription.dispose();
  assert.ok(restarted);
  const tree = await api.server.request('keycode/shortcutTree', {});
  assert.ok(tree.apps.length > 0);
});

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
