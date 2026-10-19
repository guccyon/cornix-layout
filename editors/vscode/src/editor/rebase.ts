// 外での変更（protocol.md の 7.3）の「画面の変更を残す」の当て直しと、保存・外での変更の知らせに使う小さな道具。vscode に依存しない。
import * as crypto from 'node:crypto';
import type { Address, Change, Diagnostic, FileVersion, ProfileSnapshot } from '../protocol';
import { addressKey, snapshotValueAt, type ChangeValue } from './pendingChanges';

/** 同じ場所が外でも変わった Change（画面の値と外の値のどちらにするか項目ごとに選ばせる） */
export type Conflict = { change: Change; external: ChangeValue | null };

export type RebaseResult = {
  /** そのまま当て直すもの */
  kept: Change[];
  /** 同じ場所が外でも変わったもの */
  conflicts: Conflict[];
  /** 新しい snapshot に同じ Address がないもの（ファイル名が変わった・ファイルが消えた）。当て直せない */
  lost: Change[];
};

/**
 * Change を新しい snapshot（after）に当て直す（7.3）。
 * before(address) は外の変更の前のその場所の値（キーは表記の文字列、QMK 設定は数値か真偽値、割り当てがなければ null）。分からなければ undefined で、
 * そのときは外でも変わったものとして扱う（選ばせる）。当て直した値が新しい値と同じになった Change は捨てる（どこにも入れない）
 */
export function rebaseChanges(
  changes: readonly Change[],
  before: (address: Address) => ChangeValue | null | undefined,
  after: ProfileSnapshot,
): RebaseResult {
  const result: RebaseResult = { kept: [], conflicts: [], lost: [] };
  for (const change of changes) {
    const next = snapshotValueAt(after, change.address);
    if (next === undefined) result.lost.push(change);
    else if (next === change.value) continue;
    else if (before(change.address) === next) result.kept.push(change);
    else result.conflicts.push({ change, external: next });
  }
  return result;
}

/**
 * ホットエグジットのバックアップから戻したときの「外の変更の前の値」。
 * バックアップを作ったときと今とでファイルの版が同じなら今の値、違えばバックアップに書いた値（なければ分からない）
 */
export function backupBefore(
  snapshot: ProfileSnapshot,
  backupFiles: Record<string, FileVersion>,
  savedValues: Record<string, ChangeValue | null> | undefined,
): (address: Address) => ChangeValue | null | undefined {
  return (address) => {
    if (address.file in backupFiles && backupFiles[address.file] === snapshot.files[address.file]) return snapshotValueAt(snapshot, address);
    const key = addressKey(address);
    return savedValues && key in savedValues ? savedValues[key] : undefined;
  };
}

/** Change の並びが触るファイルのうち、版が a と b で違うもの */
export function changedFiles(changes: readonly Change[], a: Record<string, FileVersion>, b: Record<string, FileVersion>): string[] {
  const files = [...new Set(changes.map((change) => change.address.file))];
  return files.filter((file) => (a[file] ?? null) !== (b[file] ?? null));
}

/** 構造検証の error（保存すると読めなくなるので保存を止める。protocol.md の 6.2 の 2） */
export function structureErrors(diagnostics: readonly Diagnostic[]): Diagnostic[] {
  return diagnostics.filter((d) => d.severity === 'error' && d.source === 'structure');
}

/** ディスク上のバイト列の版（protocol.md の 2. の FileVersion） */
export function fileVersionOf(bytes: Uint8Array): string {
  return `sha256:${crypto.createHash('sha256').update(bytes).digest('hex')}`;
}

const HAND_NAMES: Record<string, string> = { left_hand: '左手', right_hand: '右手' };
const ENCODER_OPS: Record<string, string> = { push: '押し込み', ccw: '左回し', cw: '右回し' };

/** 利用者に見せる場所の名前（「レイヤー 0 Base の左手 row0 tab」「QMK 設定 keyboard.tapping_term」） */
export function describeAddress(snapshot: ProfileSnapshot, address: Address): string {
  const setting = snapshot.settings.find((s) => addressKey(s.address) === addressKey(address));
  if (setting) return `QMK 設定 ${setting.group}.${setting.name}`;
  const layer = snapshot.layers.find((l) => l.file === address.file);
  const [, hand, group, symbol] = address.path.map(String);
  if (layer && hand && group && symbol) {
    const place = hand === 'encoders' ? `${group === 'left' ? '左' : '右'}のエンコーダの${ENCODER_OPS[symbol] ?? symbol}` : `${HAND_NAMES[hand] ?? hand} ${group} ${symbol}`;
    return `レイヤー ${layer.index} ${layer.name} の${place}`;
  }
  return `${address.file} の ${address.path.join('.')}`;
}

/** 利用者に見せる値（割り当てがなければ「割り当てなし」） */
export function describeValue(value: ChangeValue | null): string {
  if (value === null) return '（割り当てなし）';
  if (typeof value === 'boolean') return value ? 'オン' : 'オフ';
  return String(value);
}
