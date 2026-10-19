# VS Code 拡張の仕様

cornix-layout のプロファイル（設定ディレクトリ）丸ごとを 1 画面で構造化して見せ、補完つきで編集できる VS Code 拡張を作る。
仕様は 2026-10-19 の相談ですべて決まり、まず自分用の v0.1 から実装する。決定の理由は [adr.md](adr.md)、版の割り振りは [roadmap.md](roadmap.md)、
バックエンドとのやりとりは [protocol.md](protocol.md)。

## 背景と目標

キーマップの編集はふだん Claude 経由だが、素早く手で直したいときに、候補から選びながら編集できるようにしたい。

- 対象: guccyon/cornix-layout の設定ファイル（`layers/` `macros/` `tap_dance/` `combos/` `shortcuts.yaml` `settings/qmk_settings.yaml` `metadata.yaml` `position_map.yaml`）
- とくに助けたいもの: 同梱のショートカット（`data/shortcuts/` の 27 アプリ、`Shortcut('アプリ:カテゴリ:ラベル')`）と、それを元にしたマクロ（`macros/` の `preset:`）
- 線引き: リッチにしすぎない。それ以上の操作は Vial を使う
- 利用者: まずは作者本人。母艦（cornix の Ruby が動く Mac）で使う

## 仕様

プロファイル丸ごとを扱う専用の編集画面（Webview）を、Ruby のバックエンドと JSON-RPC でつなぐ。

### 画面

- 入口: コマンド「Cornix: プロファイルを開く」と、左のアクティビティバーのアイコン。`profiles/` に複数あるときは開くときに選ぶ（`.cornix.yml` の既定を初期値に）
- 2 ペイン: 上に `position_map` をキーボードの形で描いた図、下に構造化した編集画面。図のキーをクリックすると下の該当項目へ移動する
- キーボード図の物理配置（キーの座標）は Cornix 専用として拡張に固定で持ち、`position_map.yaml` の論理位置と組み合わせる
- 当面は下を「レイヤーごと」に並べ、選んでいるレイヤーを上下で共有する
- 画面の言語は日本語だけ

### 作り

- Ruby のバックエンド: `cornix` に常駐のサブコマンドを足し、標準入出力の JSON-RPC で話す。リクエストの例は、プロファイルを構造で読む、候補を引く、変更を書き込む、保存前の状態で検証する
- 拡張はこのリクエストだけで Ruby と話し、`cornix` コマンドを直接叩かない
- 保存: 画面の変更は未保存（dirty）の状態として持ち、Ctrl+S で保存する。元に戻す・未保存の表示は VS Code の仕組みに乗せる
- 書き戻しは YAML を作り直さず、変わった値の部分だけを書き換える（手で書いたコメント・並び・注記を壊さない。`Storage::ConfigEditor#update_fields` と同じ考え方）
- 外での変更: 開いている間に Claude やテキストエディタがファイルを変えたら、未保存の変更がなければ黙って読み直し、あればどちらを残すか聞く
- `cornix` の場所: 設定 `cornix.path`。既定はワークスペースの `bin/cornix`、なければ PATH。見つからなければ設定を開くボタン付きで知らせる
- Webview: 素の TypeScript。部品が増えたら Lit などの軽いライブラリを足す。ビルドは esbuild、テストは vitest と @vscode/test-electron（仮の決め。作り始めてから変えてよい）

### アイコン

