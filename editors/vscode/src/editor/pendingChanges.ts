// 未保存の変更（protocol.md の 2. と 12.3 の Change）。当てる順の 1 本の並びとして持つ。
// - 並びの中を指さない set と remove（レイヤーのキー・QMK 設定・description・注記など）は畳む: 同じ場所（Address と field）の前の変更を外して末尾に足し、
//   保存済みの値と同じになったら持たない（v0.1 の「同じ Address は最後の値だけ」）
// - 並びを指す Change（insert / move と、並びの要素を指す set / remove）は畳まずに足した順のまま持つ（並びの中の位置は前の Change を当てたあとで数えるため）
// 元に戻す・やり直しは profileDocument.ts が並びの前後（配列そのもの）で作る。vscode に依存しない（Webview の model.ts も addressKey を使う）。
import type { Address, AnyChange, Change, FileVersion, ProfileSnapshot } from '../protocol';

export type ChangeValue = Change['value'];
/** 書く欄。注記（field: "note"）と割り当て（"key"。省いたとき）は別の値として畳む */
export type ChangeField = 'key' | 'note';

export function addressKey(address: Address): string {
  return JSON.stringify([address.file, ...address.path]);
}

/** 値の場所の鍵（注記は割り当てと別。割り当ての鍵は addressKey と同じなので、v0.1 のバックアップの saved もそのまま読める） */
export function valueKey(address: Address, field: ChangeField = 'key'): string {
  return field === 'note' ? `${addressKey(address)}#note` : addressKey(address);
}

export function fieldOf(change: AnyChange): ChangeField {
  return (change.op === undefined || change.op === 'set' || change.op === 'remove') && change.field === 'note' ? 'note' : 'key';
}

/**
 * 並びを指す Change か（12.3）。insert / move は並びそのものを指し、set / remove は道筋に番号（並びの要素）があれば並びの中を指す。
 * 番号を含む道筋は sequence・keys・trigger_keys の要素だけ（position_map の番号は Change の宛先にならない）
 */
export function isSequential(change: AnyChange): boolean {
  if (change.op === 'insert' || change.op === 'move') return true;
  return change.address.path.some((key) => typeof key === 'number');
}

/** Webview から来たものが AnyChange の形か（形の違うものは足さない。中身の正しさはサーバーが確かめる） */
export function isAnyChange(value: unknown): value is AnyChange {
  if (value === null || typeof value !== 'object') return false;
  const change = value as Record<string, unknown>;
  const address = change.address as Record<string, unknown> | null | undefined;
  if (!address || typeof address !== 'object' || typeof address.file !== 'string' || !Array.isArray(address.path)) return false;
  if (!address.path.every((key) => typeof key === 'string' || typeof key === 'number')) return false;
  const field = change.field;
  if (field !== undefined && field !== 'key' && field !== 'note') return false;
  switch (change.op) {
    case undefined:
    case 'set':
      return ['string', 'number', 'boolean'].includes(typeof change.value);
    case 'remove':
      return true;
    case 'insert':
      return Number.isInteger(change.index) && change.value !== undefined && change.value !== null;
    case 'move':
      return Number.isInteger(change.from) && Number.isInteger(change.to);
    default:
      return false;
  }
}

/** v0.1 の Change（並びの外の割り当て・設定の set）か。snapshot のメッセージの changes に入れるもの */
function isPlainSet(change: AnyChange): change is Change {
  return (change.op === undefined || change.op === 'set') && fieldOf(change) === 'key' && !isSequential(change);
}

/** 並びの外のその場所の、items の中の最後の値（set の値、remove なら null。行ごと消したあとの注記も null）。なければ undefined */
function valueIn(items: readonly AnyChange[], address: Address, field: ChangeField): ChangeValue | null | undefined {
  const key = valueKey(address, field);
  const row = addressKey(address);
  for (let i = items.length - 1; i >= 0; i--) {
    const change = items[i]!;
    if (isSequential(change)) continue;
    if (valueKey(change.address, fieldOf(change)) === key) return change.op === 'remove' ? null : (change as Change).value;
    if (field === 'note' && change.op === 'remove' && fieldOf(change) === 'key' && addressKey(change.address) === row) return null;
  }
  return undefined;
}

/** 保存済みの値を引く（ないなら undefined） */
export type SavedValue = (address: Address, field: ChangeField) => ChangeValue | null | undefined;

export class PendingChanges {
  /** 当てる順の並び。変えるたびに新しい配列にする（元に戻すが「その編集のあと何も変わっていないか」を配列そのもので見分けるため） */
  private items: readonly AnyChange[] = [];

