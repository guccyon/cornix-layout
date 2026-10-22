// 実機の操作の設定と、device のサーバーの起動の引数（protocol.md の 14.1、ADR 019）。vscode に依存しない（単体テストのため）。

/** 設定の名前（package.json の contributes.configuration。既定 false） */
export const ALLOW_WRITES_SETTING = 'cornix.device.allowWrites';

/** cornix serve の --root の後ろに足す引数。--allow-writes は設定が true のときだけ付ける */
export function deviceServerArgs(allowWrites: boolean): string[] {
  return allowWrites ? ['--device', '--allow-writes'] : ['--device'];
}
