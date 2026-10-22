// 統合テストの道具（偽のサーバーの suite/index.ts と、本物のサーバーの suite/realServer.ts で使う）。
import * as assert from 'node:assert/strict';
import * as fs from 'node:fs';
import * as path from 'node:path';
import * as vscode from 'vscode';
import type { DeviceBackup } from '../../../src/deviceProtocol';
import type { DevicePrompts } from '../../../src/device/deviceFlow';
import type { BackupPickItem, ConfirmText, Notice } from '../../../src/device/deviceTexts';
import type { ProfileDocument } from '../../../src/editor/profileDocument';
import type { KeepChoice, ProfilePrompts } from '../../../src/editor/prompts';
import type { CornixExtensionApi } from '../../../src/extension';

type Test = { name: string; fn: () => Promise<void> };
const tests: Test[] = [];
export const test = (name: string, fn: () => Promise<void>) => tests.push({ name, fn });

/** 登録した順に動かす。後のテストは前のテストの状態に依存するので、1 つ失敗したらやめる */
export async function run(): Promise<void> {
  const failures: string[] = [];
  for (const { name, fn } of tests) {
    try {
      await fn();
      console.log(`  ✓ ${name}`);
    } catch (error) {
      console.log(`  ✗ ${name}\n    ${error instanceof Error ? (error.stack ?? error.message) : String(error)}`);
      failures.push(name);
      break;
    }
  }
  if (failures.length > 0) throw new Error(`${failures.length} 件の統合テストが失敗しました`);
}

export async function activateExtension(): Promise<CornixExtensionApi> {
  const extension = vscode.extensions.getExtension<CornixExtensionApi>('guccyon.cornix-vscode');
  assert.ok(extension, '拡張が見つからない');
  return extension.activate();
}

type PromptLog = { method: string; args: unknown[] };

/** 保存と外での変更で利用者に聞くこと（protocol.md の 6.2・7.3）。通知のボタンは押せないので、差し替えて答える */
export class FakePrompts implements ProfilePrompts {
  readonly calls: PromptLog[] = [];
  side: KeepChoice | undefined = 'screen';
  /** 画面の値を残す項目の添字（undefined なら閉じた扱い） */
  conflicts: number[] | undefined = [];
  lost: 'discard' | 'external' | undefined = 'discard';
  /** あれば chooseSide はこれが解決するまで答えない（聞いている途中を作る） */
  gate: Promise<void> | undefined;

  async chooseSide(...args: unknown[]) {
    this.calls.push({ method: 'chooseSide', args });
    await this.gate;
    return this.side;
  }
  resolveConflicts(...args: unknown[]) {
    this.calls.push({ method: 'resolveConflicts', args });
    return Promise.resolve(this.conflicts);
  }
  confirmLost(...args: unknown[]) {
    this.calls.push({ method: 'confirmLost', args });
    return Promise.resolve(this.lost);
  }
  saveFailed(message: string, openFile?: () => void) {
    this.calls.push({ method: 'saveFailed', args: [message, openFile !== undefined] });
  }
  /** 項目の操作の前に保存するか（12.5） */
  saveFirst = true;
  /** 項目の操作を書くか */
  itemEdit = true;
  confirmSaveFirst(...args: unknown[]) {
    this.calls.push({ method: 'confirmSaveFirst', args });
    return Promise.resolve(this.saveFirst);
  }
  confirmItemEdit(...args: unknown[]) {
    this.calls.push({ method: 'confirmItemEdit', args });
    return Promise.resolve(this.itemEdit);
  }
  itemEditFailed(message: string, openFile?: () => void) {
    this.calls.push({ method: 'itemEditFailed', args: [message, openFile !== undefined] });
  }
  of(method: string): PromptLog[] {
    return this.calls.filter((call) => call.method === method);
  }
}

