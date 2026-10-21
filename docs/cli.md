# コマンドの体系と `cornix self`

`cornix` のサブコマンドの並べ方の方針と、cornix 自体をほかのプログラム（VS Code 拡張など）から見つけられるようにする
`cornix self` の設計（issue #59）。`cornix self` は設計だけで、まだ実装していない。使い方は [README.ja.md](../README.ja.md)。

## サブコマンドの体系

| 階層 | 形 | コマンド |
|---|---|---|
| 上の階層 | いまのプロファイルに対する動詞 | `init` `pull` `status` `apply` `restore` `validate` `rename` `compile` `decompile` `cleanup` |
| グループ | プロファイル以外のものの「名詞 動詞」 | `device <動詞>`（実機の直接操作）、`snapshots [list]`（スナップショット）、`self <動詞>`（cornix 自体） |
| ほかのプログラムが起動するもの | 名前を変えない | `serve`（`--device` も）、`mcp` |

- 毎日使うものは短く打てるように上の階層に置く。プロファイル以外を相手にするものはグループにまとめ、上の階層を増やさない
- `snapshots` はいまの一覧を `snapshots list` の省略形とする。あとで `show` や `prune` などを足せる（足すまでは今のまま）
- `serve` と `mcp` は `.mcp.json` や拡張の起動の手順が名前を持っているので変えない
- 既存のコマンド名は変えない（互換を壊さない）。変えるのは `cornix help` の一覧の見せ方だけで、用途ごとの見出しで分ける
  （日々の操作 / 設定の編集 / Vial を使う場合 / 実機の直接操作 / ほかのプログラムから使う / cornix 自体）。
  見出しは各コマンドのクラスに持たせ（`Command.group` など）、`Main::COMMANDS` の並びは見出しの中の順にする

### やめた案

- **グループ名 `extension`（`cornix extension configure`）**: VS Code 専用に見えるが、同じことが MCP のクライアントやターミナルにも要る
- **グループ名 `setup`**: `init`（プロファイルを作る）と区別しにくい。`self` は rustup self や poetry self と同じく「ツール自体」を指す
- **`serve` と `mcp` を `server editor|device|mcp` にまとめる**: 登録済みの設定を壊すだけで得るものが少ない

## `cornix self`: cornix 自体の場所を通す

### 問題

拡張は `cornix` を、設定 `cornix.path` → ワークスペースの `bin/cornix` → `PATH` の順に探す（`editors/vscode/src/server/locateCornix.ts`）。
プロファイルを別のリポジトリに置く使い方（README の「利用の形」の B）では 2 番目で見つからず、`cornix.path` に絶対パスを手で書くことになる。

`PATH` に `bin/cornix` への symlink を置く手順（README の「取得する」）もあるが、これだけでは足りない。`bin/cornix` は `#!/usr/bin/env ruby` なので、
Dock から起動した VS Code のようにログインシェルから環境を読むと mise や rbenv の Ruby が `PATH` の後ろに回り、macOS の `/usr/bin/ruby`（2.6）が選ばれて落ちる
（`.claude/memories/vscode_extension.md`。いまは editors/vscode/README.md で、Ruby を決めたスクリプトを手で作る回避を案内している）。

また、ユーザー設定の `cornix.path` が古い worktree を指したままだと、気づかずに古いコードで動く（PR #54 の別名 `SingleQuote` が「不明なキーコード」になった件）。

### 決めたこと

Ruby を固定した小さなスクリプト（shim）を `PATH` の通った場所に置く。拡張は変えずに 3 番目（`PATH`）で見つける。

```sh
#!/bin/sh
# cornix self link が作成（cornix 1.0.0）。作り直すときは cornix self link、外すときは cornix self unlink
exec '/Users/me/.local/share/mise/installs/ruby/3.4.1/bin/ruby' '/Users/me/src/cornix-layout/bin/cornix' "$@"
```

| コマンド | 内容 |
|---|---|
| `self link [--dir DIR] [--print] [--yes]` | 実行しているこの `bin/cornix` と、それを動かしている Ruby で shim を作る |
| `self unlink [--dir DIR]` | `self link` が作った shim を消す（目印の行がないファイルは消さない） |
| `self status` | この cornix の場所・版・約束の版、動かしている Ruby、shim の場所と指す先、`PATH` で最初に見つかる `cornix`、クローンのブランチとコミット |

