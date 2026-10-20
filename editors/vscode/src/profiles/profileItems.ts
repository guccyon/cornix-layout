// profile/list の結果を、一覧（アクティビティバー）と QuickPick に並べる形にする。vscode に依存しない。
import type { ProfileListResult } from '../protocol';

export type ProfileItem = {
  dir: string;
  name: string;
  /** 名前の横に薄く出す文字（名前が重なるときの dir、既定の印） */
  description: string;
  isDefault: boolean;
};

/** 既定のプロファイルを先頭に。名前が重なるときだけ dir を添える（protocol.md の 5.1） */
export function profileItems(result: ProfileListResult): ProfileItem[] {
  const counts = new Map<string, number>();
  for (const profile of result.profiles) counts.set(profile.name, (counts.get(profile.name) ?? 0) + 1);
  const items = result.profiles.map((profile): ProfileItem => {
    const isDefault = profile.dir === result.default;
    const parts = [(counts.get(profile.name) ?? 0) > 1 ? profile.dir : '', isDefault ? '既定' : ''].filter(Boolean);
    return { dir: profile.dir, name: profile.name, description: parts.join(' · '), isDefault };
  });
  return [...items.filter((item) => item.isDefault), ...items.filter((item) => !item.isDefault)];
}
