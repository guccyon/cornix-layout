# Cornix Keyboard Layout Manager - Development Guide

## Instructions
常に日本語で回答してください。コードや設計に関する説明、エラーの報告などもすべて日本語を使用してください。

## Quick Links

- **設計**: [docs/architecture.md](../docs/architecture.md)（方針・層と依存の向き・データの流れ・コード規約）
- **契約**: [docs/tasks.md](../docs/tasks.md)（主なクラスの公開メソッド、リファクタの経緯）
- **座標系**: [architecture/coordinate_system.md](architecture/coordinate_system.md)（論理位置と layout.vil の物理位置）
- **背景**: [context/project_background.md](context/project_background.md)
- **Features**:
  - [Reference System](features/reference_system.md) - Macro / TapDance の参照
  - [Modifier Expressions](features/modifier_expressions.md) - VS Code 風修飾キー表現
  - [Rename](features/rename.md) - `cornix rename` と `bin/rename_file`
  - [Validation](features/validation.md) - 構造検証と意味検証
  - [Device / MCP](features/device_mcp.md) - キーボード直接操作と MCP サーバー
- **Memories**: [memories/](memories/)
  - [domain_architecture_refactor](memories/domain_architecture_refactor.md) - 作り直しの知見・意図的に変えた振る舞い
  - [vial_device_protocol](memories/vial_device_protocol.md) - RMK 0.8 / Vial プロトコル
  - [settings_ordering](memories/settings_ordering.md) - QMK Settings の QSID と順序
  - [vial_qmk_settings_restore_issue](memories/vial_qmk_settings_restore_issue.md) - permissive_hold が復元されない件
  - [key_notes](memories/key_notes.md) - 割り当ての注記（`{ key:, note: }`）の持ち方と引き継ぎ
- **テスト**: [spec/README.md](../spec/README.md)

---

## Development Instructions

**重要な原則**:
- 作業完了時には、得られた知見を `.claude/memories/` に記録すること
- `README.md` と `README.en.md` は**常に一緒に更新**すること
- プロンプト及び計画、作業結果の報告は全て日本語で行うこと
- タスクを実行してコミットする際には必ず RSpec が全て通る状態を確認すること（`LANG=ja_JP.UTF-8 bundle exec rspec`）
- Pull Request の説明は下記「Pull Request の説明」のルールに従うこと
- [docs/architecture.md](../docs/architecture.md) の方針・依存の向き・コード規約を守ること
- 実機のキーボードへの書き込み（`cornix device apply` / `restore`、MCP の書き込み）は利用者の同意なしに行わないこと

### Pull Request の説明

PR の説明は、読み手が背景から結論まで追えるよう丁寧に構造化して日本語で書く。
`.github/pull_request_template.md` の見出しを使い、変更内容に応じて必要なセクションを取捨選択する（該当しないセクションは削除）。

- **概要**: 何が変わるかを 1〜3 文で
- **背景**: なぜこの変更が必要になったか（どの作業で見つかったか、どんな要望か）
- **問題**: バグ修正では、再現手順・期待した結果・実際の結果と原因（コードの場所）
- **対応内容**: どう直したか。変更点が複数あれば項目ごとに分け、主要なファイル/クラスを示す
- **影響範囲・互換性**: 既存の設定や layout.vil への影響、Breaking Change、利用者側で必要な作業
- **動作確認**: RSpec の結果、round-trip check、実データでの確認
- **補足**: 対象外にしたこと、今後の課題、マージ後に必要な作業など

小さな変更（typo 修正など）では概要と対応内容だけでよい。複数の独立した修正を含む PR では、問題と対応内容を修正ごとに分けて書く。

## Project Overview

Cornix キーボードの Vial `layout.vil` と YAML 設定ファイル（`config/`）の双方向変換ツール。

- `cornix compile` / `decompile` / `validate` / `rename` / `cleanup`: 設定ファイルの変換・検証・名前付け
- `cornix device` / `cornix mcp`: 接続中のキーボードへの直接読み書き（差分だけ書き込む）
- 名前参照（`Macro('名前')`）、VS Code 風修飾キー表現（`Cmd + Q`）、エイリアス（`Tab`, `!`）
- decompile → compile で 16bit 値が元と一致する

## Architecture

```
Interface       CLI（bin/cornix → Interface::Cli::Main）・MCP サーバー（Interface::Mcp::Server）
Application     ユースケース（Compile / Decompile / Validate / Cleanup / RenameFiles / SuggestRenames / Device*）と Environment（DI）
Mapping         KeycodeCatalog / KeycodeCodec / KeycodeNotation / VialNotation / MacroCodec / ProfileMapper / QmkSettingCatalog
Planning        ImageDiff / Change / Plan
Domain          Profile 集約と値オブジェクト（Keycode, ModifierSet, LayerRef, Layer, Macro, TapDance, Combo, PositionMap, ...）。I/O なし
Image           DeviceImage（16bit 値とバイト列のまま）。I/O なし
Storage         ConfigRepository（config/*.yaml）/ VilFile（layout.vil）/ BackupStore / ConfigEditor / DecompileLock
Device          HidBridge / Protocol / Session / Reader / Planner / Writer
```

