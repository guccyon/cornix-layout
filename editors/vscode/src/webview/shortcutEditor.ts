// 自分のショートカットの節（spec.md の「ファイルの種類ごと」の shortcuts.yaml）。名前ごとの値（候補から Shortcut(...) を除く）。
// v0.3: 同梱のショートカットのコピー（tasks-v0.3.md の決めたことの 2）。選んだものを、名前はラベル・値は同梱の表記（text）で足す。
// 同じ名前があれば、追加の欄を開いて名前を聞く。コピーしても既存の参照（Shortcut('アプリ:カテゴリ:ラベル')）は書き換えない。
// v0.5（tasks-v0.5.md の決めたことの 1・5）: 「同梱からコピー」のボタンはやめ、節の「追加」の一覧の「同梱から」にまとめた。
// 追加（コピーも、名前を入れて足すのも）は itemEdit の create のまま送り、ホストが未保存の変更（["shortcuts", 名前] の set）に積む。
// 一覧には未保存で足したショートカットも並べ、値を直せる（itemsModel.ts の shortcutItems）。ショートカットには番号も未使用もない。
import type { ProfileSnapshot, ShortcutSnapshot } from '../protocol';
import { ItemSection, type ItemSectionOptions, type ListEntry } from './itemList';
import { shortcutItems, shortcutView, type ShortcutView } from './itemsModel';
import type { PresetEntry } from './presetPicker';

export class ShortcutEditor extends ItemSection<ShortcutSnapshot, ShortcutView> {
  constructor(options: ItemSectionOptions) {
    super(options, { kind: 'shortcut', title: 'ショートカット', namePlaceholder: '前のタブへ', className: 'shortcut-editor', bundled: 'shortcut' });
  }

  protected items(snapshot: ProfileSnapshot): ShortcutSnapshot[] | undefined {
    return snapshot.shortcuts ? shortcutItems(snapshot.shortcuts, this.pending) : undefined;
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
  protected override pickBundled(entry: PresetEntry): void {
    const value = entry.text;
    if (value === undefined) return;
    if (this.itemNames().includes(entry.label)) {
      this.openCreateForm(entry.label, { value, message: `ショートカット「${entry.label}」はすでにあります。別の名前にしてください` });
      return;
    }
    this.createItem({ op: 'create', kind: 'shortcut', name: entry.label, value });
  }
}
