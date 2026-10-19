import { defineConfig } from 'vitest/config';

// 単体テスト（vscode を使わないもの）。VS Code の中で動かすものは test/integration/（@vscode/test-electron）
export default defineConfig({
  test: {
    include: ['test/unit/**/*.test.ts'],
    environment: 'node',
  },
});
