// プロファイルを 1 つの仮想ドキュメントに見立てる URI（ADR 015、protocol.md の 11. の 9）。
//   cornix-profile:/<名前>?dir=<dir>
// タブの題は URI の最後の部分（名前）になる。プロファイルの場所は dir（ワークスペースからの相対パス、外なら絶対パス）で指す。
// カスタムエディタの selector は "cornix-profile:/**"（スキームまで含めた形で当てる）。vscode に依存しない。

export const PROFILE_SCHEME = 'cornix-profile';

export type ProfileUriParts = { scheme: string; path: string; query: string };

export function profileUriParts(dir: string, name: string): ProfileUriParts {
  const label = name.replace(/[/\\]/g, '_') || 'profile';
  return { scheme: PROFILE_SCHEME, path: `/${label}`, query: new URLSearchParams({ dir }).toString() };
}

/** URI から dir を取り出す。cornix-profile: でない・dir がなければ undefined */
export function profileDirOf(uri: { scheme: string; query: string }): string | undefined {
  if (uri.scheme !== PROFILE_SCHEME) return undefined;
  return new URLSearchParams(uri.query).get('dir') ?? undefined;
}
