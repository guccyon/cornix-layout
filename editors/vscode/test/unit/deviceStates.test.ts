// 実機への反映の途中の状態（src/device/deviceStates.ts）と、通知に出す文（src/device/deviceTexts.ts）
import { describe, expect, it } from 'vitest';
import { DeviceErrorCodes, type DeviceChange, type DevicePlan } from '../../src/deviceProtocol';
import { DeviceStates, filesKey } from '../../src/device/deviceStates';
import { deviceFailure, isDeviceAction, validationErrorNotice, writeResultNotice } from '../../src/device/deviceTexts';

const change = (n: number): DeviceChange => ({ kind: 'key', layer: 0, device: 'KC_A', profile: `KC_${n}`, text: `レイヤー0 k${n}: KC_A → KC_${n}` });

const plan = (changes: DeviceChange[], warnings: string[] = []): DevicePlan => ({
  token: 't',
  empty: changes.length === 0,
  changes,
  warnings,
  keyboard: { name: 'Cornix', uid: 'u' },
});

describe('DeviceStates', () => {
  it('はじめは何もない。始める・終えるはすべての画面に、途中の変化はその dir に知らせる', () => {
    const fired: (string | undefined)[] = [];
    const states = new DeviceStates(false, (dir) => fired.push(dir));
    expect(states.get('p')).toEqual({ transfer: null, busyElsewhere: false, allowWrites: false });
    states.start('p', 'v1');
    expect(states.busy).toBe(true);
    expect(states.get('p')).toMatchObject({ transfer: { step: 'reading', progress: null }, busyElsewhere: false });
    expect(states.get('q')).toMatchObject({ transfer: null, busyElsewhere: true });
    states.update('p', { step: 'reading', progress: { done: 1, total: 4 } });
    states.update('p', { step: 'preview', plan: plan([change(1)]), profile: 'p', stale: false });
    states.finish('p');
    expect(states.busy).toBe(false);
    expect(fired).toEqual([undefined, 'p', 'p', undefined]);
    // 始めていなければ update しない
    states.update('p', { step: 'reading', progress: null });
    expect(states.get('p').transfer).toBeNull();
    // 書き込みの許可はすべての画面に送り直す
    states.setAllowWrites(true);
    expect(fired.at(-1)).toBeUndefined();
    expect(states.get('other').allowWrites).toBe(true);
  });

  it('プレビューのあとで設定ファイルの版が変わったら古いにする。キーの順は見ない', () => {
    const states = new DeviceStates(true, () => undefined);
    states.start('p', filesKey({ 'a.yml': 'h1', 'b.yml': 'h2' }));
    states.update('p', { step: 'preview', plan: plan([change(1)]), profile: 'p', stale: false });
    states.checkFiles('p', filesKey({ 'b.yml': 'h2', 'a.yml': 'h1' }));
    expect(states.get('p').transfer).toMatchObject({ stale: false });
    states.checkFiles('p', filesKey({ 'a.yml': 'h3', 'b.yml': 'h2' }));
    expect(states.get('p').transfer).toMatchObject({ step: 'preview', stale: true });
  });

  it('読んでいる間に変わったら、読み終えたプレビューを古いにする（違いがないプレビューはそのまま）', () => {
    const states = new DeviceStates(true, () => undefined);
    states.start('p', 'v1');
    states.checkFiles('p', 'v2');
    states.update('p', { step: 'preview', plan: plan([change(1)]), profile: 'p', stale: false });
    expect(states.get('p').transfer).toMatchObject({ stale: true });

    states.finish('p');
    states.start('p', 'v1');
    states.checkFiles('p', 'v2');
    states.update('p', { step: 'preview', plan: plan([]), profile: 'p', stale: false });
    expect(states.get('p').transfer).toMatchObject({ stale: false });
  });

  it('読み始めたときに開いていなければ（版が分からない）古いかを見ない', () => {
    const states = new DeviceStates(true, () => undefined);
    states.start('p', undefined);
    states.update('p', { step: 'preview', plan: plan([change(1)]), profile: 'p', stale: false });
    states.checkFiles('p', filesKey({}));
    expect(states.get('p').transfer).toMatchObject({ stale: false });
  });
});

describe('deviceTexts', () => {
  it('反映の結果: 書いた件数とバックアップ。違いが残れば警告と「もう一度プレビュー」', () => {
    expect(writeResultNotice({ applied: 3, backup: 'b/layout.vil', remaining: [] }, 'p')).toEqual({
      level: 'info',
      message: '3 件を書き込みました（バックアップ: b/layout.vil）。',
      actions: [],
    });
    expect(writeResultNotice({ applied: 0, backup: null, remaining: [] }, 'p').message).toBe('実機はすでにこのプロファイルと同じでした。');
    expect(writeResultNotice({ applied: 3, backup: null, remaining: [change(1), change(2)] }, 'p')).toMatchObject({
      level: 'warning',
      message: expect.stringContaining('2 件が違ったままです（レイヤー0 k1: KC_A → KC_1 など）'),
      actions: [{ label: 'もう一度プレビュー', command: 'cornix.device.apply', args: ['p'] }],
    });
  });

  it('検証のエラー', () => {
    expect(validationErrorNotice(2)).toMatchObject({ level: 'warning', message: expect.stringContaining('検証のエラーが 2 件'), actions: [{ label: '問題を表示' }] });
  });

  it('知らせ済みのエラー（CornixUnavailableError）と取り消しは知らせない。知らないエラーは出力を表示のボタン付き', () => {
    const unavailable = Object.assign(new Error('x'), { name: 'CornixUnavailableError' });
    expect(deviceFailure(unavailable, 'preview', 'p', 'Cornix')).toBeUndefined();
    expect(deviceFailure({ code: -32800, message: 'c' }, 'preview', 'p', 'Cornix')).toBeUndefined();
    expect(deviceFailure(new Error('落ちました'), 'confirm', 'p', 'Cornix')).toMatchObject({
      level: 'error',
      message: '実機への書き込みに失敗しました: 落ちました',
      actions: [{ label: '出力を表示' }],
    });
    expect(deviceFailure(new Error('落ちました'), 'preview', 'p', 'Cornix')?.message).toBe('実機を読んで比べるのに失敗しました: 落ちました');
  });

  it('キーボードが見つからないときの文は、渡したキーボードの表示名を使う', () => {
    const notConnected = { code: DeviceErrorCodes.DeviceUnavailable, message: 'x', data: { reason: 'notConnected' } };
    expect(deviceFailure(notConnected, 'preview', 'p', 'Cornix')?.message).toBe(
      'キーボードが見つかりません。Cornix を USB か Bluetooth でつないでから、もう一度試してください。',
    );
    expect(deviceFailure(notConnected, 'preview', 'p', 'Other Board')?.message).toBe(
      'キーボードが見つかりません。Other Board を USB か Bluetooth でつないでから、もう一度試してください。',
    );
  });

  it('画面から来た操作の名前を確かめる', () => {
    expect(['preview', 'confirm', 'cancel', 'openSettings'].every(isDeviceAction)).toBe(true);
    expect(['compare', 'apply', 'restore', 'pull', undefined].some(isDeviceAction)).toBe(false);
  });
});
