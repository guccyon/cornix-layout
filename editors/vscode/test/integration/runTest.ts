// 統合テストの入口。VS Code をダウンロードして（.vscode-test/ にとっておく）、拡張を読み込ませて suite/index.ts を動かす。
// ワークスペースは test/integration/workspace を一時ディレクトリに写したもの（テストがファイルを書き、設定も変えるため）。
// 写した先の cornix.path はテスト用の偽のサーバー（test/fake-server/cornix）の絶対パスにする。
// CORNIX_INTEGRATION_SERVER=ruby（npm run test:integration:ruby）なら、このリポジトリの bin/cornix serve とつなぎ、suite/realServer.ts を動かす。
// そのときのワークスペースは spec/fixtures/authors_config を profiles/default に写したもの（PATH に Ruby が要る。gem は使わない）。
import { execFileSync } from 'node:child_process';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { runTests } from '@vscode/test-electron';

async function main(): Promise<void> {
  const extensionDevelopmentPath = path.resolve(__dirname, '../../..');
  const ruby = process.env.CORNIX_INTEGRATION_SERVER === 'ruby';
  const extensionTestsPath = path.resolve(__dirname, ruby ? 'suite/realServer.js' : 'suite/index.js');
  const repository = path.resolve(extensionDevelopmentPath, '../..');
  // VS Code の IPC のソケットのパスは 103 文字までなので、user-data-dir は短い一時ディレクトリに置く。
  // macOS の /var は /private/var へのリンクで、見張りの知らせのパスと食い違わないように実際のパスにする
  const temp = fs.mkdtempSync(path.join(fs.realpathSync(os.tmpdir()), 'cornix-vt-'));
  const userDataDir = path.join(temp, 'user-data');
  const workspace = path.join(temp, 'workspace');
  if (ruby) {
    fs.cpSync(path.join(repository, 'spec/fixtures/authors_config'), path.join(workspace, 'profiles/default'), { recursive: true });
    fs.writeFileSync(path.join(workspace, '.cornix.yml'), 'profile: default\n');
    fs.mkdirSync(path.join(workspace, '.vscode'));
  } else {
    fs.cpSync(path.resolve(extensionDevelopmentPath, 'test/integration/workspace'), workspace, { recursive: true });
  }
  const cornix = ruby ? rubyWrapper(temp, path.join(repository, 'bin/cornix')) : path.resolve(extensionDevelopmentPath, 'test/fake-server/cornix');
  fs.writeFileSync(path.join(workspace, '.vscode/settings.json'), `${JSON.stringify({ 'cornix.path': cornix }, null, 2)}\n`);
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

/**
 * テストを動かした環境の Ruby で bin/cornix を動かすスクリプトを作る。
 * VS Code は起動するとログインシェルから環境を読み直すので、PATH の並びが変わって bin/cornix の #!/usr/bin/env ruby が
 * 別の Ruby（macOS の /usr/bin/ruby 2.6 など）を選ぶことがある
 */
function rubyWrapper(dir: string, cornix: string): string {
  const ruby = (process.env.PATH ?? '')
    .split(path.delimiter)
    .map((entry) => path.join(entry, 'ruby'))
    .find((candidate) => fs.existsSync(candidate));
  if (!ruby) throw new Error('PATH に ruby がありません');
  // 古い Ruby だと bin/cornix が Data.define で分かりにくく落ちるので、先に止める
  const version = execFileSync(ruby, ['-e', 'print RUBY_VERSION'], { encoding: 'utf-8' });
  const [major = 0, minor = 0] = version.split('.').map(Number);
  if (major < 3 || (major === 3 && minor < 2)) throw new Error(`PATH の ruby（${ruby}、${version}）が古いです。Ruby 3.2 以上を PATH の先に置いてください`);
  const wrapper = path.join(dir, 'cornix');
  fs.writeFileSync(wrapper, `#!/bin/sh\nexec ${shellQuote(ruby)} ${shellQuote(cornix)} "$@"\n`, { mode: 0o755 });
  return wrapper;
}

/** sh の単一引用符で包む（中の ' は '\'' にする） */
function shellQuote(value: string): string {
  return `'${value.replaceAll("'", "'\\''")}'`;
}

main().catch((error: unknown) => {
  console.error(error);
  process.exit(1);
});
