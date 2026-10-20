import * as path from 'node:path';
import { describe, expect, it } from 'vitest';
import { profileFilePath, relayRequest } from '../../src/editor/webviewRelay';

describe('relayRequest', () => {
  it('中継するメソッドだけをサーバーに渡し、profileId はホストのものにする', async () => {
    const calls: unknown[] = [];
    const response = await relayRequest(
      { id: 3, method: 'keycode/inspect', params: { context: 'layerKey', text: 'A', profileId: 'p9' } },
      async (method, params) => {
        calls.push([method, params]);
        return { value: null };
      },
      'p1',
    );
    expect(calls).toEqual([['keycode/inspect', { context: 'layerKey', text: 'A', profileId: 'p1' }]]);
    expect(response).toEqual({ type: 'response', id: 3, method: 'keycode/inspect', result: { value: null } });
  });

  it('keycode/shortcutTree はプロファイルによらないので、Webview の params を使わずに {} で送る', async () => {
    const calls: unknown[] = [];
    const response = await relayRequest(
      { id: 6, method: 'keycode/shortcutTree', params: { profileId: 'p9', extra: 1 } },
      async (method, params) => {
        calls.push([method, params]);
        return { apps: [] };
      },
      'p1',
    );
    expect(calls).toEqual([['keycode/shortcutTree', {}]]);
    expect(response).toEqual({ type: 'response', id: 6, method: 'keycode/shortcutTree', result: { apps: [] } });
  });

  it('ほかのメソッドは中継せずに error で返す', async () => {
    let called = false;
    const response = await relayRequest(
      { id: 4, method: 'profile/planEdits', params: {} },
      async () => {
        called = true;
        return null;
      },
      'p1',
    );
    expect(called).toBe(false);
    expect(response).toEqual({ type: 'response', id: 4, method: 'profile/planEdits', error: '中継しないメソッドです: profile/planEdits' });
  });

  it('サーバーのエラーは error の応答にする', async () => {
    const response = await relayRequest(
      { id: 5, method: 'keycode/candidates', params: { context: 'layerKey', query: '' } },
      async () => {
        throw new Error('プロファイル p1 は開いていません');
      },
      'p1',
    );
    expect(response).toEqual({ type: 'response', id: 5, method: 'keycode/candidates', error: 'プロファイル p1 は開いていません' });
  });
});

describe('profileFilePath', () => {
  const dir = path.resolve('/work/profiles/default');

  it('設定ディレクトリの中のファイルだけを返す', () => {
    expect(profileFilePath(dir, 'layers/0_base.yml')).toBe(path.join(dir, 'layers/0_base.yml'));
    expect(profileFilePath(dir, 'layers/../metadata.yaml')).toBe(path.join(dir, 'metadata.yaml'));
  });

  it('絶対パスと、外に出るものは開かない', () => {
    expect(profileFilePath(dir, '../ipad/metadata.yaml')).toBeUndefined();
    expect(profileFilePath(dir, '../../.cornix.yml')).toBeUndefined();
    expect(profileFilePath(dir, '/etc/hosts')).toBeUndefined();
    expect(profileFilePath(dir, '..')).toBeUndefined();
    expect(profileFilePath(dir, '')).toBeUndefined();
    expect(profileFilePath(dir, '../default-other/x.yml')).toBeUndefined();
  });
});
