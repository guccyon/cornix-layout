# リファクタのタスクと契約

作業ブランチは `refactor/domain-architecture`。各タスクは `<repo-root>/<ブランチ名>` の worktree で作り、
終わったものから `refactor/domain-architecture` にマージする。同じフェーズのタスクは並列に進める。
**ここに書いた公開メソッドの形（契約）は勝手に変えない。** 変える必要があれば作業報告で提案する。

## 共通ルール

- 旧コード（`lib/cornix/models/`, `converters/`, `loaders/`, `writers/`, `compiler.rb`, `decompiler.rb`, `keycode_parser.rb`,
  `modifier_expression_compiler.rb`, `position_map.rb`, `model_validator.rb`, `device/keyboard.rb`, `device/keycodes.rb`,
  `device/macro_codec.rb`, `device/mcp_server.rb` など）と旧 spec はフェーズ 3 まで消さない・変えない。新コードは新しいファイルに書く。
- コミット前に `LANG=ja_JP.UTF-8 bundle exec rspec` がすべて通ること。新しいクラスには spec を書く。
- 正解の基準: authors-keymap の設定を旧コードで compile した結果（`tmp/baseline/layout.vil`、16bit 値で一致すればよい）と、
  旧コードの振る舞い（旧 spec と旧実装）。旧実装のバグ（docs に書いたもの）は直してよいが、直したことを報告に書く。
- [architecture.md](architecture.md) の方針・依存の向き・コード規約を守る。

## フェーズ 0（完了）

`errors.rb`、`lib/cornix.rb`、`data/*.yaml`、`Domain::Keycode::*`、`Domain::ModifierSet`、`Domain::LayerRef`、`Domain::Checks`、
`Image::DeviceImage` と付随 Record、`Mapping::KeycodeCatalog`（+Loader）、`Mapping::KeycodeCodec`、`Mapping::References`、
`Mapping::QmkSettingCatalog`、`spec/architecture_spec.rb`。

```ruby
codec = Mapping::KeycodeCodec.new(catalog = Mapping::KeycodeCatalog.default)
codec.decode(Integer) #=> Domain::Keycode（例外を出さない。最後は Raw）
codec.encode(Domain::Keycode) #=> Integer（表せなければ UnknownKeycode）
catalog.lookup(name) / code_for_name / code_for_alias / name(code) / vial_name(code) / preferred_alias(code) / aliases_for(code)
catalog.basic?(code) / quantum?(code) / dangerous?(code) / dangerous_reason(code)
catalog.unsupported_keycodes #=> { 値 => '名前: 理由' }（data/unsupported_keycodes.yaml。Domain::Capabilities#unsupported_keycodes に渡す）
refs = Mapping::References.new(macros: { '名前' => index }, tap_dances: { '名前' => index }, shortcuts: { '名前' => keycode },
                               preset_shortcuts: { 'アプリ:カテゴリ:ラベル' => keycode })
refs.macro_index(name) / tap_dance_index(name) / macro_name(index) / tap_dance_name(index)   # Mapping::References::NONE
refs.shortcut(name) #=> Keycode（shortcuts、なければ preset_shortcuts）/ shortcut_name(keycode) #=> shortcuts のちょうど 1 つと一致すればその名前
Mapping::ShortcutCatalog.default.texts #=> { 'アプリ:カテゴリ:ラベル' => 表記 }（data/shortcuts/*.yaml）/ library(notation) #=> Domain::ShortcutLibrary
catalog.macro_names / preset_names #=> 複数の手順の定義の名前 / preset: に書ける名前すべて
catalog.preset(name, notation) #=> [Domain::MacroStep]（macros/ の preset: の手順。1 シーケンスの定義は押して離す手順）/ nil
refs.preset_macro?(name)        # 同梱の複数の手順の定義か（Shortcut('名前') で使われたときの案内用。References.new(preset_macros: [...])）
Mapping::QmkSettingCatalog.default.fetch(qsid) / find(group, name) / all  #=> Definition(qsid, name, group, width, type)
```

## フェーズ 1（並列）

### p1-notation（ブランチ `refactor/p1-notation`）

`lib/cornix/mapping/keycode_notation.rb`（+ `keycode_notation/parser.rb`, `formatter.rb`, `modifiers.rb`）、`lib/cornix/mapping/vial_notation.rb`

