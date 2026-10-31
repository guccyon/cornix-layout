// 項目の追加・削除・名前の変更（protocol.md の 12.5）と preset の展開（13.1）、レイヤーの追加・削除（14.9）で、確認のダイアログに出す文と、失敗の知らせの文を作る。
// v0.5: 番号の操作とショートカットの追加（15.3。未保存の変更に積む）の編集の名前と、未使用にするときの確認の文も。vscode に依存しない。
import { ErrorCodes, type Address, type ItemEdit, type ItemFileEdits, type PlanItemEditResult } from '../protocol';

const KIND_NAMES: Record<string, string> = {
  macro: 'マクロ',
  tapDance: 'タップダンス',
  combo: 'コンボ',
  shortcut: 'ショートカット',
  layer: 'レイヤー',
};

// 約束（protocol.ts の Hand）の left / right の見出し。キーボードごとの値ではないので KeyboardSpec に寄せない
const HAND_NAMES: Record<string, string> = { left: '左手', right: '右手' };

/** Webview から来たものが ItemEdit の形か（中身の正しさはサーバーが確かめる） */
export function isItemEdit(value: unknown): value is ItemEdit {
  if (value === null || typeof value !== 'object') return false;
  const edit = value as Record<string, unknown>;
  const kind = typeof edit.kind === 'string' && edit.kind in KIND_NAMES;
  switch (edit.op) {
    case 'create':
      if (edit.kind === 'layer') return typeof edit.name === 'string' && (edit.index === undefined || Number.isInteger(edit.index));
      return kind && edit.index === undefined && typeof edit.name === 'string' && (edit.kind === 'shortcut' ? typeof edit.value === 'string' : edit.preset === undefined || typeof edit.preset === 'string');
    case 'delete':
      return kind && typeof edit.name === 'string' && layerFileOk(edit);
    case 'rename':
      return kind && typeof edit.name === 'string' && typeof edit.to === 'string' && layerFileOk(edit);
    case 'renamePosition':
      return (edit.hand === 'left' || edit.hand === 'right') && Number.isInteger(edit.row) && Number.isInteger(edit.col) && typeof edit.to === 'string';
    case 'expandPreset':
      return edit.kind === 'macro' && typeof edit.name === 'string';
    // v0.5（protocol.md の 15.3）: 番号の操作はファイルで指す
    case 'use':
    case 'unuse':
      return indexedKind(edit.kind) && typeof edit.file === 'string';
    case 'setIndex':
      return indexedKind(edit.kind) && typeof edit.file === 'string' && Number.isInteger(edit.index);
    case 'reorder':
      return (
        indexedKind(edit.kind) &&
        Array.isArray(edit.files) &&
        edit.files.length > 0 &&
        edit.files.every((file) => typeof file === 'string') &&
        (edit.indexes === undefined || (Array.isArray(edit.indexes) && edit.indexes.length === edit.files.length && edit.indexes.every((i) => Number.isInteger(i))))
      );
    default:
      return false;
  }
}

function indexedKind(kind: unknown): boolean {
  return kind === 'layer' || kind === 'macro' || kind === 'tapDance' || kind === 'combo';
}

/** 削除・名前の変更の file はレイヤーだけ（文字列）。index は書けない */
function layerFileOk(edit: Record<string, unknown>): boolean {
  return edit.index === undefined && (edit.file === undefined || (edit.kind === 'layer' && typeof edit.file === 'string'));
}

/**
 * 操作の見出し（「マクロ Bracket Pair を削除します。」）。
 * name は番号の操作（ファイルで指す）の項目の名前（分かれば「レイヤー iPad Base を使い始めます。」、なければファイル）
 */
export function itemEditTitle(edit: ItemEdit, name?: string): string {
  switch (edit.op) {
    case 'create':
      if (edit.kind === 'layer' && edit.index !== undefined) return `レイヤー ${edit.index} ${edit.name} を追加します。`;
      return `${KIND_NAMES[edit.kind]} ${edit.name} を追加します。`;
    case 'delete':
      if (edit.kind === 'layer' && edit.file !== undefined) return `レイヤー ${edit.name}（${edit.file}）を削除します。`;
      return `${KIND_NAMES[edit.kind]} ${edit.name} を削除します。`;
    case 'rename':
      return `${KIND_NAMES[edit.kind]} ${edit.name} の名前を ${edit.to} に変えます。`;
    case 'renamePosition':
      return `${HAND_NAMES[edit.hand]} row ${edit.row} col ${edit.col} の位置の名前を ${edit.to} に変えます。`;
    case 'expandPreset':
      return `${KIND_NAMES[edit.kind]} ${edit.name} の preset を手順に展開します。`;
    case 'use':
      return `${indexedItem(edit, name)}を使い始めます。`;
    case 'unuse':
      return `${indexedItem(edit, name)}を未使用にします。`;
    case 'setIndex':
      return `${indexedItem(edit, name)}の番号を ${edit.index} に変えます。`;
    case 'reorder':
      return `${KIND_NAMES[edit.kind]}を並び替えます。`;
  }
}

