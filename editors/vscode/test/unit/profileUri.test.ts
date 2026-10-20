import { describe, expect, it } from 'vitest';
import { PROFILE_SCHEME, profileDirOf, profileUriParts } from '../../src/editor/profileUri';

describe('profileUri', () => {
  it('名前を最後の部分に、dir を query に入れる', () => {
    expect(profileUriParts('profiles/default', 'default')).toEqual({ scheme: PROFILE_SCHEME, path: '/default', query: 'dir=profiles%2Fdefault' });
  });

  it('dir を取り出せる（絶対パスや日本語も）', () => {
    for (const dir of ['profiles/default', '/Users/me/キーボード/config', 'a b&c=d']) {
      expect(profileDirOf(profileUriParts(dir, 'x'))).toBe(dir);
    }
  });

  it('ほかのスキームは扱わない', () => {
    expect(profileDirOf({ scheme: 'file', query: 'dir=config' })).toBeUndefined();
  });

  it('名前の / はタブの題が崩れないように置き換える', () => {
    expect(profileUriParts('x', 'a/b').path).toBe('/a_b');
  });
});
