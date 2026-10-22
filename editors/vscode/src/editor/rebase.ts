// 外での変更（protocol.md の 7.3 と 12.3）の「画面の変更を残す」の当て直しと、保存・外での変更の知らせに使う小さな道具。vscode に依存しない。
import * as crypto from 'node:crypto';
import type { Address, AnyChange, Change, Diagnostic, FileVersion, MacroStepValue, ProfileSnapshot } from '../protocol';
import { addressKey, fieldOf, isSequential, snapshotValueAt, valueKey, type ChangeField, type ChangeValue } from './pendingChanges';

/** 同じ場所が外でも変わった Change（画面の値と外の値のどちらにするか項目ごとに選ばせる）。並びの外の set / remove だけ */
export type Conflict = { change: AnyChange; external: ChangeValue | null };

export type RebaseResult = {
  /** そのまま当て直すもの（当てる順のまま） */
  kept: AnyChange[];
  /** 同じ場所が外でも変わったもの */
  conflicts: Conflict[];
  /**
   * 当て直せないもの。新しい snapshot に同じ Address がない（ファイル名が変わった・ファイルが消えた）並びの外の変更と、
   * 並びを指す Change のあるファイルが外で変わったときの、そのファイルの Change 全部（並びの位置がずれているかもしれないため。12.3）
   */
  lost: AnyChange[];
};

/** 外の変更の前のその場所の値（分からなければ undefined） */
export type ValueBefore = (address: Address, field: ChangeField) => ChangeValue | null | undefined;

/** 並びを指す Change を、保存したあとに戻すときの逆の Change（insert は remove、move は戻す move。作れないものは undefined） */
export function inverseOf(change: AnyChange): AnyChange | undefined {
  if (change.op === 'insert') return { op: 'remove', address: { file: change.address.file, path: [...change.address.path, change.index] } };
  if (change.op === 'move') return { op: 'move', address: change.address, from: change.to, to: change.from };
  return undefined;
}

/** 並びの外の変更の画面の値（set の値、remove なら null） */
export function screenValue(change: AnyChange): ChangeValue | null {
  return change.op === 'remove' ? null : (change as Change).value;
}

/**
 * 並びを指す Change があって、外の変更の前（beforeFiles）と後（after）で版が違うファイル。
 * そのファイルの Change は全部当て直せないものにする（12.3）
 */
export function unrebaseableFiles(
  changes: readonly AnyChange[],
  beforeFiles: Record<string, FileVersion>,
  after: Record<string, FileVersion>,
): Set<string> {
  const files = new Set(changes.filter(isSequential).map((change) => change.address.file));
  return new Set([...files].filter((file) => (beforeFiles[file] ?? null) !== (after[file] ?? null)));
}

/**
 * Change を新しい snapshot（after）に当て直す（7.3・12.3）。
 * before(address, field) は外の変更の前のその場所の値（キーは表記の文字列、QMK 設定は数値か真偽値、割り当てがなければ null）。分からなければ undefined で、
 * そのときは外でも変わったものとして扱う（選ばせる）。当て直した値が新しい値と同じになった Change は捨てる（どこにも入れない）。
 * beforeFiles（外の変更の前のファイルの版）を渡すと、並びを指す Change のあるファイルが外で変わっていれば、そのファイルの Change を全部 lost にする
 */
