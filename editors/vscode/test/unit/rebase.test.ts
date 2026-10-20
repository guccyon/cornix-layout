// 外での変更の当て直し（protocol.md の 7.3）と、保存・知らせの道具
import { describe, expect, it } from 'vitest';
import type { Address, AnyChange, Change, ProfileSnapshot } from '../../src/protocol';
import { addressKey, snapshotValueAt } from '../../src/editor/pendingChanges';
import {
  backupBefore,
  changedFiles,
  describeAddress,
  describeChange,
  describeValue,
  fileVersionOf,
  inverseOf,
  rebaseChanges,
  structureErrors,
} from '../../src/editor/rebase';
import * as data from '../fake-server/fixtures';
import { fixtureSnapshot } from './webview/fakeHost';

const base = 'layers/0_base.yml';
const key = (hand: string, group: string, symbol: string): Address => ({ file: base, path: ['mapping', hand, group, symbol] });
const tab = key('left_hand', 'row0', 'tab');
const q = key('left_hand', 'row0', 'Q');
const w = key('left_hand', 'row0', 'W');
const tapping: Address = { file: 'settings/qmk_settings.yaml', path: ['keyboard', 'tapping_term'] };

/** snapshot の 1 つのキーの値を変えたもの */
function withKey(snapshot: ProfileSnapshot, address: Address, text: string | null): ProfileSnapshot {
  return {
    ...snapshot,
    layers: snapshot.layers.map((layer) => ({
      ...layer,
      keys: layer.keys.map((k) =>
        addressKey(k.address) === addressKey(address)
          ? { ...k, value: text === null ? null : { text, canonical: text, code: 0, kind: 'basic' as const, display: { label: text } } }
          : k,
      ),
    })),
  };
}

describe('rebaseChanges', () => {
  const before = fixtureSnapshot();
  const valueBefore = (address: Address) => {
    const k = before.layers.flatMap((l) => l.keys).find((x) => addressKey(x.address) === addressKey(address));
    if (k) return k.value?.text ?? null;
    return before.settings.find((s) => addressKey(s.address) === addressKey(address))?.value;
  };

  it('外で変わっていない場所の変更はそのまま当て直す', () => {
    const after = withKey(before, w, 'Escape'); // 外では W だけが変わった
    const changes: Change[] = [{ address: q, value: 'Tab' }, { address: tapping, value: 200 }];
    expect(rebaseChanges(changes, valueBefore, after)).toEqual({ kept: changes, conflicts: [], lost: [] });
  });

  it('同じ場所が外でも変わっていれば選ばせ、外の値と同じになった変更は捨てる', () => {
    const after = withKey(withKey(before, q, 'Escape'), tab, 'Tab');
    const changes: Change[] = [
      { address: q, value: 'Tab' },
      { address: tab, value: 'Tab' },
    ];
    expect(rebaseChanges(changes, valueBefore, after)).toEqual({
      kept: [],
      conflicts: [{ change: { address: q, value: 'Tab' }, external: 'Escape' }],
      lost: [],
    });
  });

  it('新しい snapshot に同じ Address がなければ当て直せない', () => {
    const after = { ...before, layers: before.layers.filter((l) => l.file !== base) };
    const changes: Change[] = [{ address: q, value: 'Tab' }];
    expect(rebaseChanges(changes, valueBefore, after).lost).toEqual(changes);
  });

  it('外の変更の前の値が分からなければ選ばせる', () => {
    const changes: Change[] = [{ address: q, value: 'Tab' }];
    expect(rebaseChanges(changes, () => undefined, before).conflicts).toEqual([{ change: changes[0], external: 'Q' }]);
  });
});

