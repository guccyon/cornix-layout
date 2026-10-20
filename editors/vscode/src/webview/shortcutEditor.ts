// 自分のショートカットの節（spec.md の「ファイルの種類ごと」の shortcuts.yaml）。名前ごとの値（候補から Shortcut(...) を除く）。
// v0.3: 「同梱からコピー」（tasks-v0.3.md の決めたことの 2）。同梱のショートカットの階層の選択（presetPicker.ts）で選んだものを、
// 名前はラベル・値は同梱の表記（text）で足す（profile/planItemEdit の create。ホストが確認してすぐ書く）。同じ名前があれば、追加の欄を開いて名前を聞く。
// コピーしても既存の参照（Shortcut('アプリ:カテゴリ:ラベル')）は書き換えない。
import type { ProfileSnapshot, ShortcutSnapshot } from '../protocol';
import { ItemSection, type ItemSectionOptions, type ListEntry } from './itemList';
import { shortcutView, type ShortcutView } from './itemsModel';
import { loadShortcutTree, PresetPicker, type PresetEntry } from './presetPicker';

export class ShortcutEditor extends ItemSection<ShortcutSnapshot, ShortcutView> {
  /** 「同梱からコピー」の選択 */
  readonly copyPicker: PresetPicker;

  constructor(options: ItemSectionOptions) {
    super(options, { kind: 'shortcut', title: 'ショートカット', namePlaceholder: '前のタブへ', className: 'shortcut-editor' });
    this.copyPicker = new PresetPicker({
      kind: 'shortcut',
      buttonLabel: '同梱からコピー',
      className: 'shortcut-copy',
      loadTree: () => loadShortcutTree(this.host),
      current: () => null,
      onPick: (_name, entry) => this.copyPreset(entry),
    });
    this.toolbar.append(this.copyPicker.element);
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

  /** 同梱のショートカットを自分のものとして足す。同じ名前があれば、名前と値を入れた追加の欄を開く */
  private copyPreset(entry: PresetEntry): void {
    const value = entry.text;
    if (value === undefined) return;
    if (this.itemNames().includes(entry.label)) {
      this.openCreateForm(entry.label, value, `ショートカット「${entry.label}」はすでにあります。別の名前にしてください`);
      return;
    }
    this.createItem({ op: 'create', kind: 'shortcut', name: entry.label, value });
  }
}
