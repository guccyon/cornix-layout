// テキストで開いたときの波線（protocol.md の 12.7）。snapshot の diagnostics をファイルごとの波線にする。vscode に依存しない
// （DiagnosticCollection に入れるのは profileEditorProvider.ts）。
import type { Diagnostic, ProfileSnapshot, Range } from '../protocol';

export type TextDiagnostic = { range: Range; severity: Diagnostic['severity']; message: string; source: Diagnostic['source'] };

const FILE_START: Range = { start: { line: 0, character: 0 }, end: { line: 0, character: 0 } };

/**
 * 設定ディレクトリからの相対パス → そのファイルの波線。address も file もないもの（どのファイルとも言えない問題）と、
 * ディレクトリの問題（"macros/"）は出さない。range がなければファイルの先頭
 */
export function textDiagnostics(snapshot: Pick<ProfileSnapshot, 'diagnostics'>): Map<string, TextDiagnostic[]> {
  const result = new Map<string, TextDiagnostic[]>();
  for (const diagnostic of snapshot.diagnostics) {
    const file = diagnostic.address?.file ?? diagnostic.file;
    if (!file || file.endsWith('/')) continue;
    const list = result.get(file) ?? [];
    list.push({ range: diagnostic.range ?? FILE_START, severity: diagnostic.severity, message: diagnostic.message, source: diagnostic.source });
    result.set(file, list);
  }
  return result;
}
