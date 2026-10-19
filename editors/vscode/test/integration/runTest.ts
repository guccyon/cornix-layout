// 統合テストの入口。VS Code をダウンロードして（.vscode-test/ にとっておく）、拡張を読み込ませて suite/index.ts を動かす。
// ワークスペースは test/integration/workspace（cornix.path がテスト用の偽のサーバーを指す）。
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { runTests } from '@vscode/test-electron';

async function main(): Promise<void> {
  const extensionDevelopmentPath = path.resolve(__dirname, '../../..');
  const extensionTestsPath = path.resolve(__dirname, 'suite/index.js');
  const workspace = path.resolve(extensionDevelopmentPath, 'test/integration/workspace');
  // VS Code の IPC のソケットのパスは 103 文字までなので、user-data-dir は短い一時ディレクトリに置く
  const userDataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'cornix-vt-'));
  try {
    await runTests({
      version: process.env.VSCODE_TEST_VERSION ?? 'stable',
      extensionDevelopmentPath,
      extensionTestsPath,
      launchArgs: [
        workspace,
        `--user-data-dir=${userDataDir}`,
        '--disable-extensions',
        '--disable-workspace-trust',
        '--skip-welcome',
        '--skip-release-notes',
      ],
    });
  } finally {
    fs.rmSync(userDataDir, { recursive: true, force: true });
  }
}

main().catch((error: unknown) => {
  console.error(error);
  process.exit(1);
});
