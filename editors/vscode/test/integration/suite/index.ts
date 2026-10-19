// VS Code の中で動く統合テスト。偽のサーバーとつなぎ、プロファイルを開いて、dirty・revert・見張り・バックアップ・保存・外での変更・再起動が VS Code の仕組みに乗ることを確かめる。
import * as assert from 'node:assert/strict';
import * as fs from 'node:fs';
import * as path from 'node:path';
import * as vscode from 'vscode';
import type { ProfileDocument } from '../../../src/editor/profileDocument';
import { snapshotValueAt } from '../../../src/editor/pendingChanges';
import type { KeepChoice, ProfilePrompts } from '../../../src/editor/prompts';
import type { CornixExtensionApi } from '../../../src/extension';
import type { Address } from '../../../src/protocol';

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

// ---------------------------------------------------------------------------
// 保存と外での変更（protocol.md の 6.2・7.3）。通知のボタンは押せないので、prompts を差し替えて答える
// ---------------------------------------------------------------------------

type PromptLog = { method: string; args: unknown[] };

class FakePrompts implements ProfilePrompts {
  readonly calls: PromptLog[] = [];
  side: KeepChoice | undefined = 'screen';
  /** 画面の値を残す項目の添字（undefined なら閉じた扱い） */
  conflicts: number[] | undefined = [];
  lost: 'discard' | 'external' | undefined = 'discard';

  chooseSide(...args: unknown[]) {
    this.calls.push({ method: 'chooseSide', args });
    return Promise.resolve(this.side);
  }
  resolveConflicts(...args: unknown[]) {
    this.calls.push({ method: 'resolveConflicts', args });
    return Promise.resolve(this.conflicts);
  }
  confirmLost(...args: unknown[]) {
    this.calls.push({ method: 'confirmLost', args });
    return Promise.resolve(this.lost);
  }
  saveFailed(message: string) {
    this.calls.push({ method: 'saveFailed', args: [message] });
  }
  of(method: string): PromptLog[] {
    return this.calls.filter((call) => call.method === method);
  }
}

const BASE = 'profiles/default/layers/0_base.yml';
const baseKey = (group: string, symbol: string, hand = 'left_hand'): Address => ({ file: 'layers/0_base.yml', path: ['mapping', hand, group, symbol] });

function readWorkspaceFile(rel: string): string {
  return fs.readFileSync(path.join(workspaceRoot().fsPath, rel), 'utf-8');
}

/** 外（テキストエディタや Claude）でファイルを書き換える */
async function writeOutside(rel: string, from: string, to: string): Promise<void> {
  const text = readWorkspaceFile(rel);
  assert.ok(text.includes(from), `${rel} に ${from} がない`);
  await vscode.workspace.fs.writeFile(vscode.Uri.joinPath(workspaceRoot(), rel), new TextEncoder().encode(text.replace(from, to)));
}

/** 編集画面を前に出して Ctrl+S と同じコマンドで保存し、保存の流れが終わるのを待つ */
async function saveProfile(document: ProfileDocument): Promise<void> {
  await vscode.commands.executeCommand('vscode.openWith', document.uri, 'cornix.profileEditor');
  await vscode.commands.executeCommand('workbench.action.files.save');
  await document.settled();
}

async function revertProfile(document: ProfileDocument): Promise<void> {
  await vscode.commands.executeCommand('vscode.openWith', document.uri, 'cornix.profileEditor');
  await vscode.commands.executeCommand('workbench.action.files.revert');
  await waitFor('revert', async () => profileTab()?.isDirty === false && document.changes.size === 0);
}

let prompts: FakePrompts;

test('変更して保存（Ctrl+S）すると、ファイルはその値だけが変わり、未保存の変更が空になる。保存のあとの undo はディスクの値に対する変更になる', async () => {
  const document = api.profileEditor.openDocuments[0];
  assert.ok(document);
  prompts = new FakePrompts();
  api.profileEditor.prompts = prompts;
  const before = readWorkspaceFile(BASE);
  const edits: vscode.CustomDocumentEditEvent<ProfileDocument>[] = [];
  const subscription = api.profileEditor.onDidChangeCustomDocument((edit) => edits.push(edit));
  document.applyChange({ address: baseKey('row0', 'Q'), value: 'Escape' });
  subscription.dispose();
  await waitFor('dirty', async () => profileTab()?.isDirty === true);

  await saveProfile(document);
  await waitFor('保存', async () => profileTab()?.isDirty === false);
  assert.equal(readWorkspaceFile(BASE), before.replace('      Q: Q\n', '      Q: Escape\n'));
  assert.equal(document.changes.size, 0);
  assert.equal(snapshotValueAt(document.snapshot, baseKey('row0', 'Q')), 'Escape');
  assert.deepEqual(prompts.calls, []);
  // 保存の間に溜めた見張りの知らせを離しても、知っている版と同じなので外での変更にならない
  await new Promise((resolve) => setTimeout(resolve, 500));
  assert.deepEqual(prompts.of('chooseSide'), []);

  // 保存のあとの undo: ディスクの値（Escape）に対する変更（Q）として残る。redo で戻ると変更から外れる
  const edit = edits.at(-1);
  assert.ok(edit);
  await edit.undo();
  assert.deepEqual(document.changes.list(), [{ address: baseKey('row0', 'Q'), value: 'Q' }]);
  await edit.redo();
  assert.equal(document.changes.size, 0);
});

