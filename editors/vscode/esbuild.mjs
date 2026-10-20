// ビルド: 拡張（Node）、Webview（ブラウザ）、テスト用の偽のサーバーと統合テストを out/ に出す
//   node esbuild.mjs               1 回だけビルド
//   node esbuild.mjs --watch       変わるたびにビルド
//   node esbuild.mjs --production  .vsix 用（縮める・ソースマップなし・テスト用は作らない）
import * as esbuild from 'esbuild';

const watch = process.argv.includes('--watch');
const production = process.argv.includes('--production');

const common = {
  bundle: true,
  sourcemap: !production,
  minify: production,
  logLevel: 'info',
};

/** @type {import('esbuild').BuildOptions[]} */
const builds = [
  {
    ...common,
    entryPoints: ['src/extension.ts'],
    outfile: 'out/extension.js',
    platform: 'node',
    format: 'cjs',
    target: 'node20',
    external: ['vscode'],
  },
  {
    ...common,
    entryPoints: ['src/webview/main.ts'],
    outfile: 'out/webview.js',
    platform: 'browser',
    format: 'iife',
    target: 'es2022',
  },
];

if (!production) {
  builds.push(
    {
      ...common,
      entryPoints: ['test/fake-server/main.ts'],
      outfile: 'out/test/fake-server.js',
      platform: 'node',
      format: 'cjs',
      target: 'node20',
    },
    {
      ...common,
      entryPoints: ['test/integration/runTest.ts', 'test/integration/suite/index.ts', 'test/integration/suite/realServer.ts'],
      outdir: 'out/test/integration',
      outbase: 'test/integration',
      platform: 'node',
      format: 'cjs',
      target: 'node20',
      external: ['vscode', '@vscode/test-electron'],
    },
  );
}

if (watch) {
  const contexts = await Promise.all(builds.map((options) => esbuild.context(options)));
  await Promise.all(contexts.map((context) => context.watch()));
} else {
  await Promise.all(builds.map((options) => esbuild.build(options)));
}
