// 未保存の変更を足す 1 つの編集（VS Code の元に戻す・やり直しの単位）を作る。vscode に依存しない（profileDocument.ts が VS Code の編集に載せる）。
// 1 つの編集は Change 1 つ（画面の change / edit）か、v0.5 の番号の操作・ショートカットの追加のように planItemEdit が返した Change の並び（ADR 022）。
import type { Address, AnyChange } from '../protocol';
import { fieldOf, isSequential, type ChangeField, type ChangeValue, type PendingChanges, type SavedValue } from './pendingChanges';
import { inverseOf } from './rebase';

/** 編集が使うもの（ドキュメントの今の状態） */
export type EditContext = {
  readonly changes: PendingChanges;
  /** 並びの外の場所の保存済みの値（今の snapshot から） */
  readonly savedValue: SavedValue;
  /** 外の変更を取り込むたびに増える数（そのあとの undo の扱いを変える） */
  epoch(): number;
  /** 画面に出す値（未保存の変更があればその値、なければ snapshot の値。どちらもなければ null） */
  currentValue(address: Address, field: ChangeField): ChangeValue | null;
};

export type RecordedEdit = { undo(): void; redo(): void };

/** 並びの外の場所を value にする（null は消す、undefined は未保存の変更を外す）。今の snapshot に対する変更になる */
export function assignValue(changes: PendingChanges, savedValue: SavedValue, address: Address, field: ChangeField, value: ChangeValue | null | undefined): void {
  if (value === undefined) changes.discard(address, field);
  else if (value === null) changes.add({ op: 'remove', address, ...(field === 'note' ? { field } : {}) }, savedValue);
  // v0.1 の形（op を省けば set）のまま作る
  else changes.add({ address, value, ...(field === 'note' ? { field } : {}) }, savedValue);
}

type Step = {
  change: AnyChange;
  sequential: boolean;
  field: ChangeField;
  /** 足す前にその場所に未保存の変更があったか */
  hadChange: boolean;
  /** 足す前の画面の値 */
  beforeValue: ChangeValue | null;
  /** 保存したあとに戻したときの逆の Change */
  inverse?: AnyChange;
};

/**
 * Change の並びを未保存の変更に足し、その元に戻す・やり直しを返す（足すものがなければ undefined）。
 * 足す前と後の並び（配列そのもの）を持ち、そのあと並びが変わっていなければ undo・redo はその並びに戻す（1 つの編集の Change は一緒に動く）。
 * 保存や外での変更で並びが変わったあとの undo・redo は、Change ごとに（undo は後ろから）次のようにする:
 * 並びの外の変更なら「前の値（そのときの未保存の値か snapshot の値）」と「新しい値」を今の snapshot に対して当てる（保存のあとに戻すと、ディスクの値に対する変更として残る）。
 * ただし前の値が snapshot の値だった（未保存の変更がなかった）変更を、外の変更を取り込んだあとに戻すときは、
 * 外の変更の前の値ではなく今の snapshot の値に戻す（変更を外す）。利用者が見ていない値で外の変更を黙って戻さないため。
 * 並びを指す変更は、まだ並びにあればそれを外し、保存したあとなら逆の Change（insert は remove、move は戻す move）を足す。
 * 逆の Change を作れないもの（並びの要素の set と remove。前の値が分からない）は戻さない
 */
export function recordEdit(context: EditContext, changes: readonly AnyChange[]): RecordedEdit | undefined {
  if (changes.length === 0) return undefined;
  const { changes: pending, savedValue } = context;
  const epoch = context.epoch();
  const before = pending.current();
  const steps: Step[] = changes.map((change) => {
    const sequential = isSequential(change);
    const field = fieldOf(change);
    const step: Step = {
      change,
      sequential,
      field,
      hadChange: !sequential && pending.pendingValue(change.address, field) !== undefined,
      beforeValue: sequential ? null : context.currentValue(change.address, field),
    };
    pending.add(change, savedValue);
    return step;
  });
  const after = pending.current();

  const undoStep = (step: Step) => {
    const { change, field } = step;
    if (!step.sequential) assignValue(pending, savedValue, change.address, field, !step.hadChange && context.epoch() !== epoch ? undefined : step.beforeValue);
    else if (pending.current().includes(change)) pending.remove(change);
    else if ((step.inverse = inverseOf(change))) pending.add(step.inverse, savedValue);
  };
  const redoStep = (step: Step) => {
    const { change } = step;
    if (!step.sequential) pending.add(change, savedValue);
    else if (step.inverse && pending.current().includes(step.inverse)) pending.remove(step.inverse);
    else if (!pending.current().includes(change)) pending.add(change, savedValue);
    step.inverse = undefined;
  };

  return {
    undo: () => {
      if (pending.current() === after) pending.restore(before);
      else for (const step of [...steps].reverse()) undoStep(step);
    },
    redo: () => {
      if (pending.current() === before) pending.restore(after);
      else for (const step of steps) redoStep(step);
    },
  };
}
