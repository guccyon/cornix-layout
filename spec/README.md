# RSpec テスト

```bash
LANG=ja_JP.UTF-8 bundle exec rspec                          # すべて
LANG=ja_JP.UTF-8 bundle exec rspec spec/domain              # 層ごと
LANG=ja_JP.UTF-8 bundle exec rspec spec/end_to_end_spec.rb  # compile / decompile の一致
```

- キーボードは不要（実機の代わりに `spec/device/fake_rmk_device.rb` を使う）。実機と通信するテストは書かない
- 実行順はランダム（`--seed` で再現できる）。メッセージが日本語なので `LANG=ja_JP.UTF-8` を付ける
- GitHub Actions（`.github/workflows/rspec.yml`）が push / pull request ごとに、`ruby -w` で `lib/cornix.rb`（とその下の全ファイル）を読み込み、`ruby -wc` で `bin/` の各ファイルを検査して、警告が出ないことを確かめてから実行する

## 構成

`spec/` は `lib/cornix/` と同じ層の構成にする（`lib/cornix/mapping/keycode_codec.rb` ↔ `spec/mapping/keycode_codec_spec.rb`）。

| ディレクトリ | 対象 | 主な内容 |
|---|---|---|
| `domain/` | `Domain::*` | 値オブジェクトの検証（`InvalidValue`）、`PositionMap` の座標変換、`Profile#diagnostics` |
| `mapping/` | `Mapping::*` | キーコード表・`KeycodeCodec`・`KeycodeNotation`（表記ごとの値と往復）・`VialNotation`（全 16bit 値で旧実装と同じ表記）・`MacroCodec`・`ProfileMapper` |
| `planning/` | `Planning::*` | `ImageDiff` の差分、`Plan` の token、マクロの一覧 |
| `storage/` | `Storage::*` | `ConfigRepository` の読み書きと問題の報告、`VilFile`、`BackupStore`、`ConfigEditor`、`YamlFile`、`DiagnosticLocator` |
| `device/` | `Device::*` | `Protocol` の範囲検査、`Session` / `Reader` / `Planner` / `Writer`、`HidBridge`（`CORNIX_HID_BRIDGE` で差し替え） |
| `application/` | `Application::*` | 設定のユースケース（Validate / Compile / Decompile / Cleanup）、rename、デバイスのユースケース、`Environment` |
| `interface/` | `Interface::*` | CLI（`Main` とコマンドの出力・終了コード）、MCP サーバー（ツール一覧と応答） |

層をまたぐもの:

- **`end_to_end_spec.rb`**: `test_config` / `authors_config` を `cornix compile` して、保存した .vil と 16bit 値で一致すること、
  .vil を decompile → validate → compile して元に戻ること。`bin/cornix`・`bin/diff_layouts`・`bin/rename_file` を子プロセスで実行する確認もある
- **`architecture_spec.rb`**: `lib/cornix` の各層が参照してよい層だけを参照していること（`docs/architecture.md` の表）

## 共通の道具

| ファイル | 内容 |
|---|---|
| `spec_helper.rb` | `lib/cornix` を読み込み、RSpec を設定する |
| `domain/support/domain_factories.rb` | Domain の値を作る helper（既定の position_map など） |
| `mapping/support/vil_image.rb` | 保存した 16bit 値（`fixtures/expected/*.values.json`）から `DeviceImage` を作る |
| `storage/support/storage_helpers.rb` | 一時ディレクトリへの設定の複写など |
| `application/support/config_root.rb` | shared context `config root`: 一時ディレクトリを root にした `Environment`、`FakeClaude`、fixtures の設置 |
| `application/device_environment_context.rb` | `FakeRmkDevice` を開く `device_opener` を渡した `Environment` |
| `device/fake_rmk_device.rb` | RMK 0.8 の Vial 応答を模したデバイス（ファームウェアがパニックする範囲外の書き込みは例外にする） |
| `planning/planning_images_context.rb` | 差分の spec で使う DeviceImage |

## fixtures

| パス | 内容 |
|---|---|
| `fixtures/test_config/` | 機能を一通り使う設定（10 レイヤー、マクロ・タップダンス・コンボ、修飾キー表現、参照、設定） |
| `fixtures/layout.vil` | `test_config` を旧実装で compile した結果（正解） |
| `fixtures/authors_config/` | authors-keymap ブランチの `config/` の複写（実際に使っているキーマップ） |
| `fixtures/authors_baseline.vil` | `authors_config` を旧実装で compile した結果（正解） |
| `fixtures/authors_decompiled_config/` | `authors_baseline.vil` を旧実装で decompile した結果（旧形式の設定も読めることの確認） |
| `fixtures/vial_keycodes_v6.yaml` | 旧 `lib/cornix/device/via_keycodes.yaml`（vial-gui から抽出した表）。`data/keycodes.yaml` との照合に使う |
| `fixtures/position_map.yaml` | position_map のサンプル |
| `fixtures/expected/` | 旧実装を消す前に、旧実装で求めて保存した期待値（下表） |

`fixtures/expected/`:

| ファイル | 旧実装 | 使う spec |
|---|---|---|
| `vial_codes.tsv.gz` | `Device::Keycodes` の全 16bit 値の decode / encode | `mapping/vial_notation_spec.rb` |
| `config_keycodes.yaml` | 設定ファイルの全キーコード文字列の値（値にできなかったものは null） | `mapping/keycode_notation_config_spec.rb` |
| `layout.values.json`, `authors_baseline.values.json` | .vil を 16bit 値にしたもの | `storage/config_repository_baseline_spec.rb` ほか |
| `macro_buffers.json` | `Device::MacroCodec` が書いたマクロのバイト列 | `mapping/macro_codec_spec.rb` |
| `fake_device_snapshot.json` | `Device::Keyboard` が FakeRmkDevice から読んだ状態 | `device/reader_spec.rb` |
| `mcp_tools.json` | `Device::McpServer` の tools/list と instructions | `interface/mcp/server_spec.rb` |

旧実装は削除済みなので、これらの期待値は作り直せない。振る舞いを意図的に変えるときは、変えた理由を spec とコミットに書いてから期待値を更新する。

## 書き方

- 新しいクラスには spec を書く。テスト用の値は fixtures か `domain_factories.rb` から作り、実機・ネットワーク・利用者のファイルには触れない
- ファイルを書くテストは `Dir.mktmpdir` の下で行う（`config root` の shared context を使う）
- コミット前に `LANG=ja_JP.UTF-8 bundle exec rspec` がすべて通ること
