import { describe, expect, it } from 'vitest';
import { profileItems } from '../../src/profiles/profileItems';

describe('profileItems', () => {
  it('既定を先頭にし、印を付ける', () => {
    const items = profileItems({
      profiles: [
        { dir: 'config', name: 'config' },
        { dir: 'profiles/default', name: 'default' },
      ],
      default: 'profiles/default',
    });
    expect(items.map((item) => [item.dir, item.description])).toEqual([
      ['profiles/default', '既定'],
      ['config', ''],
    ]);
  });

  it('名前が重なるときだけ dir を添える', () => {
    const items = profileItems({
      profiles: [
        { dir: 'profiles/work', name: 'work' },
        { dir: '/Users/me/work', name: 'work' },
        { dir: 'profiles/ipad', name: 'ipad' },
      ],
      default: null,
    });
    expect(items.map((item) => item.description)).toEqual(['profiles/work', '/Users/me/work', '']);
  });
});
