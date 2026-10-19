import { describe, expect, it } from 'vitest';
import { locateCornix } from '../../src/server/locateCornix';

const root = '/work/cornix-layout';
const only = (...files: string[]) => (file: string) => files.includes(file);

describe('locateCornix', () => {
  it('設定 cornix.path があればそれを使う（相対パスはワークスペースから）', () => {
    const result = locateCornix({ configured: 'tools/cornix', workspaceRoot: root, envPath: '/usr/bin', isExecutable: only('/work/cornix-layout/tools/cornix') });
    expect(result).toEqual({ found: true, location: { command: '/work/cornix-layout/tools/cornix', source: 'setting' } });
  });

  it('設定の場所に実行できるファイルがなければ、ほかを探さずに知らせる', () => {
    const result = locateCornix({ configured: '/opt/cornix', workspaceRoot: root, envPath: '/usr/bin', isExecutable: only('/work/cornix-layout/bin/cornix') });
    expect(result.found).toBe(false);
    if (!result.found) expect(result.message).toContain('/opt/cornix');
  });

  it('設定が名前だけ（パスの区切りがない）なら PATH から探す', () => {
    const result = locateCornix({ configured: 'cornix', workspaceRoot: root, envPath: '/a:/b', isExecutable: only('/work/cornix-layout/cornix', '/b/cornix') });
    expect(result).toEqual({ found: true, location: { command: '/b/cornix', source: 'setting' } });
    const missing = locateCornix({ configured: 'cornix', workspaceRoot: root, envPath: '/a', isExecutable: () => false });
    expect(missing.found).toBe(false);
    if (!missing.found) expect(missing.message).toContain('PATH');
  });

  it('設定が空ならワークスペースの bin/cornix', () => {
    const result = locateCornix({ configured: '  ', workspaceRoot: root, envPath: '/usr/local/bin', isExecutable: only('/work/cornix-layout/bin/cornix', '/usr/local/bin/cornix') });
    expect(result).toEqual({ found: true, location: { command: '/work/cornix-layout/bin/cornix', source: 'workspace' } });
  });

  it('bin/cornix がなければ PATH を前から探す', () => {
    const result = locateCornix({ configured: undefined, workspaceRoot: root, envPath: '/a::/b:/c', isExecutable: only('/b/cornix', '/c/cornix') });
    expect(result).toEqual({ found: true, location: { command: '/b/cornix', source: 'path' } });
  });

  it('どこにもなければ設定を促す文を返す', () => {
    const result = locateCornix({ configured: '', workspaceRoot: root, envPath: '/usr/bin', isExecutable: () => false });
    expect(result.found).toBe(false);
    if (!result.found) expect(result.message).toContain('cornix.path');
  });
});
