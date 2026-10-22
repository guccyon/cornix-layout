// タップダンスの節（spec.md の「ファイルの種類ごと」の tap_dance/）。4 つの動作のキー（自分自身への参照は候補から除く）とその注記、tapping_term。
// v0.5: 一覧は使っているタップダンスだけ（未保存の変更を当てた番号の順）。番号を変えると番号の参照（TD(2) など）も書き換わる。
import type { ProfileSnapshot, TapDanceSnapshot } from '../protocol';
import { arrangeItems, snapshotItems } from '../itemIndex';
import { ItemSection, parseMilliseconds, type ItemSectionOptions, type ListEntry } from './itemList';
import { TAP_DANCE_ACTIONS, tapDanceView, type TapDanceView } from './itemsModel';

/** 読み込みで tapping_term を書いていないときの値（protocol.md の 12.2） */
export const DEFAULT_TAPPING_TERM = 250;

export class TapDanceEditor extends ItemSection<TapDanceSnapshot, TapDanceView> {
  constructor(options: ItemSectionOptions) {
    super(options, {
      kind: 'tapDance',
      title: 'タップダンス',
      namePlaceholder: 'Tab Escape',
      className: 'tap-dance-editor',
      indexNote: '番号の参照（TD(2) / TapDance(2) など）も新しい番号に書き換えます',
    });
  }

  protected items(snapshot: ProfileSnapshot): TapDanceSnapshot[] | undefined {
    return snapshot.tapDances ? arrangeItems(snapshotItems(snapshot, 'tapDance'), this.pending).used : undefined;
  }

  protected entry(tapDance: TapDanceSnapshot, view: TapDanceView): ListEntry {
    return { name: tapDance.name, index: tapDance.index, detail: view.description.value, file: tapDance.file };
  }

  protected view(tapDance: TapDanceSnapshot): TapDanceView {
    return tapDanceView(tapDance, this.pending);
  }

  protected shape(): unknown {
    return 'tapDance';
  }

  protected buildDetail(tapDance: TapDanceSnapshot, body: HTMLElement): void {
    // 自分自身を動作に入れると押したときに戻ってこないので、候補から除く
    const candidateParams = { exclude: `TapDance('${tapDance.name}')` };
    body.append(
      this.valueField<string>({
        label: '説明',
        focus: 'description',
        type: 'text',
        entry: () => this.current.description,
        parse: (text) => ({ value: text }),
        removable: true,
        placeholder: () => '（なし）',
        className: 'item-description',
      }),
    );
    for (const { name, label } of TAP_DANCE_ACTIONS) {
      body.append(
        this.keyField({
          label,
          focus: `action:${name}`,
          context: 'tapDanceAction',
          candidateParams,
          entry: () => this.current.actions[name],
          note: true,
          remove: {
            label: `${label}の割り当てを消す`,
            onClick: () => {
              const entry = this.current.actions[name];
              if (entry.text !== '') this.edit({ op: 'remove', address: entry.address }, `action:${name}`);
            },
          },
        }),
      );
    }
    body.append(
      this.valueField<number>({
        label: 'tapping_term',
        focus: 'tapping-term',
        type: 'number',
        entry: () => this.current.tappingTerm,
        parse: parseMilliseconds,
        removable: true,
        placeholder: () => `既定 ${DEFAULT_TAPPING_TERM}`,
        hint: () => this.qmkHint(),
      }),
    );
  }

  /** QMK 設定の tapping_term を薄く添える（spec.md の「ファイルの種類ごと」） */
  private qmkHint(): string {
    const setting = this.snapshot?.settings.find((s) => s.name === 'tapping_term');
    const value = setting?.value ?? setting?.default;
    return typeof value === 'number' ? `ミリ秒（QMK 設定の tapping_term: ${value}）` : 'ミリ秒';
  }
}