describe('rebaseChanges の v0.2 の Change（12.3）', () => {
  const macro = 'macros/00_bracket_pair.yml';
  const before = fixtureSnapshot({ files: { [base]: 'sha256:base', [macro]: 'sha256:m1' }, macros: data.MACROS });
  const valueBefore = (address: Address, field: 'key' | 'note' = 'key') => snapshotValueAt(before, address, field);
  const insert: AnyChange = { op: 'insert', address: { file: macro, path: ['sequence'] }, index: 1, value: { action: 'delay', duration: 10 } };
  const description: AnyChange = { address: { file: macro, path: ['description'] }, value: '新しい説明' };

  it('並びを指す Change のあるファイルが外で変わったら、そのファイルの Change はまとめて当て直せない', () => {
    const after = { ...before, files: { ...before.files, [macro]: 'sha256:m2' } };
    const changes: AnyChange[] = [{ address: q, value: 'Tab' }, insert, description];
    expect(rebaseChanges(changes, valueBefore, after, before.files)).toEqual({ kept: [{ address: q, value: 'Tab' }], conflicts: [], lost: [insert, description] });
  });

  it('並びのあるファイルが変わっていなければ、並びの変更はそのまま当て直す', () => {
    const after = { ...before, files: { ...before.files, [base]: 'sha256:base2' } };
    expect(rebaseChanges([insert, description], valueBefore, after, before.files)).toEqual({ kept: [insert, description], conflicts: [], lost: [] });
  });

  it('注記と remove も同じ場所が外でも変わっていれば選ばせる', () => {
    const thumb: Address = { file: base, path: ['mapping', 'left_hand', 'thumb_keys', 'left'] };
    const after = fixtureSnapshot({
      layers: before.layers.map((layer) => ({
        ...layer,
        keys: layer.keys.map((k) => (addressKey(k.address) === addressKey(thumb) && k.value ? { ...k, value: { ...k.value, note: '外の注記' } } : k)),
      })),
    });
    const note: AnyChange = { address: thumb, value: '画面の注記', field: 'note' };
    const removeQ: AnyChange = { op: 'remove', address: q };
    expect(rebaseChanges([note, removeQ], valueBefore, after)).toEqual({ kept: [removeQ], conflicts: [{ change: note, external: '外の注記' }], lost: [] });
  });

  it('逆の Change と見せ方', () => {
    expect(inverseOf(insert)).toEqual({ op: 'remove', address: { file: macro, path: ['sequence', 1] } });
    expect(inverseOf({ op: 'move', address: { file: macro, path: ['sequence'] }, from: 0, to: 2 })).toEqual({ op: 'move', address: { file: macro, path: ['sequence'] }, from: 2, to: 0 });
    expect(inverseOf(description)).toBeUndefined();
    expect(describeChange(insert)).toBe('2 番目に足す: delay 10ms');
    expect(describeChange({ op: 'remove', address: q, field: 'note' })).toBe('注記を消す');
    expect(describeAddress(before, { file: macro, path: ['sequence', 0, 'keys', 1] })).toBe('マクロ Bracket Pair の手順 1 のキー 2');
  });
});

describe('backupBefore と changedFiles', () => {
  const snapshot = fixtureSnapshot({ files: { [base]: 'sha256:new', 'settings/qmk_settings.yaml': 'sha256:same' } });
  const backupFiles = { [base]: 'sha256:old', 'settings/qmk_settings.yaml': 'sha256:same' };

  it('版が同じファイルは今の値、違うファイルはバックアップに書いた値（なければ分からない）', () => {
    const before = backupBefore(snapshot, backupFiles, { [addressKey(q)]: 'Q' });
    expect(before(tapping)).toBe(180);
    expect(before(q)).toBe('Q');
    expect(before(w)).toBeUndefined();
  });

  it('変更が触るファイルのうち版が違うもの', () => {
    const changes: Change[] = [{ address: q, value: 'Tab' }, { address: tapping, value: 200 }];
    expect(changedFiles(changes, backupFiles, snapshot.files)).toEqual([base]);
  });
});

describe('知らせに使う道具', () => {
  it('構造検証の error だけを拾う', () => {
    const errors = structureErrors([
      { severity: 'error', source: 'semantic', message: 'a' },
      { severity: 'warning', source: 'structure', message: 'b' },
      { severity: 'error', source: 'structure', message: 'c' },
    ]);
    expect(errors.map((d) => d.message)).toEqual(['c']);
  });

  it('場所と値の名前', () => {
    const snapshot = fixtureSnapshot();
    expect(describeAddress(snapshot, tab)).toBe('レイヤー 0 Base の左手 row0 tab');
    expect(describeAddress(snapshot, { file: base, path: ['mapping', 'encoders', 'right', 'push'] })).toBe('レイヤー 0 Base の右のエンコーダの押し込み');
    expect(describeAddress(snapshot, tapping)).toBe('QMK 設定 keyboard.tapping_term');
    expect(describeAddress(snapshot, { file: 'layers/9_x.yml', path: ['mapping'] })).toBe('layers/9_x.yml の mapping');
    expect([describeValue(null), describeValue(true), describeValue(180), describeValue('Tab')]).toEqual(['（割り当てなし）', 'オン', '180', 'Tab']);
  });

  it('ファイルの版は sha256 の小文字の 16 進', () => {
    expect(fileVersionOf(new TextEncoder().encode(''))).toBe('sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
  });
});
