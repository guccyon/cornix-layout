# 修飾キー表現（VS Code 風）

`Cmd + Q` のような表記を修飾キー付きのキーコードにする機能。利用者向けの説明は README の「修飾キー表現」。

## 実装の場所

- 解析: `Mapping::KeycodeNotation::Parser`（`lib/cornix/mapping/keycode_notation/parser.rb`）
  - 解釈の順: 文字列全体が別名・QMK 名 → 参照 → `M3` → `0xHHHH` → 修飾キー式（`修飾名 +` で始まる）→ 関数形式
  - 別名を先に見るので、`+`（`LSFT(KC_EQUAL)`）や `LCtrl` のような別名は修飾キー式より優先される
- 修飾名・修飾関数・MOD_ 定数の表: `Mapping::KeycodeNotation::Modifiers`（`keycode_notation/modifiers.rb`）
  - `EXPRESSION`（`Cmd` / `Command` / `Option` / `RCtrl` ...）、`FUNCTIONS`（`LCTL`, `C_S`, `SGUI`, `MEH`, `HYPR` ... → ビット）、
    `FUNCTION_ALIASES`（`LCS` → `C_S`, `LSG` → `SGUI` など）、`MOD_TAP_BITS`、`CONSTANTS`
- 値: `Domain::ModifierSet`（左右のどちらか一方 + ctrl / shift / alt / gui の 5bit）と `Domain::Keycode::Modified(mods, base)`
- 16bit 値: `Mapping::KeycodeCodec`（`mods.bits << 8 | base`）
- 書き出し: `Mapping::KeycodeNotation::Formatter`

## 規則

- 修飾キー式は ModifierSet で組み立てる（文字列で `LCS(...)` などを作らない）。そのため
  - 修飾キーの順序は値に影響しない
  - 左右の混在（`Shift + RCmd + A`）は `UnknownKeycode`（「左右の修飾キーは混在できません」）。QMK の 5bit では表せない
  - 修飾できるのは基本キーだけ（`Cmd + LT(1, Space)` はエラー）
- .vil には `VialNotation` が Vial の名前で書く（`C_S`, `SGUI`, `LCA`, `LSA`, `MEH`, `LCG`, `LAG`, `LCAG`, `HYPR`, `RCG` ...）。
  Vial に名前のない組み合わせ（`LCSG`, `LSAG`, 右側の多く）は `0x0B17` のような 16bit 値で書く。
  旧実装は `LCS(...)` / `LCSG(...)` など Vial が読めない名前を書き、右 Ctrl+Shift+Alt を MEH にしていた（直した）
- decompile（`Formatter`）の正規形: 別名があれば別名（`LSFT(KC_1)` → `!`）、なければ修飾キー式。
  順序は `Ctrl, Option, Shift, Command`、右側は `RCtrl, ROption, RShift, RCommand`（`EXPRESSION_ORDER` / `EXPRESSION_FORMAT`）
- ModTap は `正規名_T(キー)`（`LGUI_T(Lang2)`）、正規名がなければ `MT(MOD_..., キー)`
- 不変条件 `parse(format(k)) == k` は全 16bit 値で spec が検査する（`spec/mapping/keycode_notation_spec.rb`）

## テスト

- `spec/mapping/keycode_notation_spec.rb`: 表記ごとの値、エラーメッセージ、往復
- `spec/mapping/keycode_notation_config_spec.rb`: test_config / authors_config の全キーコードが旧コードと同じ値
  （`spec/fixtures/expected/config_keycodes.yaml`）
