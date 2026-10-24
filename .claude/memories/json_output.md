# --json（issue #26）で決めたこと

- 結果の Hash は各結果の `#to_h`（キーは文字列）と `Application::Serialize` の部品で作る。CLI の `--json`（`Command#emit`）と MCP の 2 つ目の `content` が同じものを使う。新しい結果を足したら `#to_h` も足す
- `--json` のとき標準出力は JSON 1 つだけ。エラーも標準出力に `{ "error" }`（標準エラー出力には出さない）。終了コードは `--json` なしと同じ。`--json` の有無は `GlobalOptions.json?` で extract より先に見る（共通のオプションの誤りも JSON にするため）
- 設定ディレクトリを使うコマンドは「設定: …」の行の代わりに `config`（`Command#with_config`）を先頭に入れる
- 書き込むコマンドは y/N を出せないので `--yes` 必須。確かめるのはキーボードを開く前（apply は compile の前）。`cleanup -f`・rename・mcp・serve は対象外でエラー
- status は issue の案と違い `{ config, compile, diff }`（検証の結果も返すため）
- `ReadResult#to_h` は保存したとき `{ path }` だけ（MCP の `save_path` で数十 KB の vil を流さないため）
- テスト: `spec/interface/cli/json_option_spec.rb`。macOS では `top_level_commands_spec.rb:144`（#87 由来、`/var` と `/private/var`）が失敗する
