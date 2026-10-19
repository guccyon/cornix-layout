// `cornix` コマンドの場所を決める（spec.md の「作り」）。
// 設定 cornix.path > ワークスペースの bin/cornix > PATH の cornix の順。vscode に依存しない（vitest で確かめる）。
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';

export type CornixLocation = {
  /** 実行するファイルの絶対パス */
  command: string;
  /** どこから見つけたか */
  source: 'setting' | 'workspace' | 'path';
};

export type LocateResult =
  | { found: true; location: CornixLocation }
  | { found: false; message: string };

export type LocateOptions = {
  /** 設定 cornix.path（空文字・未設定なら既定の順で探す） */
  configured: string | undefined;
  /** ワークスペースのフォルダ（絶対パス） */
  workspaceRoot: string;
  /** 環境変数 PATH */
  envPath: string | undefined;
  /** 実行できるファイルか（テストで差し替える） */
  isExecutable?: (file: string) => boolean;
  platform?: NodeJS.Platform;
};

export function locateCornix(options: LocateOptions): LocateResult {
  const isExecutable = options.isExecutable ?? defaultIsExecutable;
  const platform = options.platform ?? process.platform;
  const configured = options.configured?.trim();

  if (configured) {
    const command = resolveConfigured(configured, options.workspaceRoot);
    if (isExecutable(command)) return { found: true, location: { command, source: 'setting' } };
    return {
      found: false,
      message: `設定 cornix.path の「${configured}」が見つからないか、実行できません。`,
    };
  }

  const workspaceBin = path.join(options.workspaceRoot, 'bin', 'cornix');
  if (isExecutable(workspaceBin)) return { found: true, location: { command: workspaceBin, source: 'workspace' } };

  const names = platform === 'win32' ? ['cornix.bat', 'cornix.cmd', 'cornix.exe', 'cornix'] : ['cornix'];
  const separator = platform === 'win32' ? ';' : ':';
  for (const dir of (options.envPath ?? '').split(separator)) {
    if (!dir) continue;
    for (const name of names) {
      const command = path.join(dir, name);
      if (isExecutable(command)) return { found: true, location: { command, source: 'path' } };
    }
  }

  return {
    found: false,
    message: 'cornix が見つかりません。ワークスペースに bin/cornix がなく、PATH にもありません。設定 cornix.path で場所を指定してください。',
  };
}

function resolveConfigured(configured: string, workspaceRoot: string): string {
  if (configured === '~' || configured.startsWith('~/')) return path.join(os.homedir(), configured.slice(1));
  return path.resolve(workspaceRoot, configured);
}

function defaultIsExecutable(file: string): boolean {
  try {
    if (!fs.statSync(file).isFile()) return false;
    fs.accessSync(file, fs.constants.X_OK);
    return true;
  } catch {
    return false;
  }
}
