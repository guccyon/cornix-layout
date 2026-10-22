// 本物のサーバー（このリポジトリの bin/cornix serve）とつなぐ統合テスト（npm run test:integration:ruby）。
// ワークスペースは spec/fixtures/authors_config を profiles/default に写したもの（runTest.ts）。
// 偽のサーバーの suite/index.ts が確かめる細かい場合は繰り返さず、開く・描く・候補・検証・保存・外での変更の流れが Ruby の結果で通ることを見る。
import * as assert from 'node:assert/strict';
import * as vscode from 'vscode';
import { snapshotValueAt } from '../../../src/editor/pendingChanges';
import type { CornixExtensionApi } from '../../../src/extension';
import type { Address } from '../../../src/protocol';
import { activateExtension, FakeDevicePrompts, FakePrompts, profileTab, readWorkspaceFile, revertProfile, saveProfile, test, waitFor, writeOutside } from './support';

export { run } from './support';

let api: CornixExtensionApi;
const prompts = new FakePrompts();

const BASE = 'profiles/default/layers/0_base.yml';
const SETTINGS = 'profiles/default/settings/qmk_settings.yaml';
const key = (group: string, symbol: string, hand = 'left_hand', file = 'layers/0_base.yml'): Address => ({ file, path: ['mapping', hand, group, symbol] });
const encoder = (side: 'left' | 'right', action: 'push' | 'ccw' | 'cw'): Address => ({ file: 'layers/0_base.yml', path: ['mapping', 'encoders', side, action] });
const setting = (group: string, name: string): Address => ({ file: 'settings/qmk_settings.yaml', path: [group, name] });
const PALETTE = "Shortcut('VS Code:基本操作:コマンドパレット')";

function document() {
  const opened = api.profileEditor.openDocuments[0];
  assert.ok(opened, 'プロファイルが開いていない');
  return opened;
}

test('本物のサーバーにつながり、一覧と initialize の結果が取れる', async () => {
  api = await activateExtension();
  api.profileEditor.prompts = prompts;
  const list = await api.server.request('profile/list', {});
  assert.deepEqual(list, { profiles: [{ dir: 'profiles/default', name: 'default' }], default: 'profiles/default' });
});

test('プロファイルを開くと、Ruby が読んだ snapshot でキーボード図を描く', async () => {
  const rendered: unknown[] = [];
  const subscription = api.profileEditor.onDidReceiveWebviewMessage(({ message }) => {
    if (message.type === 'rendered') rendered.push(message);
  });
  try {
    // プロファイルが 1 つなので選ばせずに開く
    await vscode.commands.executeCommand('cornix.openProfile');
    await waitFor('タブ', async () => profileTab());
    assert.equal(profileTab()?.label, 'default');
    await waitFor('rendered', async () => rendered.length > 0, 20000);
  } finally {
    subscription.dispose();
  }
  const snapshot = document().snapshot;
  assert.equal(snapshot.status, 'ok');
  assert.deepEqual(snapshot.diagnostics, []);
  assert.equal(snapshot.layers.length, 10);
  assert.equal(snapshot.settings.find((s) => s.name === 'tapping_term')?.value, 180);
  assert.deepEqual(rendered.at(-1), { type: 'rendered', status: 'ok', layer: 0, keys: 48, encoders: 6, styled: true });
});

test('候補と 1 つの値の解釈を Ruby から引ける', async () => {
  const profileId = document().profileId;
  const candidates = await api.server.request('keycode/candidates', { profileId, context: 'layerKey', query: 'コマンドパレット', limit: 10 });
  const palette = candidates.items.find((item) => item.category === 'presetShortcut');
  assert.equal(palette?.insertText, PALETTE);
  assert.equal(palette?.icon, 'material-icon-theme:vscode');
  const macro = await api.server.request('keycode/candidates', { profileId, context: 'layerKey', query: 'Bracket', limit: 5 });
  assert.equal(macro.items[0]?.insertText, "Macro('Bracket Pair')");
  const inspect = await api.server.request('keycode/inspect', { profileId, context: 'layerKey', text: PALETTE });
  assert.equal(inspect.value?.code, 0x0a13);
  assert.equal(inspect.value?.display.label, '⇧⌘P');
  assert.deepEqual(inspect.diagnostics, []);
});

test('値を決めると profile/validate の意味検証の結果が欄に出る（保存はしない）', async () => {
  const doc = document();
  doc.applyChange({ address: key('row0', 'W'), value: 'Macro(20)' });
  const target = JSON.stringify(key('row0', 'W'));
  await waitFor('検証の結果', async () => doc.viewSnapshot.diagnostics.some((d) => d.severity === 'error' && d.source === 'semantic' && JSON.stringify(d.address) === target));
  await revertProfile(doc);
  assert.deepEqual(doc.viewSnapshot.diagnostics, []);
});

test('読めない表記があれば保存しない', async () => {
  const doc = document();
  const before = readWorkspaceFile(BASE);
  doc.applyChange({ address: key('row0', 'W'), value: 'ないキー' });
  await saveProfile(doc);
  assert.match(String(prompts.of('saveFailed').at(-1)?.args[0]), /読めない値があるので保存しませんでした/);
  assert.equal(readWorkspaceFile(BASE), before);
  await revertProfile(doc);
});