export function rebaseChanges(
  changes: readonly AnyChange[],
  before: ValueBefore,
  after: ProfileSnapshot,
  beforeFiles?: Record<string, FileVersion>,
): RebaseResult {
  const result: RebaseResult = { kept: [], conflicts: [], lost: [] };
  const unrebaseable = beforeFiles ? unrebaseableFiles(changes, beforeFiles, after.files) : new Set<string>();
  for (const change of changes) {
    if (unrebaseable.has(change.address.file)) {
      result.lost.push(change);
      continue;
    }
    if (isSequential(change)) {
      // 並びのあるファイルが外で変わっていない（変わっていれば上で外した）ので、位置はずれていない
      result.kept.push(change);
      continue;
    }
    const field = fieldOf(change);
    const next = snapshotValueAt(after, change.address, field);
    if (next === undefined) result.lost.push(change);
    else if (next === screenValue(change)) continue;
    else if (before(change.address, field) === next) result.kept.push(change);
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
): (address: Address, field?: ChangeField) => ChangeValue | null | undefined {
  return (address, field = 'key') => {
    if (address.file in backupFiles && backupFiles[address.file] === snapshot.files[address.file]) return snapshotValueAt(snapshot, address, field);
    const key = valueKey(address, field);
    return savedValues && key in savedValues ? savedValues[key] : undefined;
  };
}

/** Change の並びが触るファイルのうち、版が a と b で違うもの */
export function changedFiles(changes: readonly AnyChange[], a: Record<string, FileVersion>, b: Record<string, FileVersion>): string[] {
  const files = [...new Set(changes.map((change) => change.address.file))];
  return files.filter((file) => (a[file] ?? null) !== (b[file] ?? null));
}

/** 2 つの files（ファイル → 版）が同じか（キーの並びによらず比べる） */
export function sameFiles(a: Record<string, FileVersion>, b: Record<string, FileVersion>): boolean {
  const keys = new Set([...Object.keys(a), ...Object.keys(b)]);
  return [...keys].every((key) => key in a && key in b && a[key] === b[key]);
}

/**
 * 構造検証の error（保存すると読めなくなるので保存を止める。protocol.md の 6.2 の 2）。
 * saved（保存済みの snapshot の diagnostics）を渡すと、そこにすでにある読めない値（同じ場所・同じ文）は除く
 * （ディスクにすでに書いてあり、保存で増えるわけではない。ほかの欄の保存を止めない）
 */
export function structureErrors(diagnostics: readonly Diagnostic[], saved: readonly Diagnostic[] = []): Diagnostic[] {
  const key = (d: Diagnostic) => JSON.stringify([d.address ?? d.file ?? null, d.message]);
  const existing = new Set(saved.filter((d) => d.severity === 'error' && d.source === 'structure').map(key));
  return diagnostics.filter((d) => d.severity === 'error' && d.source === 'structure' && !existing.has(key(d)));
}

/** ディスク上のバイト列の版（protocol.md の 2. の FileVersion） */
export function fileVersionOf(bytes: Uint8Array): string {
  return `sha256:${crypto.createHash('sha256').update(bytes).digest('hex')}`;
}

const HAND_NAMES: Record<string, string> = { left_hand: '左手', right_hand: '右手' };
const ENCODER_OPS: Record<string, string> = { push: '押し込み', ccw: '左回し', cw: '右回し' };
const TAP_DANCE_ACTIONS: Record<string, string> = {
  on_tap: 'タップ',
  on_hold: 'ホールド',
  on_double_tap: 'ダブルタップ',
  on_tap_hold: 'タップしてホールド',
};
const ITEM_KEYS: Record<string, string> = {
  output_key: '出すキー',
  description: '説明',
  tapping_term: 'tapping_term',
  duration: '待ち時間',
  content: '文字',
  preset: 'preset',
};

/** 利用者に見せる場所の名前（「レイヤー 0 Base の左手 row0 tab」「QMK 設定 keyboard.tapping_term」「マクロ Bracket Pair の手順 1 のキー 2」） */
export function describeAddress(snapshot: ProfileSnapshot, address: Address): string {
  const setting = snapshot.settings.find((s) => addressKey(s.address) === addressKey(address));
  if (setting) return `QMK 設定 ${setting.group}.${setting.name}`;
  const layer = snapshot.layers.find((l) => l.file === address.file);
  const [first, hand, group, symbol] = address.path.map(String);
  if (layer && first === 'description' && address.path.length === 1) return `レイヤー ${layer.index} ${layer.name} の説明`;
  if (layer && hand && group && symbol) {
    const place = hand === 'encoders' ? `${group === 'left' ? '左' : '右'}のエンコーダの${ENCODER_OPS[symbol] ?? symbol}` : `${HAND_NAMES[hand] ?? hand} ${group} ${symbol}`;
    return `レイヤー ${layer.index} ${layer.name} の${place}`;
  }
  const items = [
    ...(snapshot.macros ?? []).map((m) => ({ kind: 'マクロ', name: m.name, file: m.file })),
    ...(snapshot.tapDances ?? []).map((t) => ({ kind: 'タップダンス', name: t.name, file: t.file })),
    ...(snapshot.combos ?? []).map((c) => ({ kind: 'コンボ', name: c.name, file: c.file })),
  ];
  const item = items.find((i) => i.file === address.file);
  if (item) return `${item.kind} ${item.name} の${describeItemPath(address.path)}`;
  const shortcut = (snapshot.shortcuts ?? []).find((s) => addressKey(s.address) === addressKey(address));
  if (shortcut) return `ショートカット ${shortcut.name}`;
  return `${address.file} の ${address.path.join('.')}`;
}

/** マクロ・タップダンス・コンボのファイルの中の場所（番号は 1 から数えて見せる） */
function describeItemPath(path: readonly (string | number)[]): string {
  const parts: string[] = [];
  for (let i = 0; i < path.length; i++) {
    const key = path[i];
    const next = path[i + 1];
    const at = typeof next === 'number' ? ` ${next + 1}` : '';
    if (key === 'sequence') parts.push(`手順${at}`);
    else if (key === 'keys') parts.push(`キー${at}`);
    else if (key === 'trigger_keys') parts.push(`同時に押すキー${at}`);
    else if (typeof key === 'string' && key in ITEM_KEYS) parts.push(ITEM_KEYS[key]!);
    else if (typeof key === 'string' && key in TAP_DANCE_ACTIONS) parts.push(TAP_DANCE_ACTIONS[key]!);
    else if (typeof key === 'string' && key !== 'actions') parts.push(key);
    if (typeof next === 'number') i += 1;
  }
  // 番号のあとは空白を入れてつなぐ（「手順 1 のキー 2」）
  return parts.reduce((text, part) => (text ? `${text}${/\d$/.test(text) ? ' ' : ''}の${part}` : part), '') || '中身';
}

/** 利用者に見せる値（割り当てがなければ「割り当てなし」） */
export function describeValue(value: ChangeValue | null): string {
  if (value === null) return '（割り当てなし）';
  if (typeof value === 'boolean') return value ? 'オン' : 'オフ';
  return String(value);
}

/** 利用者に見せる Change の中身（当て直せないものの一覧に使う） */
export function describeChange(change: AnyChange): string {
  switch (change.op) {
    case 'remove':
      return fieldOf(change) === 'note' ? '注記を消す' : '消す';
    case 'insert':
      return `${change.index + 1} 番目に足す: ${typeof change.value === 'string' ? change.value : describeStep(change.value)}`;
    case 'move':
      return `${change.from + 1} 番目を ${change.to + 1} 番目へ動かす`;
    default:
      return fieldOf(change) === 'note' ? `注記: ${String(change.value)}` : describeValue(change.value);
  }
}

function describeStep(step: MacroStepValue): string {
  if (step.action === 'delay') return `delay ${step.duration}ms`;
  if (step.action === 'text') return `text ${step.content}`;
  return `${step.action}: ${step.keys.join(' ')}`;
}