```
compile    config/ ─ConfigRepository→ Profile ─ProfileMapper→ DeviceImage ─VilFile→ layout.vil
decompile  layout.vil ─VilFile→ DeviceImage ─ProfileMapper→ Profile ─ConfigRepository→ config/
validate   ConfigRepository#load（構造検証）→ Profile#diagnostics（意味検証）
device     layout.vil → DeviceImage（目標）、実機 ─Reader→ DeviceImage（現在）→ ImageDiff → Plan(token) → Writer → 読み直して検証
```

- 文字列 ⇄ Keycode は `KeycodeNotation`（設定ファイル）と `VialNotation`（.vil）、16bit 値 ⇄ Keycode は `KeycodeCodec`、
  Profile ⇄ DeviceImage は `ProfileMapper` だけが行う。キーコード文字列は読み込み時に 1 回だけ解析する
- 依存の向きは `spec/architecture_spec.rb` が検査する（Domain / Image は何にも依存しない）
- ライブラリの中で `puts` / `gets` / `exit` しない。エラーは `Cornix::Error` 系（`lib/cornix/errors.rb`）で送出し、
  CLI が標準エラー出力に `エラー: …` と表示して終了コード 1

## Directory Structure

```
bin/
  cornix            CLI
  diff_layouts      2 つの layout.vil を 16bit 値で比べる（round-trip check）
  rename_file       RenameFiles の薄い入口（JSON で結果を表示）
data/
  keycodes.yaml     名前付きキーコードの表（Vial プロトコル 6）
  aliases.yaml      別名（QMK 名: [正規名, 別名...]。先頭が decompile で書く名前）
  qmk_settings.yaml QSID・名前・グループ・幅
  dangerous_keycodes.yaml  実機に書き込まないキーコード
lib/cornix.rb       全ファイルを層の順に require
lib/cornix/
  domain/ image/ mapping/ planning/ storage/ device/ application/ interface/
  errors.rb, position_map.yaml（config/position_map.yaml のテンプレート）
ext/cornix_hid/     raw HID ブリッジ（Swift、tmp/cornix-hid にビルド）
spec/               lib と同じ層の構成 + end_to_end_spec.rb / architecture_spec.rb / fixtures/
docs/               architecture.md, tasks.md
config/             利用者の設定（生成物。main ブランチにはない）
```

## Testing

```bash
LANG=ja_JP.UTF-8 bundle exec rspec                         # すべて（キーボード不要）
LANG=ja_JP.UTF-8 bundle exec rspec spec/mapping            # 層ごと
LANG=ja_JP.UTF-8 bundle exec rspec spec/end_to_end_spec.rb # compile / decompile の一致
```

- `spec/end_to_end_spec.rb`: `spec/fixtures/test_config` と `spec/fixtures/authors_config` を compile し、
  保存した `layout.vil` / `authors_baseline.vil` と 16bit 値で一致すること、decompile → compile で戻ること
- 旧実装の結果は `spec/fixtures/expected/` に保存してあり、それと比べる
- 実機の代わりに `spec/device/fake_rmk_device.rb`（RMK 0.8 の応答を模したもの）を使う

### Round-trip check（手元の layout.vil で）

```bash
mv config config.backup
cp ~/Downloads/layout.vil tmp/layout.vil
cornix decompile && cornix compile
ruby bin/diff_layouts       # tmp/layout.vil と layout.vil を 16bit 値で比較 → === ✓ FILES ARE IDENTICAL ===
```

## Key Design Decisions

- **キーコード表**: 名前付きのキーコードだけを `data/keycodes.yaml` に持ち、`MO(n)` / `LT(n, kc)` / `LSFT(kc)` など引数付きは
  `KeycodeCodec` の定数とビット演算で組み立てる。別名は `data/aliases.yaml`（重複は読み込み時にエラー）
- **.vil の表記**: `VialNotation#format` は Vial GUI が保存する表記と同じ。Vial に名前のない値は `0xHHHH`
- **decompile の正規形**: 別名 → 修飾キー式（`Ctrl, Option, Shift, Command` の順）→ 関数形式 → `0xHHHH`。
  参照は `Macro('名前')` / `TapDance('名前')`、設定は名前の形
- **修飾キー**: `Domain::ModifierSet` は左右どちらか一方。左右の混在はエラー
- **知らない値は落とさない**: 解釈できない 16bit 値は `Keycode::Raw`、.vil の未対応項目は `DeviceImage#meta` で往復させる
- **Position Map**: テンプレート `lib/cornix/position_map.yaml` → 利用者版 `config/position_map.yaml`。
  座標変換は `Domain::PositionMap` だけが行う
- **rename**: 名前参照はテキスト置換で書き換え、変更の前後の compile 結果（16bit 値）を比べて違えば元に戻す
- **cleanup / Environment**: 場所は `Application::Environment#root`（既定はリポジトリのルート）から決まる。カレントディレクトリに依存しない

## Troubleshooting

- **decompile が止まる**: `config/layers/` か `config/macros/` にファイルがある。退避するか `cornix cleanup`（ロックがあれば `-f`）
- **Round-trip check が失敗する**: `ruby bin/diff_layouts` で差分の場所を確認
- **テストが失敗する**: `LANG=ja_JP.UTF-8` を付けているか確認。`bundle exec rspec --format documentation` で詳細
- **依存の向きの違反**: `spec/architecture_spec.rb` の失敗は層の依存の向きの誤り（docs/architecture.md の表を参照）

## References

- [QMK Keycodes](https://docs.qmk.fm/keycodes)
- [Vial Documentation](https://get.vial.today/)
- [QMK Firmware](https://docs.qmk.fm/)
