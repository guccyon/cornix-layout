# Cornix Keyboard Layout Manager - Development Guide

## Instructions
常に日本語で回答してください。コードや設計に関する説明、エラーの報告などもすべて日本語を使用してください。

## Quick Links

人にも役立つ設計の文書は `docs/` に置く（一覧: [docs/README.md](../docs/README.md)）。`.claude/` には Claude 向けの開発ルールと作業の知見だけを置く。

- **背景**: [docs/background.md](../docs/background.md)（Cornix と Vial、解決したい問題、用語、layout.vil の構造）
- **設計**: [docs/architecture.md](../docs/architecture.md)（方針・層と依存の向き・データの流れ・コード規約）
- **ドメインモデル**: [docs/domain-model.md](../docs/domain-model.md)（Profile と値オブジェクト、Keycode、座標系、意味検証、ProfileMapper の対応、設定ファイル）
- **契約**: [docs/tasks.md](../docs/tasks.md)（主なクラスの公開メソッド、リファクタの経緯）
- **機能**:
  - [キーコードの表記](../docs/notation.md) - 修飾キー表現、Macro / TapDance の参照、Shortcut('名前')
  - [検証](../docs/validation.md) - 構造検証と意味検証
  - [rename](../docs/rename.md) - `cornix rename` と `bin/rename_file`
  - [キーボード直接操作と MCP](../docs/device.md) - `cornix device` / `cornix mcp`、RMK 0.8 の挙動と安全設計
  - [VS Code 拡張](../docs/vscode-extension/README.md) - 仕様・ADR・ロードマップ・バックエンドとのリクエストの約束（v0.1・v0.2・v0.3、v0.4 は設計。コードは `editors/vscode/`、バックエンドは `cornix serve`）
- **Memories**: [memories/](memories/)
  - [domain_architecture_refactor](memories/domain_architecture_refactor.md) - 作り直しの知見・意図的に変えた振る舞い
  - [settings_ordering](memories/settings_ordering.md) - QMK Settings の QSID と順序
  - [vial_qmk_settings_restore_issue](memories/vial_qmk_settings_restore_issue.md) - permissive_hold が復元されない件
  - [key_notes](memories/key_notes.md) - 割り当ての注記（`{ key:, note: }`）の持ち方と引き継ぎ
  - [named_shortcuts](memories/named_shortcuts.md) - Shortcut('名前') を nape_pro-layout から移植したときの判断
  - [keycode_coverage](memories/keycode_coverage.md) - cornixhub / QMK / vial-qmk に基づくキーコードの網羅と出典
  - [vscode_extension](memories/vscode_extension.md) - VS Code 拡張の作業で分かったこと（QMK 設定の既定値は RMK、YAML の書き換えの注意、CI と必須チェック、通しの確認で分かった古い Ruby が選ばれる件と .vscodeignore の件）
  - [vscode_extension_v03](memories/vscode_extension_v03.md) - VS Code 拡張 v0.3 の作業の知見（P の squash のあとに段 2 のブランチで起きた衝突と解き方、webview.css の末尾の衝突で閉じ括弧が落ちた件、コンテナでの rspec の動かし方）
  - [snapshots](memories/snapshots.md) - スナップショットの履歴（issue #25）で決めたこと（latest の扱い、種類 backup、restore の既定、古いものの削除、device_backups の扱い）とテストの注意
  - [vscode_extension_v02](memories/vscode_extension_v02.md) - VS Code 拡張 v0.2 の作業の知見（コンテナでの rspec の動かし方と統合テストが CI でしか走らない件、偽のサーバーの注意、並列の PR の進め方、planItemEdit の解釈、未保存の変更の並びと畳み方）
- **テスト**: [spec/README.md](../spec/README.md)

---

## Development Instructions

