// 偽のサーバーの入口。`cornix serve --root <dir>` と同じ引数で起動する（test/fake-server/cornix から呼ぶ）。
import { runFakeServer } from './server';

const args = process.argv.slice(2);
if (args[0] !== 'serve') {
  process.stderr.write('使い方: cornix serve --root <ワークスペースのフォルダ>（テスト用の偽のサーバー）\n');
  process.exit(1);
}
const rootIndex = args.indexOf('--root');
const root = rootIndex >= 0 ? args[rootIndex + 1] : undefined;
if (!root) {
  process.stderr.write('--root がありません\n');
  process.exit(1);
}

const scenario = process.env.CORNIX_FAKE_SCENARIO === 'invalid' ? 'invalid' : 'default';
process.stderr.write(`[fake-cornix] 起動しました（root: ${root}、scenario: ${scenario}）\n`);
runFakeServer(process.stdin, process.stdout, {
  root,
  scenario,
  exitOn: process.env.CORNIX_FAKE_EXIT_ON || undefined,
  log: (line) => process.stderr.write(`${line}\n`),
  onExit: (code) => process.exit(code),
});
process.stdin.on('end', () => process.exit(0));
