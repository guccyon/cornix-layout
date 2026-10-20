// 自分のショートカットの節（spec.md の「ファイルの種類ごと」の shortcuts.yaml）。名前ごとの値（候補から Shortcut(...) を除く）。
import type { ProfileSnapshot, ShortcutSnapshot } from '../protocol';
import { ItemSection, type ItemSectionOptions, type ListEntry } from './itemList';
import { shortcutView, type ShortcutView } from './itemsModel';

export class ShortcutEditor extends ItemSection<ShortcutSnapshot, ShortcutView> {
  constructor(options: ItemSectionOptions) {
    super(options, { kind: 'shortcut', title: 'ショートカット', namePlaceholder: '前のタブへ', className: 'shortcut-editor' });
  }

  protected items(snapshot: ProfileSnapshot): ShortcutSnapshot[] | undefined {
    return snapshot.shortcuts;
  }

  protected entry(shortcut: ShortcutSnapshot, view: ShortcutView): ListEntry {
    // 1 つのファイル（shortcuts.yaml）に並ぶので、その名前の行の下だけを見る
    return { name: shortcut.name, detail: view.value.text, file: shortcut.address.file, prefix: shortcut.address };
  }

  protected view(shortcut: ShortcutSnapshot): ShortcutView {
    return shortcutView(shortcut, this.pending);
  }

  protected shape(): unknown {
    return 'shortcut';
  }

  protected buildDetail(_shortcut: ShortcutSnapshot, body: HTMLElement): void {
    body.append(this.keyField({ label: '値', focus: 'value', context: 'shortcutValue', entry: () => this.current.value, placeholder: 'Command + Shift + [' }));
  }
}