  get size(): number {
    return this.items.length;
  }

  /** 当てる順の全部（profile/validate・profile/planEdits・Webview の pending に送るもの） */
  list(): AnyChange[] {
    return [...this.items];
  }

  /** 今の並びそのもの（元に戻す・やり直しの比べに使う。変えない） */
  current(): readonly AnyChange[] {
    return this.items;
  }

  /** 並びをそのまま置き換える（元に戻す・やり直し・バックアップから戻すとき。畳み直さない） */
  restore(items: readonly AnyChange[]): void {
    this.items = items;
  }

  /** v0.1 の changes（並びの外の割り当て・設定の set。同じ Address は 1 つ） */
  plainSets(): Change[] {
    return this.items.filter(isPlainSet);
  }

  /** 並びの外の、その場所の最後の set（注記は field: "note"） */
  get(address: Address, field: ChangeField = 'key'): Change | undefined {
    const key = valueKey(address, field);
    for (let i = this.items.length - 1; i >= 0; i--) {
      const change = this.items[i]!;
      if (isSequential(change) || valueKey(change.address, fieldOf(change)) !== key) continue;
      return change.op === 'remove' ? undefined : (change as Change);
    }
    return undefined;
  }

  /**
   * 並びの外のその場所に未保存の変更があるか。あれば画面の値（set の値、remove なら null）、なければ undefined。
   * 行ごと消した（field なしの remove）あとの注記は null
   */
  pendingValue(address: Address, field: ChangeField = 'key'): ChangeValue | null | undefined {
    return valueIn(this.items, address, field);
  }

  /**
   * 変更を足す。並びを指すものは末尾に足すだけ。並びの外の set / remove は同じ場所の前の変更を外して末尾に足し、
   * 保存済みの値（saved）と同じになれば持たない。ただし同じ行を消す変更（remove）が前にあれば、消したあとに書く変更として残す。
   * 行ごと消す remove は、同じ行の注記の変更も外す（行がなくなるので）
   */
  add(change: AnyChange, saved: SavedValue): void {
    if (isSequential(change)) {
      this.items = [...this.items, change];
      return;
    }
    const field = fieldOf(change);
    const key = valueKey(change.address, field);
    const row = addressKey(change.address);
    const removing = change.op === 'remove';
    const removesRow = removing && field === 'key';
    const dropped = (c: AnyChange) => {
      if (isSequential(c)) return false;
      // 前に消した行は、そのあとに書く set では残す（消した注記を戻さないため）
      if (c.op === 'remove' && !removing) return false;
      return valueKey(c.address, fieldOf(c)) === key || (removesRow && addressKey(c.address) === row);
    };
    // 置き換える前の変更があれば、その位置に入れる（割り当ての set → 注記の set の順を崩さない。注記だけの set はサーバーが -32602 にする）
    let at = -1;
    const rest: AnyChange[] = [];
    for (const c of this.items) {
      if (!dropped(c)) rest.push(c);
      else if (at < 0 && valueKey(c.address, fieldOf(c)) === key) at = rest.length;
    }
    // この変更の前の値: 残した変更で消していれば null、なければ保存済みの値
    const pending = valueIn(rest, change.address, field);
    const before = pending !== undefined ? pending : saved(change.address, field);
    const removedBefore = pending === null;
    if (removing ? before === null : !removedBefore && (change as Change).value === before) {
      // 書いていないものを消す・保存済みと同じ値にするのは、前の変更を外すだけでよい
      this.items = rest;
      return;
    }
    if (at < 0 && !removing && field === 'key' && (before === null || before === undefined)) {
      // まだ書いていない位置の割り当ては、同じ行の注記の set より前に入れる（行を作ってから注記を書く）
      const note = rest.findIndex((c) => !isSequential(c) && c.op !== 'remove' && fieldOf(c) === 'note' && addressKey(c.address) === row);
      if (note >= 0) at = note;
    }
    this.items = at < 0 ? [...rest, change] : [...rest.slice(0, at), change, ...rest.slice(at)];
  }

  /**
   * 並びの外のその場所を value にする（null は「未保存の変更なし」）。保存済みの値と同じなら外す。
   * 保存・外での変更のあとの当て直しと、v0.1 の値の元に戻すが使う
   */
  assign(address: Address, value: ChangeValue | null, saved: ChangeValue | null | undefined, field: ChangeField = 'key'): void {
    const key = valueKey(address, field);
    this.items = this.items.filter((c) => isSequential(c) || c.op === 'remove' || valueKey(c.address, fieldOf(c)) !== key);
    // 前に行を消していれば、保存済みと同じ値でも消したあとに書く変更として残す
    if (value === null || (value === saved && valueIn(this.items, address, field) !== null)) return;
    const change: Change = field === 'note' ? { address, value, field } : { address, value };
    this.items = [...this.items, change];
  }

