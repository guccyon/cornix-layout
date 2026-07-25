# Vial の layout 取り込みで permissive_hold が復元されない件

## 症状

`qmk_settings.yaml` で `permissive_hold: true` にして compile → `.vil` を Vial（web）で
load すると、UI のチェックが外れる（false に戻る）。他の boolean 設定
（`hold_on_other_key_press` / `chordal_hold`）も同様に戻る可能性がある。

## 切り分け結果（2026-07-24 調査）

**Cornix ツール側にバグはない。** 以下を実装・Vial公式ソースの両面から確認済み:

1. QSID マッピングは正しい（vial-qmk `quantum/qmk_settings.c` の protos で確認）:
   - `22` = permissive_hold（`tapping_v2` bit0）
   - `23` = hold_on_other_key_press（bit1）
   - `24` = retro_tapping（bit2）
   - `26` = chordal_hold（bit3）
   - `8` = 旧方式（`tapping` バイトに permissive_hold 等をビットフィールド格納）。
     firmware世代で 8系 か 22系 のどちらか。Cornix対象ファームは **22系（新）**。
2. Cornix が出す `.vil` の `settings` は、Vial 純正が書き出す `.vil` と**バイト単位で一致**
   （実機からVial webでexportした `tmp/layout.vil` も `"22": 1`）。
3. Vial純正でも「チェック→save current layout→その.vilをload」で同じくチェックが外れる
   → Cornixを通さなくても再現する = **Vial の load（取り込み）側の問題**。

## Vial 実装の事実（vial-gui master, web版も同じ MainWindow→restore_layout 経路）

- `protocol/keyboard_comm.py` の `restore_layout` は settings を**スキップしていない**。
  `data["settings"]` の各 qsid をそのまま読み、`is_qsid_supported(qsid)` が真なら
  `qmk_settings_set(qsid, value)` を呼ぶ。**別キー参照もしていない**（save/restore同一qsid）。
  → 「別キーに出力して復元させる」ような裏技のターゲットは存在しない。
- `qmk_settings_set` は `CMD_VIAL_QMK_SETTINGS_SET` を送るだけで、vial-qmk側が即EEPROM永続化
  （別途saveコマンド不要）。
- `is_qsid_supported` は同梱の `qmk_settings.json`（qsid_fields）で判定。22は含まれる。
- `qsid_serialize(22, 1)` は boolean width1 → `b'\x01'`。ビット処理はレガシーqsid8用でUI層のみ。

### vial.rocks 実デプロイ版で確認済み（2026-07-24）

利用環境は vial.rocks（ホスト型web、ローカルビルドではない）。トップページのビルドハッシュ
`Vial: e42622c352b69eff523a467718db487ab9c9cbf2` の keyboard_comm.py を直接確認したところ、
**その版の restore_layout にも settings 復元ループは存在する**（qsid 22 を is_qsid_supported 通過後
qmk_settings_set で書き戻す）。export に `22:1` が入る事実から is_qsid_supported(22)=True も確定。
→ **「Vial web が復元をスキップ」説・「別キー読み替え」説はいずれも否定**。load は実際に
qmk_settings_set(22,1) を送っているはず。

### 決定的観測（2026-07-24）：EEPROM 未永続化と判明

VialWeb を切断→再接続（何も load していない状態）した時点で、**すでに permissive hold の
チェックが外れている**。Vial は接続時 `reload_settings()` で `qmk_settings_get(22)` を実機から
読むので、これは **ファームが QSID 22 に 0 を返す＝実機 EEPROM に保持されていない**ことを意味する。

全観測が一本化:
- タブで直接チェック → RAM には効きセッション中は操作感が良い。
- 切断・再接続で EEPROM から読み直し → 保持されず 0 に戻る。
- `.vil` load で書き戻しても同様に保持されず戻る。

→ **load 処理も Cornix も無関係。根本原因は firmware 側で QMK設定（特に tapping_v2 系）が
EEPROM に永続化されていないこと。**

範囲確定の確認: 再接続直後に整数設定（tapping_term=180 等）も戻るか。
- 一緒に戻る → QMK設定のEEPROM保存が丸ごと効いていない（boot時リセット/バージョン不整合等）。
- 数値は保持されbooleanだけ戻る → tapping_v2 バイト固有の保存不具合。

### 追加観測（2026-07-26）：permissive_hold のみ非永続

ユーザ確認: **他のQMK設定（tapping_term 等）は正しく永続化される。permissive_hold のみ
再接続で 0 に戻る。** hold_on_other_key_press(bit1)/chordal_hold(bit3) 等は残るのに
permissive_hold(bit0) だけダメ。
→ EEPROM保存機構は正常。**permissive_hold 固有の上書き/リセットがファーム内で起きている**。
最有力:
  1. config.h の `#define PERMISSIVE_HOLD` 等がランタイム設定と競合しboot時にruntime値を潰す
  2. keymap.c に `get_permissive_hold(...)` 等の per-key オーバーライド定義がある
  3. そのビルド世代で QSID 22 の起動時apply/保存が #ifdef で欠けている
確定にはファームソース（keyboards/.../config.h, rules.mk, keymap.c, ベースvial-qmkのコミット）が必要。

### 対処（ファーム側）

1. 確実: 対象キーボードの config.h（vial-qmk派生）に `#define PERMISSIVE_HOLD` を入れて再ビルド
   （ランタイム設定に依存せず常時有効）。HOLD_ON_OTHER_KEY_PRESS / CHORDAL_HOLD も同様。
2. あるいは QMK設定のEEPROM永続化自体を修正（ファームのバージョン整合/EEPROMリセット条件調査）。

## 切り分けの決め手（未実施の検証案）

load 後に **整数設定**（tapping_term=180, oneshot_timeout=1000, flow_tap=120 等）が
デフォルトに戻るか、**boolean だけ**戻るかを見る:
- 全部戻る → Vial webビルドが古い/settings非復元 → Vial更新 or QMK Settingsタブで直接設定
- booleanだけ戻る → firmware/シリアライズのビットqsid問題（.vilの値は正しい）
- 何も戻らずチェック表示だけ → UIリフレッシュの表示バグ（実機は適用済み）

## 実務上の回避策

QMK設定は `.vil` の load 経由では信頼しない。**Vial の「QMK Settings」タブで
permissive hold を直接チェックして保存**（実機EEPROMへ直書き、確実に永続化）。
キーマップ/マクロ/コンボ/タップダンスは従来通り `.vil` load でOK。

関連: [[settings_ordering]]