**重要な原則**:
- 作業完了時には、得られた知見を `.claude/memories/` に記録すること
- `README.md`（英語）と `README.ja.md`（日本語）は**常に一緒に更新**すること（下の「README の同期」）
- プロンプト及び計画、作業結果の報告は全て日本語で行うこと
- タスクを実行してコミットする際には必ず RSpec が全て通る状態を確認すること（`LANG=ja_JP.UTF-8 bundle exec rspec`）。VS Code 拡張（`editors/vscode/`）を触ったときは `cd editors/vscode && npm ci && npm run typecheck && npm test` も通ること
- Pull Request の説明は下記「Pull Request の説明」のルールに従うこと
- [docs/architecture.md](../docs/architecture.md) の方針・依存の向き・コード規約を守ること
- 実機のキーボードへの書き込み（`cornix apply` / `restore`、`cornix device apply` / `restore`、MCP の書き込み）は利用者の同意なしに行わないこと

### README の同期

- `README.md`（英語）と `README.ja.md`（日本語）は同じ内容に保つ。**片方を変えたら、同じコミットでもう片方も変える**。英語で書くのは `README.md` だけ（ほかの文書は日本語。GitHub のコミュニティ用ファイル `SECURITY.md` は英日を併記する）
- 節の構成・コード例・リンクをそろえる。コード例の中のコメントや YAML の例の名前・説明は、それぞれの言語に訳す。キーの名前・コマンド・オプション・ツールが出すメッセージは訳さない
- 同期は `spec/docs/readme_sync_spec.rb` が確かめる（見出しのレベルの並び、コードブロックの数と言語、リポジトリ内のファイルと外部へのリンク、節へのリンクの数と行き先）。内容の一致は自分で確かめる
- 日本語の文書から README を指すときは `README.ja.md` へリンクする

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

### マージ後の片付け（このリポジトリ固有）

PR を main にマージしたら、共通の片付け（作業ブランチと worktree の削除、main の worktree の最新化。アカウントのスキル `post-merge-cleanup`）に続けて、次も必ず行う。

- **キーマップのブランチを main に追従させる**: `authors-keymap` と `cornix-default-keymap` は、main の先端に個人のキーマップのコミットを載せたブランチ。
  1. それぞれの worktree で未コミットの変更を確かめる（あれば退避してから）
  2. `git rebase origin/main` し、`cornix validate` が通ることを確かめる
  3. `git push --force-with-lease -u origin <branch>` で remote に反映する
- キーマップのブランチで直した機能（キーマップ以外の変更）は main に取り込み、キーマップのブランチには個人のキーマップのコミットだけを残す
- 手元の Mac で作業していないとき（クラウドのセッションなど）は、remote 側を rebase して push したうえで、手元の worktree（main・`authors-keymap`・`cornix-default-keymap`）も origin に合わせる。
  手元に触れないなら、合わせ方を利用者に伝える
- 新しい worktree を作ったら、起点の worktree（なければ `main`）の `.claude/settings.local.json`（Git の管理外）を作成先の `.claude/` にコピーする（あれば上書きしない）

## Project Overview

Cornix キーボードの Vial `layout.vil` と YAML 設定ファイル（`config/`）の双方向変換ツール。

- `cornix compile` / `decompile` / `validate` / `rename` / `cleanup`: 設定ファイルの変換・検証・名前付け
- `cornix pull` / `status` / `apply` / `restore`: compile・decompile と `cornix device` を組み合わせたショートカット
  （compile の出力は `tmp/build/layout.vil`、pull は `tmp/layout.vil` に読み出してから decompile）
- `cornix init` と共通のオプション `--config` / `--profile` / `--root`: 設定ディレクトリの作成と場所の指定
- `cornix device` / `cornix mcp`: 接続中のキーボードへの直接読み書き（差分だけ書き込む）
- `cornix serve`: VS Code 拡張（`editors/vscode/`）のバックエンド。標準入出力の JSON-RPC（docs/vscode-extension/protocol.md）でプロファイルを読み、候補・検証・書き換えを返す（実機には触らない）
- 名前参照（`Macro('名前')`）、名前付きショートカット（`Shortcut('名前')`、`config/shortcuts.yaml` と同梱の `data/shortcuts/`）、VS Code 風修飾キー表現（`Cmd + Q`）、エイリアス（`Tab`, `!`）
- decompile → compile で 16bit 値が元と一致する

## Architecture

