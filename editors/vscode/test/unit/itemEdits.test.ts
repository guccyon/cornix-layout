// 項目の操作（protocol.md の 12.5・13.1）の確認のダイアログの文と失敗の知らせ、テキストの波線（12.7）
import { describe, expect, it } from 'vitest';
import { describeItemEdit, isItemEdit, itemEditErrorMessage } from '../../src/editor/itemEdits';
import { textDiagnostics } from '../../src/editor/textDiagnostics';
import { ErrorCodes, type PlanItemEditResult } from '../../src/protocol';

const ref = { file: 'layers/0_base.yml', path: ['mapping', 'left_hand', 'row2', 'B'] };

describe('describeItemEdit', () => {
  it('削除は壊れる参照の件数と、消すファイルを出す', () => {
    const result: PlanItemEditResult = {
      files: [{ file: 'macros/00_bracket_pair.yml', baseVersion: 'sha256:a', create: false, delete: true, edits: [] }],
      references: [ref],
      diagnostics: [],
    };
    const { message, detail } = describeItemEdit({ op: 'delete', kind: 'macro', name: 'Bracket Pair' }, result);
    expect(message).toContain('マクロ Bracket Pair を削除します。');
    expect(message).toContain('参照が 1 件あり');
    expect(detail).toBe('削除: macros/00_bracket_pair.yml');
  });

  it('名前の変更は書き換える参照の件数と、改名・書き換えのファイルを出す', () => {
    const result: PlanItemEditResult = {
      files: [
        { file: 'macros/00_bracket_pair.yml', baseVersion: 'sha256:a', create: false, renameTo: 'macros/00_square.yml', edits: [{ range: { start: { line: 1, character: 6 }, end: { line: 1, character: 18 } }, newText: 'Square' }] },
        { file: 'layers/0_base.yml', baseVersion: 'sha256:b', create: false, edits: [] },
      ],
      references: [ref, ref],
      diagnostics: [],
    };
    const { message, detail } = describeItemEdit({ op: 'rename', kind: 'macro', name: 'Bracket Pair', to: 'Square' }, result);
    expect(message).toContain('参照 2 件も書き換えます。');
    expect(detail.split('\n')).toEqual(['名前の変更: macros/00_bracket_pair.yml → macros/00_square.yml（書き換えあり）', '書き換え: layers/0_base.yml']);
  });

  it('追加は作るファイル', () => {
    const result: PlanItemEditResult = { files: [{ file: 'combos/01_x.yml', baseVersion: null, create: true, edits: [] }], references: [], diagnostics: [] };
    expect(describeItemEdit({ op: 'create', kind: 'combo', name: 'X' }, result)).toEqual({
      message: 'コンボ X を追加します。すぐにファイルに書きます（元に戻すで戻せます）。',
      detail: '作成: combos/01_x.yml',
    });
  });

  it('preset の展開（v0.3）は手順に置き換えることと、書き換えるファイル', () => {
    const result: PlanItemEditResult = {
      files: [{ file: 'macros/02_copy_selected.yml', baseVersion: 'sha256:c', create: false, edits: [] }],
      references: [],
      diagnostics: [],
    };
    expect(describeItemEdit({ op: 'expandPreset', kind: 'macro', name: 'Copy Selected' }, result)).toEqual({
      message:
        'マクロ Copy Selected の preset を手順に展開します。preset: の行を同梱の定義の手順（sequence:）に置き換えます（キーボードに書く値は変わりません）。すぐにファイルに書きます（元に戻すで戻せます）。',
      detail: '書き換え: macros/02_copy_selected.yml',
    });
  });
});

describe('itemEditErrorMessage', () => {
  it('-32602 はサーバーの文を見せる', () => {
    const error = { code: ErrorCodes.InvalidParams, message: 'row0 に Q はすでにあります', data: { field: 'edit.to' } };
    expect(itemEditErrorMessage({ op: 'renamePosition', hand: 'left', row: 0, col: 0, to: 'Q' }, error)).toBe(
      '左手 row 0 col 0 の位置の名前を Q に変えられませんでした（row0 に Q はすでにあります）',
    );
  });

  it('-32061 の verify は compile の結果が変わるためと書く', () => {
    const error = { code: ErrorCodes.EditNotLocal, message: '照合に失敗', data: { address: ref, reason: 'verify' } };
    expect(itemEditErrorMessage({ op: 'rename', kind: 'macro', name: 'A', to: 'B' }, error)).toContain('名前を変える前と後で compile の結果が変わるため');
    expect(itemEditErrorMessage({ op: 'expandPreset', kind: 'macro', name: 'A' }, error)).toBe(
      'マクロ A の preset を手順に展開できませんでした（展開の前と後で compile の結果が変わるため）。照合に失敗',
    );
  });
});

describe('isItemEdit', () => {
  it('形の違うメッセージは受け付けない', () => {
    expect(isItemEdit({ op: 'create', kind: 'macro', name: 'X' })).toBe(true);
    expect(isItemEdit({ op: 'create', kind: 'shortcut', name: 'X', value: 'A' })).toBe(true);
    expect(isItemEdit({ op: 'create', kind: 'shortcut', name: 'X' })).toBe(false);
    expect(isItemEdit({ op: 'rename', kind: 'layer', name: 'Base', to: 'Main' })).toBe(true);
    expect(isItemEdit({ op: 'delete', kind: 'layer', name: 'Base' })).toBe(false);
    expect(isItemEdit({ op: 'renamePosition', hand: 'left', row: 0, col: 1, to: 'q' })).toBe(true);
    expect(isItemEdit({ op: 'renamePosition', hand: 'up', row: 0, col: 1, to: 'q' })).toBe(false);
    expect(isItemEdit({ op: 'expandPreset', kind: 'macro', name: 'Copy Selected' })).toBe(true);
    expect(isItemEdit({ op: 'expandPreset', kind: 'combo', name: 'Copy Selected' })).toBe(false);
    expect(isItemEdit({ op: 'expandPreset', kind: 'macro' })).toBe(false);
    expect(isItemEdit(null)).toBe(false);
  });
});

describe('textDiagnostics', () => {
  it('address か file のあるものをファイルごとにし、range がなければファイルの先頭', () => {
    const range = { start: { line: 7, character: 11 }, end: { line: 7, character: 28 } };
    const result = textDiagnostics({
      diagnostics: [
        { severity: 'error', source: 'structure', message: 'a', address: ref, range },
        { severity: 'warning', source: 'semantic', message: 'b', file: 'layers/1_symbols.yml' },
        { severity: 'error', source: 'structure', message: 'c', file: 'macros/' },
        { severity: 'error', source: 'structure', message: 'd' },
      ],
    });
    expect([...result.keys()]).toEqual(['layers/0_base.yml', 'layers/1_symbols.yml']);
    expect(result.get('layers/0_base.yml')).toEqual([{ range, severity: 'error', message: 'a', source: 'structure' }]);
    expect(result.get('layers/1_symbols.yml')?.[0]?.range).toEqual({ start: { line: 0, character: 0 }, end: { line: 0, character: 0 } });
  });
});