test('レイヤーのキー・エンコーダ・QMK 設定を変えて保存すると、その値の部分だけが変わる', async () => {
  const doc = document();
  prompts.calls.length = 0;
  const base = readWorkspaceFile(BASE);
  const settings = readWorkspaceFile(SETTINGS);
  doc.applyChange({ address: key('row0', 'W'), value: 'LGui' });
  doc.applyChange({ address: key('row2', 'comma', 'right_hand'), value: PALETTE });
  doc.applyChange({ address: key('row0', 'R', 'left_hand', 'layers/1_symbols.yml'), value: "Macro('Bracket Pair')" });
  doc.applyChange({ address: encoder('left', 'ccw'), value: 'BrightnessUp' });
  doc.applyChange({ address: setting('keyboard', 'tapping_term'), value: 200 });
  doc.applyChange({ address: setting('keyboard', 'permissive_hold'), value: true });
  await waitFor('dirty', async () => profileTab()?.isDirty === true);
  await saveProfile(doc);
  await waitFor('保存', async () => profileTab()?.isDirty === false);
  assert.deepEqual(prompts.calls, []);
  assert.equal(
    readWorkspaceFile(BASE),
    base
      .replace('      W: W\n', '      W: LGui\n')
      .replace('      comma: ","\n', `      comma: "${PALETTE}"\n`)
      .replace('      ccw: VolumeDown\n', '      ccw: BrightnessUp\n'),
  );
  assert.equal(readWorkspaceFile(SETTINGS), settings.replace('tapping_term: 180', 'tapping_term: 200').replace('permissive_hold: false', 'permissive_hold: true'));
  assert.match(readWorkspaceFile('profiles/default/layers/1_symbols.yml'), /\n {6}R: Macro\('Bracket Pair'\)\n/);
  assert.equal(doc.changes.size, 0);
  // 新しい snapshot は Ruby が読み直したもの（16bit 値と表示の文字が入る）
  const comma = doc.snapshot.layers[0]?.keys.find((k) => JSON.stringify(k.address) === JSON.stringify(key('row2', 'comma', 'right_hand')));
  assert.equal(comma?.value?.code, 0x0a13);
  assert.equal(comma?.value?.origin, 'presetShortcut');
  assert.equal(doc.snapshot.settings.find((s) => s.name === 'permissive_hold')?.value, true);
  // 保存の間に溜めた見張りの知らせを離しても、知っている版と同じなので外での変更にならない
  await new Promise((resolve) => setTimeout(resolve, 800));
  assert.deepEqual(prompts.of('chooseSide'), []);
});

test('外で変わったとき、未保存の変更がなければ黙って描き直す', async () => {
  const doc = document();
  prompts.calls.length = 0;
  await writeOutside(BASE, '      E: E\n', '      E: Enter\n');
  await waitFor('描き直し', async () => snapshotValueAt(doc.snapshot, key('row0', 'E')) === 'Enter');
  assert.deepEqual(prompts.calls, []);
  assert.equal(profileTab()?.isDirty, false);
});

test('外で変わったとき、未保存の変更があれば聞き、画面の変更を残して当て直したものを保存できる', async () => {
  const doc = document();
  prompts.calls.length = 0;
  prompts.side = 'screen';
  doc.applyChange({ address: key('row0', 'T'), value: 'Tab' });
  await waitFor('dirty', async () => profileTab()?.isDirty === true);
  await writeOutside(BASE, '      R: R\n', '      R: Escape\n');
  await waitFor('聞く', async () => prompts.of('chooseSide').length > 0);
  await doc.settled();
  assert.equal(snapshotValueAt(doc.snapshot, key('row0', 'R')), 'Escape');
  assert.deepEqual(doc.changes.list(), [{ address: key('row0', 'T'), value: 'Tab' }]);
  await saveProfile(doc);
  await waitFor('保存', async () => profileTab()?.isDirty === false);
  assert.match(readWorkspaceFile(BASE), /\n {6}R: Escape\n {6}T: Tab\n/);
});

// v0.4: 本物の device のサーバー（cornix serve --device）とつなぐ。CI（Linux）では実機を使えないので、macOS 以外の案内が出ることと、
// 実機を読まない device/backups が答えることを見る。macOS では本物のキーボードを読みにいくので動かさない（書き込みはどちらでもしない）
test('実機と比べると、本物の device のサーバーが macOS 以外では使えないと答え、その案内を出す', async () => {
  if (process.platform === 'darwin') return;
  const devicePrompts = new FakeDevicePrompts();
  api.device.prompts = devicePrompts;
  assert.equal(vscode.workspace.getConfiguration('cornix').get('device.allowWrites'), false);
  assert.equal(await vscode.commands.executeCommand('cornix.device.compare', 'profiles/default'), 'failed');
  assert.equal(devicePrompts.last?.level, 'error');
  assert.match(devicePrompts.last?.message ?? '', /macOS でだけ使えます/);
  assert.equal(api.device.states.get('profiles/default').status, 'unknown');
  assert.deepEqual(await api.device.server.request('device/backups', { dir: 'profiles/default' }), { backups: [] });
  assert.equal(await api.device.server.writesAllowed(), false);
});

test('閉じると一覧から消え、サーバーは止められる', async () => {
  await vscode.commands.executeCommand('workbench.action.closeAllEditors');
  await waitFor('閉じる', async () => api.profileEditor.openDocuments.length === 0);
  await api.server.stop();
  assert.equal(api.server.isRunning, false);
});
