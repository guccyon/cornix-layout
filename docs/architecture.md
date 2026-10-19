# アーキテクチャ

cornix-layout の内部構造。設計の経緯は設計案ドキュメント（Claude Docs「cornix-layout リアーキテクチャ設計案」）、
タスクの分担と公開メソッドの契約は [tasks.md](tasks.md)、Profile と値オブジェクトの詳細は [domain-model.md](domain-model.md) を参照。

## 方針

1. **ドメインモデルを中心に置く。** config/*.yaml も layout.vil も HID のバイト列も外側の表現で、内側には型のある値だけを置く。
2. **値は一度だけ解析する。** キーコードの文字列は読み込み時に `Domain::Keycode` へ変換し、以降は文字列を再解析しない。
3. **変換の口を絞る。** 文字列 ⇄ Keycode は `KeycodeNotation`（設定ファイル）と `VialNotation`（.vil）、
   16bit 値 ⇄ Keycode は `KeycodeCodec`、Profile ⇄ DeviceImage は `ProfileMapper` だけが行う。
4. **表に持つのは名前だけ。** `data/keycodes.yaml` は名前付きのキーコード、`data/aliases.yaml` は人が読む別名。
   MO / LT / MT / LSFT など引数付きのキーコードは `KeycodeCodec` の定数とビット演算で組み立てる。
5. **I/O は境界に押し出す。** Domain / Image / Mapping / Planning は純粋な Ruby。ファイルは Storage、HID は Device だけが触る。
6. **知らない値は落とさない。** 解釈できない 16bit 値は `Keycode::Raw`、.vil の未対応項目は `DeviceImage#meta` でそのまま往復させる。

## レイヤーと依存の向き

```
Interface       CLI (bin/cornix) ・ MCP サーバー
Application     ユースケース（Compile / Decompile / Validate / Cleanup / Rename / Init / Device*）と Environment（DI）・
                Workspace（使う設定ディレクトリと tmp/ の場所を決める）
Mapping         KeycodeCatalog / KeycodeCodec / KeycodeNotation / VialNotation / MacroCodec / ProfileMapper /
                QmkSettingCatalog / ShortcutCatalog（同梱の data/*.yaml の表）
Planning        ImageDiff / Change / Plan（DeviceImage どうしの差分と書き込み計画）
Domain          Profile 集約と値オブジェクト（Keycode, ModifierSet, LayerRef, Layer, Macro, ...）。I/O なし
Image           DeviceImage（16bit 値とバイト列のまま）。I/O なし
Storage         ConfigRepository（config/*.yaml）/ VilFile（layout.vil）/ BackupStore / SettingsFile（.cornix.yml）
Device          HidBridge / Protocol / Session / Reader / Writer
```

| レイヤー | 参照してよいもの |
| --- | --- |
| domain | なし |
| image | なし |
| mapping | domain, image |
| planning | image |
| storage | domain, image, mapping |
| device | image, planning, mapping |
| application | すべて |
| interface | application |

`spec/architecture_spec.rb` がソースの参照を検査する。`Cornix::Error` 系の例外（`lib/cornix/errors.rb`）はどこからでも使ってよい。

## データの流れ

```
compile    config/ ─ConfigRepository→ Profile ─ProfileMapper→ DeviceImage ─VilFile→ tmp/build/layout.vil
decompile  layout.vil ─VilFile→ DeviceImage ─ProfileMapper→ Profile ─ConfigRepository→ config/
validate   config/ ─ConfigRepository（構造検証）→ Profile#diagnostics（意味検証）
device     layout.vil ─VilFile→ DeviceImage（目標）
           実機 ─Device::Reader→ DeviceImage（現在） → ImageDiff → Plan(token) → Device::Writer → 読み直して検証
```

CLI 直下の `pull` / `status` / `apply` / `restore` は新しいユースケースを持たず、Interface 層で既存のユースケースを組み合わせる
（`pull` = DeviceRead → tmp/layout.vil → Decompile、`status` = Compile → DeviceDiff、`apply` = Compile → DeviceApply、
`restore` = DeviceRestore）。compile の出力 `tmp/build/layout.vil`（`Environment#layout_path`）を一時領域として使い回す。

## 検証

1. **構造検証**: 値オブジェクトの生成時に `Cornix::InvalidValue`。Storage が「ファイル: キー: 内容」に変え、全件まとめて報告する。
2. **意味検証**: `Profile#diagnostics(capabilities)` が `[Domain::Diagnostic]` を返す（参照先の存在、件数の上限、名前の重複など）。

## コード規約

- ファイル名と定数名は 1 対 1（`mapping/keycode_codec.rb` ↔ `Cornix::Mapping::KeycodeCodec`）。大きなクラスは `xxx.rb` + `xxx/` に分ける。
- 値オブジェクトは `Data.define` で作り、`initialize` で検証して `InvalidValue` を送出する。配列と Hash は freeze する。
- `lib/cornix.rb` がレイヤー順・パスの浅い順に全ファイルを require する。クラス定義の時点で必要な定数は、そのファイルの先頭で `require_relative` する。
- ライブラリの中で `puts` / `gets` / `exit` しない（Interface だけが入出力する）。
- テストは RSpec。`spec/` は lib と同じレイヤー構成にする。
