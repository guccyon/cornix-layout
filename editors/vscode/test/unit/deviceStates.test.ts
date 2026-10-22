// 実機と比べた状態（src/device/deviceStates.ts）と、利用者に見せる文（src/device/deviceTexts.ts）
import { describe, expect, it } from 'vitest';
import type { DeviceBackup, DeviceChange, DevicePlan } from '../../src/deviceProtocol';
import { DeviceStates, filesKey } from '../../src/device/deviceStates';
import {
  backupLabel,
  backupPickItems,
  confirmApplyText,
  deviceFailure,
  isDeviceAction,
  MAX_DETAIL_LINES,
  progressMessage,
  statusText,
  statusTooltip,
} from '../../src/device/deviceTexts';

const change = (n: number): DeviceChange => ({ kind: 'key', layer: 0, device: 'KC_A', profile: `KC_${n}`, text: `レイヤー0 k${n}: KC_A → KC_${n}` });

describe('DeviceStates', () => {
  it('はじめは未確認。比べたら同じ／違う、変わるたびに dir を知らせる', () => {
    const fired: (string | undefined)[] = [];
    const states = new DeviceStates(false, (dir) => fired.push(dir));
    expect(states.get('p')).toEqual({ status: 'unknown', changes: [], busy: null, allowWrites: false });
    states.setBusy('p', 'compare');
    expect(states.busy).toBe(true);
    states.setCompared('p', [change(1), change(2)], 'v1');
    states.setBusy('p', null);
    expect(states.get('p')).toMatchObject({ status: 'different', busy: null });
    expect(states.get('p').changes).toHaveLength(2);
    states.setCompared('p', [], 'v1');
    expect(states.get('p').status).toBe('same');
    expect(fired).toEqual(['p', 'p', 'p', 'p']);
    // 書き込みの許可はすべての画面に送り直す
    states.setAllowWrites(true);
    expect(fired.at(-1)).toBeUndefined();
    expect(states.get('other').allowWrites).toBe(true);
  });

  it('設定ファイルの版が比べたときと違えば「未確認」に戻す（保存・外での変更）。同じなら変えない', () => {
    const states = new DeviceStates(true, () => undefined);
    states.setCompared('p', [change(1)], filesKey({ 'a.yml': 'h1', 'b.yml': 'h2' }));
    states.checkFiles('p', filesKey({ 'b.yml': 'h2', 'a.yml': 'h1' }));
    expect(states.get('p').status).toBe('different');
    states.checkFiles('p', filesKey({ 'a.yml': 'h3', 'b.yml': 'h2' }));
    expect(states.get('p')).toMatchObject({ status: 'unknown', changes: [] });
  });

  it('開いていないときに比べたもの（版が分からない）は、開いたら「未確認」に戻す', () => {
    const states = new DeviceStates(true, () => undefined);
    states.setCompared('p', [], undefined);
    states.checkFiles('p', filesKey({}));
    expect(states.get('p').status).toBe('unknown');
  });

  it('閉じたら忘れる（操作の最中は忘れない）', () => {
    const states = new DeviceStates(true, () => undefined);
    states.setCompared('p', [], 'v');
    states.setBusy('p', 'apply');
    states.forget('p');
    expect(states.get('p').status).toBe('same');
    states.setBusy('p', null);
    states.forget('p');
    expect(states.get('p').status).toBe('unknown');
  });
});

describe('deviceTexts', () => {
  const plan = (changes: DeviceChange[], warnings: string[] = []): DevicePlan => ({
    token: 't',
    empty: changes.length === 0,
    changes,
    warnings,
    keyboard: { name: 'Cornix', uid: 'u' },
  });

  it('状態の印', () => {
    const base = { changes: [] as DeviceChange[], busy: null, allowWrites: false };
    expect(statusText({ ...base, status: 'unknown' })).toBe('実機: 未確認');
    expect(statusText({ ...base, status: 'same' })).toBe('実機: 同じ');
    expect(statusText({ ...base, status: 'different', changes: [change(1), change(2)] })).toBe('実機: 違う 2 件');
    expect(statusText({ ...base, status: 'same', busy: 'apply' })).toBe('実機: 反映しています…');
    expect(statusTooltip({ ...base, status: 'unknown' })).toContain('cornix.device.allowWrites');
  });

  it('進み具合', () => {
    expect(progressMessage({ phase: 'read', done: 120, total: 560 })).toBe('実機を読んでいます（120/560）');
    expect(progressMessage({ phase: 'write', done: 1, total: 3 })).toBe('書き込んでいます（1/3）。書き始めたら取り消せません');
    expect(progressMessage({ phase: 'verify', done: 3, total: 3 })).toBe('読み直して確かめています（3/3）');
  });

  it('確認のダイアログ: 行は上限まで並べ、残りは件数。警告とバックアップの説明を添える', () => {
    const changes = Array.from({ length: MAX_DETAIL_LINES + 3 }, (_, i) => change(i));
    const text = confirmApplyText(plan(changes, ['KC_FOO は RMK が対応していません']), 'default');
    expect(text.message).toBe(`実機（Cornix）に、プロファイル default との違い ${changes.length} 件を書き込みます。`);
    const lines = text.detail.split('\n');
    expect(lines.filter((line) => line.startsWith('レイヤー0'))).toHaveLength(MAX_DETAIL_LINES);
    expect(text.detail).toContain('ほか 3 件');
    expect(text.detail).toContain('注意:\n・KC_FOO は RMK が対応していません');
    expect(text.detail).toContain('バックアップ');
    expect(text.detail).not.toContain('次から聞かない');
  });

  it('バックアップの一覧: 日時と種類、先頭に「最新」', () => {
    const backups: DeviceBackup[] = [
      { name: '20261021-101820-pre-restore', path: 'a', createdAt: '2026-10-21T10:18:20+09:00', kind: 'pre-restore' },
      { name: '20261021-101500-pre-apply', path: 'b', createdAt: '2026-10-21T10:15:00+09:00', kind: 'pre-apply' },
      { name: 'old', path: 'c', createdAt: 'unknown', kind: 'legacy' },
    ];
    expect(backupPickItems(backups).map(({ label, description }) => [label, description])).toEqual([
      ['2026-10-21 10:18:20', '戻す前・最新'],
      ['2026-10-21 10:15:00', '反映の前'],
      ['old', '前の版のバックアップ'],
    ]);
    expect(backupLabel(backups[2]!)).toBe('old');
  });

  it('知らせ済みのエラー（CornixUnavailableError）と取り消しは知らせない。知らないエラーは出力を表示のボタン付き', () => {
    const unavailable = Object.assign(new Error('x'), { name: 'CornixUnavailableError' });
    expect(deviceFailure(unavailable, 'compare', 'p').notice).toBeUndefined();
    expect(deviceFailure({ code: -32800, message: 'c' }, 'compare', 'p').notice).toBeUndefined();
    const other = deviceFailure(new Error('落ちました'), 'apply', 'p');
    expect(other.notice).toMatchObject({ level: 'error', message: '実機の操作（反映）に失敗しました: 落ちました', actions: [{ label: '出力を表示' }] });
    expect(other.resetState).toBe(true);
  });

  it('画面から来た操作の名前を確かめる', () => {
    expect(['compare', 'apply', 'restore'].every(isDeviceAction)).toBe(true);
    expect(isDeviceAction('pull')).toBe(false);
    expect(isDeviceAction(undefined)).toBe(false);
  });
});