test('QMK 設定の変更も値だけを書き換えて保存する', async () => {
  const document = api.profileEditor.openDocuments[0];
  assert.ok(document);
  const rel = 'profiles/default/settings/qmk_settings.yaml';
  const before = readWorkspaceFile(rel);
  document.applyChange({ address: { file: 'settings/qmk_settings.yaml', path: ['keyboard', 'tapping_term'] }, value: 200 });
  document.applyChange({ address: { file: 'settings/qmk_settings.yaml', path: ['keyboard', 'permissive_hold'] }, value: true });
  await saveProfile(document);
  await waitFor('保存', async () => profileTab()?.isDirty === false);
  assert.equal(readWorkspaceFile(rel), before.replace('tapping_term: 180', 'tapping_term: 200').replace('permissive_hold: false', 'permissive_hold: true'));
});

test('値を決めると profile/validate で検証し、ほかの項目にかかる問題も画面に送る', async () => {
  const document = api.profileEditor.openDocuments[0];
  assert.ok(document);
  document.applyChange({ address: baseKey('row0', 'W'), value: 'MO(9)' });
  const fn = JSON.stringify(baseKey('row3', 'fn'));
  await waitFor('検証の結果', async () => document.viewSnapshot.diagnostics.some((d) => JSON.stringify(d.address) === fn));
  assert.ok(document.viewSnapshot.diagnostics.some((d) => d.severity === 'error' && JSON.stringify(d.address) === JSON.stringify(baseKey('row0', 'W'))));
  // 保存済みの snapshot の diagnostics は変えない
  assert.ok(!document.snapshot.diagnostics.some((d) => JSON.stringify(d.address) === fn));
  await revertProfile(document);
  assert.ok(!document.viewSnapshot.diagnostics.some((d) => JSON.stringify(d.address) === fn));
});

test('構造の error（読めない表記）があれば保存しない', async () => {
  const document = api.profileEditor.openDocuments[0];
  assert.ok(document);
  const before = readWorkspaceFile(BASE);
  document.applyChange({ address: baseKey('row0', 'W'), value: 'ないキー' });
  await saveProfile(document);
  assert.match(String(prompts.of('saveFailed').at(-1)?.args[0]), /読めない値があるので保存しませんでした/);
  assert.equal(readWorkspaceFile(BASE), before);
  assert.equal(profileTab()?.isDirty, true);
  await revertProfile(document);
});

test('書き換えるファイルがテキストエディタで未保存なら保存を止める', async () => {
  const document = api.profileEditor.openDocuments[0];
  assert.ok(document);
  const uri = vscode.Uri.joinPath(workspaceRoot(), BASE);
  const text = await vscode.workspace.openTextDocument(uri);
  const edit = new vscode.WorkspaceEdit();
  edit.insert(uri, new vscode.Position(0, 0), '# テキストで書きかけ\n');
  assert.ok(await vscode.workspace.applyEdit(edit));
  assert.ok(text.isDirty);
  const before = readWorkspaceFile(BASE);
  document.applyChange({ address: baseKey('row0', 'W'), value: 'Tab' });
  await saveProfile(document);
  assert.match(String(prompts.of('saveFailed').at(-1)?.args[0]), /テキストエディタで未保存です/);
  assert.equal(readWorkspaceFile(BASE), before);
  assert.equal(profileTab()?.isDirty, true);
  // テキストの変更を戻す
  await vscode.window.showTextDocument(text);
  await vscode.commands.executeCommand('workbench.action.files.revert');
  await waitFor('テキストの revert', async () => !text.isDirty);
  await revertProfile(document);
});

test('外で変わったとき、未保存の変更がなければ黙って描き直す', async () => {
  const document = api.profileEditor.openDocuments[0];
  assert.ok(document);
  const asked = prompts.calls.length;
  await writeOutside(BASE, '      W: W\n', '      W: Enter\n');
  await waitFor('描き直し', async () => snapshotValueAt(document.snapshot, baseKey('row0', 'W')) === 'Enter');
  assert.equal(prompts.calls.length, asked);
  assert.equal(profileTab()?.isDirty, false);
});