  /** 並びの外のその場所（欄ごと）の set と remove を外す（その場所に未保存の変更がない状態にする） */
  discard(address: Address, field: ChangeField = 'key'): void {
    const key = valueKey(address, field);
    this.items = this.items.filter((c) => isSequential(c) || valueKey(c.address, fieldOf(c)) !== key);
  }

  /** その変更（同じもの）を外す */
  remove(change: AnyChange): void {
    this.items = this.items.filter((c) => c !== change);
  }

  /** 並びの外のその場所（Address の全部の欄）の変更を外す */
  delete(address: Address): void {
    const row = addressKey(address);
    this.items = this.items.filter((c) => isSequential(c) || addressKey(c.address) !== row);
  }

  clear(): void {
    this.items = [];
  }

  /** profile/validate・profile/planEdits に渡す baseVersions（変更のあるファイルだけ。版は snapshot の files から） */
  baseVersions(files: Record<string, FileVersion>): Record<string, FileVersion> {
    const result: Record<string, FileVersion> = {};
    for (const change of this.items) result[change.address.file] = files[change.address.file] ?? null;
    return result;
  }
}

/**
 * 並びの外の変更の、snapshot の中のその場所の今の値（キーは表記の文字列、QMK 設定は数値か真偽値、説明などは文字列）。
 * 書いていなければ null、snapshot に Address がなければ undefined。field: "note" は注記（なければ null）。
 * 並びの要素（道筋に番号がある）は前の Change で位置がずれるので、当て直しでは使わない
 */
export function snapshotValueAt(snapshot: ProfileSnapshot, address: Address, field: ChangeField = 'key'): ChangeValue | null | undefined {
  const key = addressKey(address);
  const hit = (slot: { address: Address } | null | undefined) => slot !== null && slot !== undefined && addressKey(slot.address) === key;
  const keyValue = (value: { text: string; note?: string } | null) => (field === 'note' ? (value?.note ?? null) : (value?.text ?? null));
  const plain = <T extends ChangeValue>(value: T | null) => (field === 'note' ? undefined : value);

  for (const layer of snapshot.layers) {
    if (layer.file !== address.file) continue;
    for (const slot of layer.keys) if (hit(slot)) return keyValue(slot.value);
    for (const encoder of [layer.encoders.left, layer.encoders.right]) {
      for (const action of [encoder.push, encoder.ccw, encoder.cw]) if (hit(action)) return keyValue(action.value);
    }
    if (layer.descriptionAddress && hit({ address: layer.descriptionAddress })) return plain(layer.description);
  }
  for (const setting of snapshot.settings) if (hit(setting)) return plain(setting.value);
  for (const macro of snapshot.macros ?? []) {
    if (macro.file !== address.file) continue;
    if (hit({ address: macro.descriptionAddress })) return plain(macro.description);
    if (macro.presetAddress && hit({ address: macro.presetAddress })) return plain(macro.preset);
    for (const step of macro.steps) {
      if (step.action === 'delay' && hit(step.duration)) return plain(step.duration.value);
      if (step.action === 'text' && hit(step.content)) return plain(step.content.value);
      if (step.action !== 'delay' && step.action !== 'text') for (const slot of step.keys) if (hit(slot)) return keyValue(slot.value);
    }
  }
  for (const tapDance of snapshot.tapDances ?? []) {
    if (tapDance.file !== address.file) continue;
    if (hit({ address: tapDance.descriptionAddress })) return plain(tapDance.description);
    if (hit(tapDance.tappingTerm)) return plain(tapDance.tappingTerm.value);
    for (const slot of Object.values(tapDance.actions)) if (hit(slot)) return keyValue(slot.value);
  }
  for (const combo of snapshot.combos ?? []) {
    if (combo.file !== address.file) continue;
    if (hit({ address: combo.descriptionAddress })) return plain(combo.description);
    if (hit(combo.output)) return keyValue(combo.output.value);
    for (const slot of combo.triggers) if (hit(slot)) return keyValue(slot.value);
  }
  for (const shortcut of snapshot.shortcuts ?? []) if (hit(shortcut)) return keyValue(shortcut.value);
  return undefined;
}