```
Interface       CLI（bin/cornix → Interface::Cli::Main）・MCP サーバー（Interface::Mcp::Server）・エディタのサーバー（Interface::EditorServer、cornix serve）
Application     ユースケース（Compile / Decompile / Validate / Cleanup / RenameFiles / SuggestRenames / Device* / Editor::*）と Environment（DI）
Mapping         KeycodeCatalog / KeycodeCodec / KeycodeNotation / VialNotation / QmkNotation / MacroCodec / ProfileMapper / QmkSettingCatalog / ShortcutCatalog / AppIconCatalog / KeyDisplay / CandidateCatalog
Planning        ImageDiff / Change / Plan
Domain          Profile 集約と値オブジェクト（Keycode, ModifierSet, LayerRef, Layer, Macro, TapDance, Combo, PositionMap, ...）。I/O なし
Image           DeviceImage（16bit 値とバイト列のまま）。I/O なし
Storage         ConfigRepository（config/*.yaml）/ VilFile（layout.vil）/ SnapshotStore / ConfigEditor / DecompileLock / YamlDocument / TextEdit / FileSource / FileVersion
Device          HidBridge / Protocol / Session / Reader / Planner / Writer
```

```
compile    config/ ─ConfigRepository→ Profile ─ProfileMapper→ DeviceImage ─VilFile→ tmp/build/layout.vil
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
  qmk_settings.yaml QSID・名前・グループ・幅・型と、エディタに出す説明（description）・既定値（default。RMK 0.8.3 の値）
  dangerous_keycodes.yaml  実機に書き込まないキーコード
  unsupported_keycodes.yaml  Cornix が対応していないとみられるキーコード（validate などで警告。書き込みは止めない）
  shortcuts/*.yaml  同梱のショートカット（cornixhub の一覧。Shortcut('アプリ:カテゴリ:ラベル') で参照）
  shortcut_icons.yaml  同梱のショートカットのアプリ名 → アイコン ID（AppIconCatalog。SVG は拡張に同梱）
  keycode_categories.yaml  キー入力欄の候補の分類と、場面ごとに上に出すもの（CandidateCatalog。keycode/candidates が使う）
lib/cornix.rb       全ファイルを層の順に require
lib/cornix/
  domain/ image/ mapping/ planning/ storage/ device/ application/ interface/
  version.rb（Cornix::VERSION）, errors.rb, position_map.yaml（config/position_map.yaml のテンプレート）
ext/cornix_hid/     raw HID ブリッジ（Swift、tmp/cornix-hid にビルド）
editors/vscode/     VS Code 拡張（TypeScript。cornix serve を子プロセスで起動して JSON-RPC で話す。README.md に開発の手順と構成）
spec/               lib と同じ層の構成 + end_to_end_spec.rb / architecture_spec.rb / support/ / fixtures/（protocol/ は cornix serve の適合テストのデータ）
docs/               設計文書（README.md が一覧。architecture / domain-model / notation / validation / rename / device / tasks / background、vscode-extension/）
CHANGELOG.md        変更履歴（Keep a Changelog の形。リリースごとに項を作る）
config/             利用者の設定（生成物。main ブランチにはない）
```

## Testing

```bash
bundle install                                             # テスト用の gem（RSpec）を入れる
LANG=ja_JP.UTF-8 bundle exec rspec                         # すべて（キーボード不要）
LANG=ja_JP.UTF-8 bundle exec rspec spec/mapping            # 層ごと
LANG=ja_JP.UTF-8 bundle exec rspec spec/end_to_end_spec.rb # compile / decompile の一致

cd editors/vscode && npm ci && npm run typecheck && npm test  # VS Code 拡張の型検査と単体テスト（vitest。VS Code なしで動く）
npm run test:integration       # 拡張の統合テスト（VS Code をダウンロードして動かす。:ruby を付けると本物の cornix serve で）
```

- `spec/end_to_end_spec.rb`: `spec/fixtures/test_config` と `spec/fixtures/authors_config` を compile し、
  保存した `layout.vil` / `authors_baseline.vil` と 16bit 値で一致すること、decompile → compile で戻ること
- 旧実装の結果は `spec/fixtures/expected/` に保存してあり、それと比べる
- 実機の代わりに `spec/device/fake_rmk_device.rb`（RMK 0.8 の応答を模したもの）を使う
- `cornix serve` の約束は `spec/fixtures/protocol/` のデータで確かめる（Ruby は `spec/interface/editor_server/conformance_spec.rb`、拡張の偽のサーバーも同じデータの一部を vitest で流す）。CI は `.github/workflows/rspec.yml`（`rspec`）と `vscode.yml`（`node`）

