// 設定ディレクトリのファイルの場所と、テキストで開くこと。
import * as path from 'node:path';
import * as vscode from 'vscode';
import type { Range } from '../protocol';
import { profileFilePath } from './webviewRelay';

/** 設定ディレクトリ（dir はワークスペースからの相対パス、外なら絶対パス。protocol.md の 2.）のファイルシステムのパス */
export function profileDirPath(dir: string): string | undefined {
  if (path.isAbsolute(dir)) return dir;
  const root = vscode.workspace.workspaceFolders?.[0]?.uri;
  return root && path.join(root.fsPath, dir);
}

/** 設定ディレクトリのファイル（設定ディレクトリからの相対パス）の URI。外に出るパスは undefined */
export function profileFileUri(dir: string, file: string): vscode.Uri | undefined {
  const base = profileDirPath(dir);
  const target = base && profileFilePath(base, file);
  return target ? vscode.Uri.file(target) : undefined;
}

/** 設定ディレクトリのファイルをテキストで開く（range があればそこを選ぶ）。設定ディレクトリの外は開かない */
export async function openProfileFile(dir: string, file: string, range?: Range): Promise<void> {
  const uri = profileFileUri(dir, file);
  if (!uri) return;
  const selection = range ? new vscode.Range(range.start.line, range.start.character, range.end.line, range.end.character) : undefined;
  await vscode.window.showTextDocument(uri, { preview: false, ...(selection ? { selection } : {}) });
}