```ruby
notation = Mapping::KeycodeNotation.new(catalog:, codec:)       # 既定値は default / KeycodeCodec.new(catalog)
notation.parse(text, references: Mapping::References::NONE)       #=> Domain::Keycode（解析できなければ UnknownKeycode、メッセージは利用者向け）
notation.format(keycode, references: Mapping::References::NONE)   #=> String（decompile が書く正規形）

vial = Mapping::VialNotation.new(catalog:, codec:)
vial.parse(text)    #=> Domain::Keycode（.vil の文字列。旧 Device::Keycodes#encode が受け付けたものすべて）
vial.format(keycode) #=> String（vial-gui 0.7.5 が Cornix の .vil に保存する表記。旧 Device::Keycodes#decode とは LAG(kc)・M32〜 などが 16 進になる点だけ違う）
vial.parse_code(text) #=> Integer / vial.format_code(Integer) #=> String
```

- `KeycodeNotation#parse` は旧コード（`KeycodeParser`, `KeycodeConverter`, `ModifierExpressionCompiler`, `ReferenceConverter`,
  `KeycodeValue` など）が受け付けた表記をすべて受け付ける: 別名、QMK 名、関数形式（`LSFT(KC_1)`, `LT1(Space)`, `LT(1, KC_A)`,
  `MO(3)`, `LGUI_T(KC_LANG2)`, `SGUI(...)`, `HYPR(...)`, `TD(4)`, `M2` など）、修飾キー式（`Cmd + Shift + A`, `Command + Plus`）、
  名前参照（`Macro('名前')`, `TapDance('名前')`, 番号指定）。`Combo(...)` は .vil で表せないので UnknownKeycode にしてよい。
- 修飾キー式の修飾名（Command / Cmd / Option / Shift / Ctrl ...）は `keycode_notation/modifiers.rb` の定数に持つ。
- 不変条件 `parse(format(k), references:) == k`。
- `format` の正規形: 別名があれば別名（`catalog.preferred_alias`）、名前参照があれば `Macro('名前')` / `TapDance('名前')`、
  修飾付きで別名がなければ修飾キー式、その他は関数形式（引数は別名）、表せない値は `0xHHHH`。
- `VialNotation#format` は全 16bit 値で旧 `Device::Keycodes#decode` と同じ文字列を返すこと（spec で全数比較する）。

### p1-domain（ブランチ `refactor/p1-domain`）

`lib/cornix/domain/` の集約と値オブジェクト。

```ruby
Domain::KeyPosition(hand: :left|:right, row:, col:)        # 論理位置（docs/domain-model.md の「座標系」の論理位置）
Domain::PositionMap.from_h(hash)                           # position_map.yaml の Hash。形式は現行のまま
  #position(hand_key, group_key, symbol) #=> KeyPosition | nil   # ('left_hand', 'row0', 'tab')
  #symbol(position) #=> [group_key, symbol] | nil
  #matrix(position) #=> [row, col]                         # layout.vil の物理座標（右手の反転、行 +4、親指）
  #position_at(row, col) #=> KeyPosition | nil
  #encoder_push_matrix(:left|:right) #=> [row, col]
  #positions #=> [KeyPosition]                             # 定義順
Domain::EncoderBinding(push:, ccw:, cw:, notes: { push: String, ... })   # 各 Keycode。notes は省略可
Domain::Layer(index:, name:, description:, keys: { KeyPosition => Keycode }, encoders: { left: EncoderBinding, right: EncoderBinding },
              notes: { KeyPosition => String })            # notes（注記）は割り当てのある位置だけ。省略可
Domain::MacroStep::Tap / Down / Up(keys: [Keycode]), Delay(ms:), Text(content:)   # KEY_ACTIONS: action の名前 → Tap / Down / Up
Domain::Macro(index:, name:, description:, steps:, preset: nil)   # preset は同梱のショートカットの名前（デバイスにはない。書き戻し用）
Domain::TapDance(index:, name:, description:, on_tap:, on_hold:, on_double_tap:, on_tap_hold:, tapping_term:,
                 notes: { on_tap: String, ... })
Domain::Combo(index:, name:, description:, trigger_keys: [Keycode], output_key: Keycode, notes: { output_key: String })
# 注記（notes）は設定ファイルにだけある「何のための割り当てか」のメモ。ProfileMapper#to_image は使わない
Domain::QmkSettings(values: { qsid(Integer) => Integer })
Domain::Metadata(...)                                      # config/metadata.yaml の内容（未使用の項目も保持）
Domain::Capabilities(layers:, macros:, tap_dances:, combos:, ...)  # Cornix の上限。定数 CORNIX
Domain::Diagnostic(severity: :error|:warning, path: String, message: String)
Domain::Profile(metadata:, settings:, position_map:, layers:, macros:, tap_dances:, combos:, shortcuts: ShortcutLibrary::EMPTY)
  #diagnostics(capabilities = Capabilities::CORNIX) #=> [Diagnostic]
  #references #=> Mapping に依存しない形で名前 → 番号（macro_names / tap_dance_names の Hash）と shortcuts（名前 → Keycode）を返す
```