### Round-trip check（手元の layout.vil で）

```bash
mv config config.backup
cp ~/Downloads/layout.vil tmp/layout.vil
cornix decompile && cornix compile
ruby bin/diff_layouts       # tmp/layout.vil と tmp/build/layout.vil を 16bit 値で比較 → === ✓ FILES ARE IDENTICAL ===
```

## Key Design Decisions

- **キーコード表**: 名前付きのキーコードだけを `data/keycodes.yaml` に持ち、`MO(n)` / `LT(n, kc)` / `LSFT(kc)` など引数付きは
  `KeycodeCodec` の定数とビット演算で組み立てる。別名は `data/aliases.yaml`（重複は読み込み時にエラー）
- **.vil の表記**: `VialNotation#format` は Vial Web の中身の vial-gui 0.7.5 が Cornix の .vil に保存する表記と同じ。Vial に名前のない値（LAG(kc) など 0.7.5 より後の名前、枠を超える MO(10) / M32 なども）は `0xHHHH`
- **decompile の正規形**: 別名 → 修飾キー式（`Ctrl, Option, Shift, Command` の順）→ 関数形式 → `0xHHHH`。
  参照は `Macro('名前')` / `TapDance('名前')`、設定は名前の形
- **修飾キー**: `Domain::ModifierSet` は左右どちらか一方。左右の混在はエラー
- **知らない値は落とさない**: 解釈できない 16bit 値は `Keycode::Raw`、.vil の未対応項目は `DeviceImage#meta` で往復させる
- **Position Map**: テンプレート `lib/cornix/position_map.yaml` → 利用者版 `config/position_map.yaml`。
  座標変換は `Domain::PositionMap` だけが行う
- **rename**: 名前参照はテキスト置換で書き換え、変更の前後の compile 結果（16bit 値）を比べて違えば元に戻す
- **cleanup / Environment**: 場所は `Application::Environment#root`（既定はリポジトリのルート）から決まる。カレントディレクトリに依存しない
- **設定ディレクトリの指定**: `Application::Workspace.resolve` が `--config` > `CORNIX_CONFIG` > `--profile NAME`（profiles/NAME）>
  カレントから親へたどった `.cornix.yml` > `<リポジトリ>/config` の順で決める。CLI は `Environment.for(workspace)` で作る。
  `<root>/config` 以外では tmp を `tmp/profiles/<名前>/`（profiles/ の外はパスのハッシュ付き。compile の出力はその下の
  `build/layout.vil`）に分ける。`.cornix.yml` の読み書きは `Storage::SettingsFile`。
  `cornix init` が設定ディレクトリ（指定がなければ `profiles/default`）と（必要なら）`.cornix.yml` を作り、デバイスか `--from` の .vil から設定を書く。
  `config/` は読むほうだけ後方互換で残す（新しく作るのは profiles/ の下）。`.cornix.yml` がなく中身のある `config/` があるところでは、
  指定なしの init は使う設定が黙って変わらないように止める。

- **バージョンとリリース**: バージョンは `lib/cornix/version.rb` の `Cornix::VERSION`（`cornix --version` と MCP の serverInfo が使う）。
  利用者に見える変更は `CHANGELOG.md` の `[Unreleased]` に足し、リリースのときに版の項へ移して `vX.Y.Z` のタグと GitHub Release を作る

## Troubleshooting

- **decompile が止まる**: `config/layers/` か `config/macros/` にファイルがある。退避するか `cornix cleanup`（ロックがあれば `-f`）
- **Round-trip check が失敗する**: `ruby bin/diff_layouts` で差分の場所を確認
- **テストが失敗する**: `LANG=ja_JP.UTF-8` を付けているか確認。`bundle exec rspec --format documentation` で詳細
- **依存の向きの違反**: `spec/architecture_spec.rb` の失敗は層の依存の向きの誤り（docs/architecture.md の表を参照）

## References

- [QMK Keycodes](https://docs.qmk.fm/keycodes)
- [Vial Documentation](https://get.vial.today/)
- [QMK Firmware](https://docs.qmk.fm/)
