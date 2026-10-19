// 統合テストの入口。VS Code をダウンロードして（.vscode-test/ にとっておく）、拡張を読み込ませて suite/index.ts を動かす。
// ワークスペースは test/integration/workspace を一時ディレクトリに写したもの（テストがファイルを書き、設定も変えるため）。
// 写した先の cornix.path はテスト用の偽のサーバー（test/fake-server/cornix）の絶対パスにする。
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { runTests } from '@vscode/test-electron';

async function main(): Promise<void> {
  const extensionDevelopmentPath = path.resolve(__dirname, '../../..');
  const extensionTestsPath = path.resolve(__dirname, 'suite/index.js');
  // VS Code の IPC のソケットのパスは 103 文字までなので、user-data-dir は短い一時ディレクトリに置く。
  // macOS の /var は /private/var へのリンクで、見張りの知らせのパスと食い違わないように実際のパスにする
  const temp = fs.mkdtempSync(path.join(fs.realpathSync(os.tmpdir()), 'cornix-vt-'));
  const userDataDir = path.join(temp, 'user-data');
  const workspace = path.join(temp, 'workspace');
  fs.cpSync(path.resolve(extensionDevelopmentPath, 'test/integration/workspace'), workspace, { recursive: true });
  fs.writeFileSync(
    path.join(workspace, '.vscode/settings.json'),
    `${JSON.stringify({ 'cornix.path': path.resolve(extensionDevelopmentPath, 'test/fake-server/cornix') }, null, 2)}\n`,
  );
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
    fs.rmSync(temp, { recursive: true, force: true });
  }
}

main().catch((error: unknown) => {
  console.error(error);
  process.exit(1);
});
