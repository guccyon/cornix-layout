// 項目の追加・削除・名前の変更（protocol.md の 12.5）で、確認のダイアログに出す文と、失敗の知らせの文を作る。vscode に依存しない。
import { ErrorCodes, type ItemEdit, type ItemFileEdits, type PlanItemEditResult } from '../protocol';

const KIND_NAMES: Record<string, string> = {
  macro: 'マクロ',
  tapDance: 'タップダンス',
  combo: 'コンボ',
  shortcut: 'ショートカット',
  layer: 'レイヤー',
};

const HAND_NAMES: Record<string, string> = { left: '左手', right: '右手' };

/** Webview から来たものが ItemEdit の形か（中身の正しさはサーバーが確かめる） */
export function isItemEdit(value: unknown): value is ItemEdit {
  if (value === null || typeof value !== 'object') return false;
  const edit = value as Record<string, unknown>;
  const kind = typeof edit.kind === 'string' && edit.kind in KIND_NAMES;
  switch (edit.op) {
    case 'create':
      return kind && edit.kind !== 'layer' && typeof edit.name === 'string' && (edit.kind === 'shortcut' ? typeof edit.value === 'string' : edit.preset === undefined || typeof edit.preset === 'string');
    case 'delete':
      return kind && edit.kind !== 'layer' && typeof edit.name === 'string';
    case 'rename':
      return kind && typeof edit.name === 'string' && typeof edit.to === 'string';
    case 'renamePosition':
      return (edit.hand === 'left' || edit.hand === 'right') && Number.isInteger(edit.row) && Number.isInteger(edit.col) && typeof edit.to === 'string';
    default:
      return false;
  }
}

/** 操作の見出し（「マクロ Bracket Pair を削除します。」） */
export function itemEditTitle(edit: ItemEdit): string {
  switch (edit.op) {
    case 'create':
      return `${KIND_NAMES[edit.kind]} ${edit.name} を追加します。`;
    case 'delete':
      return `${KIND_NAMES[edit.kind]} ${edit.name} を削除します。`;
    case 'rename':
      return `${KIND_NAMES[edit.kind]} ${edit.name} の名前を ${edit.to} に変えます。`;
    case 'renamePosition':
      return `${HAND_NAMES[edit.hand]} row ${edit.row} col ${edit.col} の位置の名前を ${edit.to} に変えます。`;
  }
}

/** ファイル 1 つの操作の 1 行（「作成: macros/05_new.yml」） */
function fileLine(file: ItemFileEdits): string {
  if (file.delete) return `削除: ${file.file}`;
  if (file.create) return `作成: ${file.file}`;
  if (file.renameTo) return `名前の変更: ${file.file} → ${file.renameTo}${file.edits.length > 0 ? '（書き換えあり）' : ''}`;
  return `書き換え: ${file.file}`;
}

/**
 * 確認のダイアログの文。message は見出しと参照の件数、detail はファイルごとの操作。
 * 参照の件数は、削除なら壊れる参照、名前の変更なら書き換える参照
 */
export function describeItemEdit(edit: ItemEdit, result: PlanItemEditResult): { message: string; detail: string } {
  const count = result.references.length;
  let references = '';
  if (edit.op === 'delete') {
    references = count > 0 ? `この項目への参照が ${count} 件あり、削除すると参照している側がエラーになります。` : 'この項目への参照はありません。';
  } else if (edit.op === 'rename' || edit.op === 'renamePosition') {
    references = count > 0 ? `参照 ${count} 件も書き換えます。` : '';
  }
  const lines = result.files.map(fileLine);
  return {
    message: [itemEditTitle(edit), references, 'すぐにファイルに書きます（元に戻すで戻せます）。'].filter(Boolean).join(''),
    detail: lines.join('\n'),
  };
}

/** profile/planItemEdit の失敗の知らせ（-32061 の verify と -32602 は理由を出す） */
export function itemEditErrorMessage(edit: ItemEdit, error: unknown): string {
  const { code, data, message } = (error ?? {}) as { code?: unknown; data?: unknown; message?: unknown };
  const what = itemEditTitle(edit).replace(/します。$/, 'できませんでした').replace(/ます。$/, 'られませんでした');
  const reason = typeof message === 'string' ? message : error instanceof Error ? error.message : String(error);
  if (code === ErrorCodes.EditNotLocal) {
    const why = (data as { reason?: string } | undefined)?.reason;
    if (why === 'verify') return `${what}（名前を変える前と後で compile の結果が変わるため）。${reason}`;
    return `${what}（値の部分だけでは書き換えられないため）。${reason}`;
  }
  if (code === ErrorCodes.InvalidParams) return `${what}（${reason}）`;
  if (code === ErrorCodes.VersionConflict) return `${what}。設定ファイルが外で変わっています。外の変更を取り込んでから、もう一度試してください。`;
  return `${what}（${reason}）`;
}