test('外で変わったとき、未保存の変更があれば聞く。画面の変更を残すと当て直し、同じ場所なら項目ごとに選ばせる', async () => {
  const document = api.profileEditor.openDocuments[0];
  assert.ok(document);
  prompts.calls.length = 0;
  prompts.side = 'screen';
  document.applyChange({ address: baseKey('row0', 'E'), value: 'Tab' });
  await waitFor('dirty', async () => profileTab()?.isDirty === true);
  // 違う場所が外で変わった: 外の値を取り込み、画面の変更は残る
  await writeOutside(BASE, '      R: R\n', '      R: Escape\n');
  await waitFor('当て直し', async () => snapshotValueAt(document.snapshot, baseKey('row0', 'R')) === 'Escape');
  await document.settled();
  assert.deepEqual(prompts.of('chooseSide').map((c) => c.args), [['default', 1, 'external']]);
  assert.deepEqual(document.changes.list(), [{ address: baseKey('row0', 'E'), value: 'Tab' }]);
  assert.equal(profileTab()?.isDirty, true);
  assert.deepEqual(prompts.of('resolveConflicts'), []);

  // 同じ場所が外でも変わった: 項目ごとに選ばせる（ここでは外の値を選ぶ）。残る変更がなければ revert を通して dirty が消える
  prompts.conflicts = [];
  await writeOutside(BASE, '      E: E\n', '      E: Enter\n');
  await waitFor('選ばせる', async () => prompts.of('resolveConflicts').length > 0);
  assert.deepEqual(prompts.of('resolveConflicts')[0]?.args, ['default', [{ label: 'レイヤー 0 Base の左手 row0 E', screen: 'Tab', external: 'Enter' }]]);
  await document.settled();
  await waitFor('外の値', async () => snapshotValueAt(document.snapshot, baseKey('row0', 'E')) === 'Enter' && document.changes.size === 0);
  await waitFor('dirty が消える', async () => profileTab()?.isDirty === false);
});

test('外で変わったとき「外の変更を残す」と、未保存の変更を捨てて revert を通る', async () => {
  const document = api.profileEditor.openDocuments[0];
  assert.ok(document);
  prompts.calls.length = 0;
  prompts.side = 'external';
  document.applyChange({ address: baseKey('row0', 'T'), value: 'Tab' });
  await waitFor('dirty', async () => profileTab()?.isDirty === true);
  await writeOutside(BASE, '      A: A\n', '      A: Escape\n');
  await waitFor('外の変更', async () => snapshotValueAt(document.snapshot, baseKey('row1', 'A')) === 'Escape');
  await document.settled();
  assert.equal(document.changes.size, 0);
  await waitFor('dirty が消える', async () => profileTab()?.isDirty === false);
  assert.equal(snapshotValueAt(document.snapshot, baseKey('row0', 'T')), 'T');
});

test('ホットエグジットから戻したとき、閉じている間に外で変わっていれば 7.3 と同じく聞く', async () => {
  const document = api.profileEditor.openDocuments[0];
  assert.ok(document);
  prompts.calls.length = 0;
  document.applyChange({ address: baseKey('row1', 'S'), value: 'Tab' });
  const destination = vscode.Uri.joinPath(workspaceRoot(), '.backup-external.json');
  const backup = await api.profileEditor.backupCustomDocument(document, { destination });
  await revertProfile(document);
  // 閉じている間に、変えた場所（S）と別の場所（D）が外で変わった
  await writeOutside(BASE, '      S: S\n      D: D\n', '      S: Enter\n      D: Escape\n');
  await waitFor('描き直し', async () => snapshotValueAt(document.snapshot, baseKey('row1', 'D')) === 'Escape');
  prompts.side = 'screen';
  prompts.conflicts = [0]; // 画面の値を残す
  const token = new vscode.CancellationTokenSource().token;
  const restored = await api.profileEditor.openCustomDocument(document.uri, { backupId: backup.id, untitledDocumentData: undefined }, token);
  try {
    await waitFor('聞く', async () => prompts.of('chooseSide').length > 0);
    await restored.settled();
    assert.deepEqual(prompts.of('chooseSide')[0]?.args, ['default', 1, 'backup']);
    assert.deepEqual(prompts.of('resolveConflicts')[0]?.args[1], [{ label: 'レイヤー 0 Base の左手 row1 S', screen: 'Tab', external: 'Enter' }]);
    assert.deepEqual(restored.changes.list(), [{ address: baseKey('row1', 'S'), value: 'Tab' }]);
  } finally {
    restored.dispose();
    backup.delete();
  }
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