- 優先は割り当て済みのキーのアイコン（図や一覧での見分けやすさ）。候補の行のアイコンはその次
- 同梱のショートカットはアプリのアイコン。`preset:` で作ったマクロを割り当てたキーにも元のアプリのアイコン
- `shortcuts.yaml` の自分のショートカットはアイコンなし
- 対応表: `data/` の別ファイルにアプリ名 → アイコン ID（例 `simple-icons:figma`）だけを持ち、全アプリに対応があるかをテストで確かめる。SVG とライセンス表記は拡張に同梱
- 素材: [Simple Icons](https://simpleicons.org/)（CC0。27 アプリ中 15）→ [Material Icon Theme](https://github.com/material-extensions/vscode-material-icon-theme)（MIT。VS Code・Word・PowerPoint）→ 残り 9 個（CleanShot, Clip Studio, Excel, Fusion 360, Illustrator, Photoshop, Premiere, Slack, Windows）は頭文字の色付きバッジを自前で作る

### 検証

- 編集画面: 値を入れたとき（onchange）に検証し、入力欄をエラーにしてメッセージを添える。未対応キーは警告
- 原因が別の項目にあるエラー（消したマクロへの参照など）は、参照している側に出す
- テキストで開いているとき: 同じ結果を波線で出す（あると親切、の扱い）
- 今のコードに足りないもの: 保存前の状態で検証する入口（今の validate は保存済みのファイルを読む）、波線のための行と列（`Storage::DiagnosticLocator` は「ファイル: キーの位置」まで）

### 範囲

- エディタから実行できるのは compile / validate / status（読むだけ）。実機への書き込み（apply / restore）は入れない
- 項目（マクロなど）の追加・削除・名前の変更は v0.2 以降（名前の変更は `cornix rename` を使う）
- 置き場所はこのリポジトリの `editors/vscode/`。CI は変更したパスで Ruby と Node を分ける
- 配布は、まず自分用に手元で .vsix を入れる

## 入力と補完

キーを入れる場所はどこも同じ「キー入力欄」を使い、ファイルの種類と項目ごとに「出す候補の種類」と「並び順」だけを変える。
版の割り振りはたたき台で、版ごとに足したり削ったりする。

### キー入力欄の候補の種類

| 種類 | 例 | 出どころ | 版 |
|---|---|---|---|
| 基本キー・修飾キー単体 | `A` `;` `Enter` `F12` `LShift` | `data/keycodes.yaml` と `data/aliases.yaml` | v0.1 |
| 修飾キー式 | `Shift + Command + P` | `KeycodeNotation` | v0.1（打つ）・v0.2（組み立て欄） |
| レイヤー操作 | `MO(1)` `TG(3)` `OSL(9)` | `KeycodeCodec` | v0.1 |
| レイヤー＋キー・Mod-Tap | `LT(2, Escape)` `RSFT_T(Up)` | `KeycodeCodec` | v0.2（組み立て欄） |
| マクロ・タップダンス | `Macro('Bracket Pair')` | そのプロファイル | v0.1 |
| 自分のショートカット | `Shortcut('前のタブへ')` | `shortcuts.yaml` | v0.1 |
| 同梱のショートカット | `Shortcut('VS Code:基本操作:コマンドパレット')` | `data/shortcuts/`（アプリ → カテゴリ → ラベルでも辿れる） | v0.1 |
| メディア・マウス・特殊 | `VolumeUp` `KC_NO` `KC_TRNS` | `data/keycodes.yaml` | v0.1 |
| 直接の値 | `0x7E40` | — | v0.1（`0x` と打ったときだけ） |

- `data/dangerous_keycodes.yaml` のキーは出さない。`data/unsupported_keycodes.yaml` のキーは警告の印を付けて下に並べる
- 検索は正規の名前・別名・QMK 名・記号そのもの・ショートカットの日本語ラベルとアプリ名に当てる。部分一致で、前方一致と完全一致を上に（あいまい検索は v0.3）
- 選んだ候補は decompile の正規形で書く。手で打った表記は解釈できればそのまま残す
- キーにマウスを載せると、何に解釈されるか（Shortcut の中身、マクロの手順など）を出す（v0.1）
- 2 役のキー（`LT` など）はタップとホールドを上下に分けて描く

### ファイルの種類ごと

| ファイル | 項目 | 候補 | 上に出すもの | 版 |
|---|---|---|---|---|
| `layers/` | 各キー | 全部 | 基本キー | v0.1 |
| `layers/` | エンコーダの押し込み・回転 | 全部 | メディア・マウスホイール・音量 | v0.1 |
| `layers/` | 注記 | 1 行の文字 | — | v0.2 |
| `macros/` | tap / down / up のキー | 基本キー・修飾キー・メディア（「すべて出す」の切り替え付き） | — | v0.2 |
| `macros/` | delay / text | 数値（ミリ秒）・ASCII の文字 | — | v0.2 |
| `macros/` | `preset:` | 手順の定義がある同梱ショートカット（アイコン付きの階層選択） | — | v0.2 |
| `tap_dance/` | 4 つの動作 | 全部（自分自身への参照は除く） | 基本キー・レイヤー操作 | v0.2 |
| `tap_dance/` | tapping_term | 数値（QMK 設定の値を薄く添える） | — | v0.2 |
| `combos/` | 同時に押すキー（最大 4） | 基本キー・修飾キー | ベースレイヤーにあるキー | v0.2 |
| `combos/` | 出すキー | 全部 | マクロ・基本キー | v0.2 |
| `shortcuts.yaml` | 値 | 全部から `Shortcut(...)` を除く | — | v0.2 |
| `settings/qmk_settings.yaml` | 各設定 | 整数は数値、真偽値はチェックボックス（説明と既定値付き） | — | v0.1 |
| `metadata.yaml` `position_map.yaml` | — | 読むだけで表示 | — | v0.1 |

- マクロのキーを絞るのは推定に基づく。読み込みはどのキーコードも受け付けるが、レイヤー操作や参照をマクロで送っても期待どおり動かないと考えられる
- レイヤー操作の候補にはレイヤーの名前を添える（`MO(1)  Symbols`）
- QMK 設定の説明文は `data/qmk_settings.yaml` に足す（今は名前と型だけ）