/** 実機の操作で聞くこと・知らせること（v0.4。モーダルのダイアログと QuickPick は押せないので、差し替えて答える） */
export class FakeDevicePrompts implements DevicePrompts {
  readonly saves: [string, number][] = [];
  readonly confirms: ConfirmText[] = [];
  readonly picks: BackupPickItem[][] = [];
  readonly notices: Notice[] = [];
  saveFirst = true;
  write = true;
  confirmSaveFirst(profile: string, pending: number) {
    this.saves.push([profile, pending]);
    return Promise.resolve(this.saveFirst);
  }
  confirmWrite(text: ConfirmText) {
    this.confirms.push(text);
    return Promise.resolve(this.write);
  }
  pickBackup(items: BackupPickItem[]): Promise<DeviceBackup | undefined> {
    this.picks.push(items);
    return Promise.resolve(items[0]?.backup);
  }
  notify(notice: Notice) {
    this.notices.push(notice);
  }
  get last(): Notice | undefined {
    return this.notices.at(-1);
  }
}

export function workspaceRoot(): vscode.Uri {
  const root = vscode.workspace.workspaceFolders?.[0]?.uri;
  assert.ok(root, 'ワークスペースがない');
  return root;
}

export function readWorkspaceFile(rel: string): string {
  return fs.readFileSync(path.join(workspaceRoot().fsPath, rel), 'utf-8');
}

/** 外（テキストエディタや Claude）でファイルを書き換える */
export async function writeOutside(rel: string, from: string, to: string): Promise<void> {
  const text = readWorkspaceFile(rel);
  assert.ok(text.includes(from), `${rel} に ${from} がない`);
  await vscode.workspace.fs.writeFile(vscode.Uri.joinPath(workspaceRoot(), rel), new TextEncoder().encode(text.replace(from, to)));
}

/**
 * writeOutside と同じ書き換えを、一時ファイルに書いてから置き換える形で当てる（読む側が途中の中身を読まない）。
 * 一時ファイルはワークスペースの直下（プロファイルの見張りの外）に置く
 */
export async function replaceOutside(rel: string, from: string, to: string): Promise<void> {
  const text = readWorkspaceFile(rel);
  assert.ok(text.includes(from), `${rel} に ${from} がない`);
  const temp = vscode.Uri.joinPath(workspaceRoot(), '.replace-outside.tmp');
  await vscode.workspace.fs.writeFile(temp, new TextEncoder().encode(text.replace(from, to)));
  await vscode.workspace.fs.rename(temp, vscode.Uri.joinPath(workspaceRoot(), rel), { overwrite: true });
}

export function profileTab(): vscode.Tab | undefined {
  return vscode.window.tabGroups.all
    .flatMap((group) => group.tabs)
    .find((tab) => tab.input instanceof vscode.TabInputCustom && tab.input.viewType === 'cornix.profileEditor');
}

/** 編集画面を前に出して Ctrl+S と同じコマンドで保存し、保存の流れが終わるのを待つ */
export async function saveProfile(document: ProfileDocument): Promise<void> {
  await vscode.commands.executeCommand('vscode.openWith', document.uri, 'cornix.profileEditor');
  await vscode.commands.executeCommand('workbench.action.files.save');
  await document.settled();
}

export async function revertProfile(document: ProfileDocument): Promise<void> {
  await vscode.commands.executeCommand('vscode.openWith', document.uri, 'cornix.profileEditor');
  await vscode.commands.executeCommand('workbench.action.files.revert');
  await waitFor('revert', async () => profileTab()?.isDirty === false && document.changes.size === 0);
  await document.settled();
}

export async function waitFor<T>(what: string, check: () => Promise<T | undefined | false>, timeoutMs = 10000): Promise<T> {
  const deadline = Date.now() + timeoutMs;
  for (;;) {
    const value = await check();
    if (value) return value;
    if (Date.now() > deadline) throw new Error(`${what} を待ちきれませんでした`);
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
}