/** 番号の操作の項目（「レイヤー iPad Base 」か「レイヤー（layers/ipad.yml）」） */
function indexedItem(edit: { kind: string; file: string }, name: string | undefined): string {
  return name !== undefined ? `${KIND_NAMES[edit.kind]} ${name} ` : `${KIND_NAMES[edit.kind]}（${edit.file}）`;
}

/**
 * 未保存の変更に積む操作（15.3）の、VS Code の編集の名前（元に戻す・やり直しの単位。「レイヤー iPad Base を使い始める」）。
 * name は itemEditTitle と同じ
 */
export function pendingItemEditLabel(edit: ItemEdit, name?: string): string {
  return itemEditTitle(edit, name).replace(/します。$/, 'する').replace(/ます。$/, 'る');
}

/** 確認のダイアログの detail に出す参照の数の上限（それより多ければ「ほか N 件」） */
const REFERENCE_LINES = 20;

/**
 * 未使用にする（15.3 の unuse）ときの確認のダイアログの文。壊れる参照（references）があるときだけ聞く（ほかの未保存の変更に積む操作は聞かない）。
 * message は見出しと壊れる参照の件数、detail は参照の場所（describe で名前にする）
 */
export function describeUnuse(edit: ItemEdit & { op: 'unuse' }, result: PlanItemEditResult, describe: (address: Address) => string, name?: string): { message: string; detail: string } {
  const count = result.references.length;
  const references =
    edit.kind === 'layer'
      ? `このレイヤーを指すレイヤー操作（MO・LT・TG など）が ${count} 件あり、未使用にすると参照している側に警告が出ます。compile ではこのレイヤーのキーはすべて何もしない（KC_NO）になります。`
      : `この項目への参照が ${count} 件あり、未使用にすると参照している側がエラーになります。`;
  const lines = result.references.slice(0, REFERENCE_LINES).map(describe);
  if (count > REFERENCE_LINES) lines.push(`ほか ${count - REFERENCE_LINES} 件`);
  return {
    message: [itemEditTitle(edit, name), references, '未保存の変更に積みます（Ctrl+S で保存します。元に戻すで戻せます）。'].join(''),
    detail: lines.length > 0 ? `壊れる参照:\n${lines.join('\n')}` : '',
  };
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
  if (edit.op === 'delete' && edit.kind === 'layer') {
    // 消したレイヤーは compile で KC_NO（issue #83）。指していたレイヤー操作は警告になるが書き込みは止めない
    references =
      count > 0
        ? `このレイヤーを指すレイヤー操作（MO・LT・TG など）が ${count} 件あり、削除すると参照している側に警告が出ます。compile ではこのレイヤーのキーはすべて何もしない（KC_NO）になります。`
        : 'このレイヤーを指すレイヤー操作はありません。compile ではこのレイヤーのキーはすべて何もしない（KC_NO）になります。';
  } else if (edit.op === 'delete') {
    references = count > 0 ? `この項目への参照が ${count} 件あり、削除すると参照している側がエラーになります。` : 'この項目への参照はありません。';
  } else if (edit.op === 'rename' || edit.op === 'renamePosition') {
    references = count > 0 ? `参照 ${count} 件も書き換えます。` : '';
  } else if (edit.op === 'expandPreset') {
    references = 'preset: の行を同梱の定義の手順（sequence:）に置き換えます（キーボードに書く値は変わりません）。';
  }
  const lines = result.files.map(fileLine);
  return {
    message: [itemEditTitle(edit), references, 'すぐにファイルに書きます（元に戻すで戻せます）。'].filter(Boolean).join(''),
    detail: lines.join('\n'),
  };
}

/** profile/planItemEdit の失敗の知らせ（-32061 の verify と -32602 は理由を出す。name は itemEditTitle と同じ） */
export function itemEditErrorMessage(edit: ItemEdit, error: unknown, name?: string): string {
  const { code, data, message } = (error ?? {}) as { code?: unknown; data?: unknown; message?: unknown };
  const what = itemEditTitle(edit, name).replace(/します。$/, 'できませんでした').replace(/ます。$/, 'られませんでした');
  const reason = typeof message === 'string' ? message : error instanceof Error ? error.message : String(error);
  if (code === ErrorCodes.EditNotLocal) {
    const why = (data as { reason?: string } | undefined)?.reason;
    if (why === 'verify') {
      const when = edit.op === 'expandPreset' ? '展開の前と後' : '名前を変える前と後';
      return `${what}（${when}で compile の結果が変わるため）。${reason}`;
    }
    return `${what}（値の部分だけでは書き換えられないため）。${reason}`;
  }
  if (code === ErrorCodes.InvalidParams) return `${what}（${reason}）`;
  if (code === ErrorCodes.VersionConflict) return `${what}。設定ファイルが外で変わっています。外の変更を取り込んでから、もう一度試してください。`;
  return `${what}（${reason}）`;
}