- 旧 `models/` と `Validatable` の検証内容（範囲、必須、重複、件数の上限、参照先の存在）を構造検証と `diagnostics` に移す。
- `path` は `layers[0].left_hand.row0.tab` のようなモデル内のパス。ファイル上の位置への写像は Storage が行う。

### p1-device（ブランチ `refactor/p1-device`）

`lib/cornix/mapping/macro_codec.rb`、`lib/cornix/planning/`、`lib/cornix/device/` の新ファイル（session.rb, reader.rb, writer.rb など）

```ruby
Mapping::MacroCodec.new.encode_all([[Image::MacroAction]]) #=> String(バイト列) / decode_all(buffer, count) / encode / decode
Device::Session.open(...) / Device::Reader#read #=> Image::DeviceImage（.vil で -1 の位置は nil）
Planning::ImageDiff.new(current:, target:).changes #=> [Planning::Change]   # Change はデータだけ
Planning::Plan(changes:, warnings:)#token / #empty?
Device::Writer#apply(plan)                                 # 書いたあと読み直して検証
```

- 旧 `Device::Keyboard` の振る舞い（diff の対象、拒否するキーコード、token、バックアップの前提、警告）を保つ。
  拒否するキーコードは `KeycodeCatalog#dangerous?`、設定の幅は `QmkSettingCatalog` を使う。
- `hid_bridge.rb` と `protocol.rb` はそのまま使ってよい（定数を data から引くように変えるのは可）。旧 `keyboard.rb` / `keycodes.rb` /
  `macro_codec.rb` / `mcp_server.rb` は残す（フェーズ 3 で削除）。

## フェーズ 2（並列）

### p2-mapper（`refactor/p2-mapper`）: `Mapping::ProfileMapper`

```ruby
mapper = Mapping::ProfileMapper.new(codec:, capabilities: Domain::Capabilities::CORNIX)
mapper.to_image(profile)   #=> Image::DeviceImage   # 旧 compile と同じ配置・パディング（未使用の TD / コンボ / マクロ）
mapper.to_profile(image, position_map:, previous: nil) #=> Domain::Profile   # previous があれば名前や説明、キーコードが同じ場所の注記を引き継ぐ
```

### p2-storage（`refactor/p2-storage`）: `Storage::ConfigRepository`

```ruby
repo = Storage::ConfigRepository.new(dir, notation:, settings_catalog:, shortcut_catalog: Mapping::ShortcutCatalog.default)
repo.load    #=> Domain::Profile（問題はすべて集めて Storage::InvalidConfig(problems) で送出）
repo.save(profile) #=> [書いたファイル]   # decompile。ファイル名の規則は旧 YamlWriter と同じ
```

- 読む順は metadata → position_map → macros → tap_dance → shortcuts（ここで References を作る）→ settings → layers → combos。
- ファイル形式は現行のまま（`.yaml` / `.yml` の両方）。YAML は safe_load、キーの重複はエラー。

### p2-vil（`refactor/p2-vil`）: `Storage::VilFile`、`Storage::BackupStore`

```ruby
Storage::VilFile.new(vial:).read(path) #=> Image::DeviceImage / #write(image, path) / #parse(json_string) / #dump(image)
```

- 出力の JSON は旧 `VialWriter` と同じ形（キーの順、`JSON.pretty_generate`）。

## フェーズ 3

### p3-interface（`refactor/p3-interface`、完了）: デバイス操作のユースケースと CLI / MCP

### p3-switch（`refactor/p3-switch`）: 残りのコマンドの移行と旧コードの削除

```ruby
env = Application::Environment.new(root: dir, claude: fake)     # repository / config_editor / decompile_lock / claude
Application::Validate.new(env).call          #=> ValidationReport(errors:, warnings:, profile:)（config/ がなければ ConfigNotFound）
Application::Compile.new(env).call(output: nil)   #=> CompileResult(report:, path:, image:)
Application::Decompile.new(env).call(input: nil)  #=> DecompileResult(status: :decompiled | :input_missing | :config_exists, ...)
Application::Cleanup.new(env).call(force: false, confirm: ->(lock) { ... })   #=> CleanupResult(status:, lock:, deleted:)
Application::RenameFiles.new(env).check(plan) / #call(plans, verify: true)    #=> RenameOutcome
Application::SuggestRenames.new(env).call / #load_plans / #cleanup            #=> RenameSuggestions
```

- `bin/cornix` は `Interface::Cli::Main`。`bin/subcommands/` と旧コード・旧 spec は削除した。
- 旧コードを正解にしていた spec は、旧コードで求めた値を `spec/fixtures/expected/` に保存して比べる。
  authors-keymap の config とその compile / decompile 結果は `spec/fixtures/authors_*` に複写してあり、
  `spec/end_to_end_spec.rb` が CI でも compile / decompile の一致を確かめる。