- **書く中身**: `bin/cornix` は実行中のファイルの実パス（`File.realpath`）、Ruby は `RbConfig.ruby`（mise の shim から動かしても、版の付いた実体のパスになる）。
  パスはシングルクォートで囲み、中の `'` はエスケープする。2 行目のコメントが目印（`unlink` と上書きの判断に使う）
- **置き場所**: 既定は `~/.local/bin`。`PATH` の各要素を展開・実パスにして比べ、通っているときだけ書く。通っていなければ書かずに、
  `PATH` への足し方（`~/.zprofile` に `export PATH="$HOME/.local/bin:$PATH"`）を表示して終了コード 1。`--dir DIR` は指定どおりに書き、`PATH` になければ警告する。
  `/bin` は macOS の SIP で書けず、`/usr/local/bin` は Apple Silicon の Mac では sudo が要ることが多いので既定にしない
- **すでにあるとき**: 目印のある shim か `bin/cornix` を指す symlink（README の古い手順）なら、前後の指す先を表示して確認（y/N、`--yes` で省略。同じなら何もしない）。
  それ以外のファイルは上書きせずにエラー
- **`--print`**: 書かずに、置く場所と中身を表示する
- **`PATH` の順**: 置いたあと、`PATH` で最初に見つかる `cornix` が shim でなければ（Homebrew などの別の cornix が先にあるなど）警告する
- **Ruby を消したとき**: shim の Ruby がなくなるとシェルが「No such file」で落ちる。`self status` と拡張の起動の失敗の通知で `cornix self link` の実行し直しを案内する
- **Windows**: 対象外（拡張の `locateCornix` と同じ）

### 拡張の側

- 探す順（`cornix.path` → `bin/cornix` → `PATH`）は変えない
- 見つからないときの通知に、`cornix self link` の案内と「場所を選ぶ」ボタンを足す。ボタンはファイルを選ぶ画面を開き、選んだパスをワークスペースの設定の `cornix.path` に書く
  （`WorkspaceConfiguration.update` を使うので、settings.json の JSONC は VS Code が扱う。ユーザー設定に書かないのは #54 の件を繰り返さないため）
- 出力パネル「Cornix」の「起動します」の行に、どこで見つけたか（設定・ワークスペース・`PATH`）を足す（いまは場所と `serverInfo.version` だけ）

### やめた案

- **VS Code のユーザー設定 `cornix.path` を cornix が書く**（issue の最初の案）: settings.json は JSONC なので、コメントを壊さずに書くのが手間。
  場所が OS・派生版（Insiders・VSCodium・Cursor）・VS Code のプロファイルごとに違う。ユーザー設定の `cornix.path` が古い worktree を指していたのが #54 の原因で、同じ形を増やす
- **登録ファイル（`~/.config/cornix/command.json` に cornix と Ruby の絶対パスを書き、拡張が読む）**: できることは `PATH` の shim とほぼ同じで、拡張にも読む処理が要る。
  登録ファイルは、Jupyter の kernelspec やブラウザの Native Messaging のように、起動する側が `PATH` に頼れないときに使う形。
  VS Code はログインシェルの `PATH` を読むので要らない。置くとしても XDG では `~/.config` は利用者の書く設定の場所で、マシンごとの情報は `~/.local/state` か `~/.local/share` になる
- **`.cornix.yml` や `tmp/` に場所を書く**: `.cornix.yml` はコミットするのでマシンごとの絶対パスを置けない。`tmp/` はプロファイルごとに要り、掃除で消える
- **symlink だけ**: 上の Ruby の問題が残る
- **`code --install-extension` までまとめる**: .vsix はまだ手元で npm で作る。GitHub Release に .vsix を付けるようになってから考える

### 今後

- `self update`（クローンを `git pull` する）、MCP のクライアントに貼る設定（Ruby と `bin/cornix` の絶対パス入り）を表示する `self status --mcp` などを `self` に足せる
- 実装するときは README（英日）の「取得する」の symlink の手順と、editors/vscode/README.md の Ruby の回避を `cornix self link` に置き換える
