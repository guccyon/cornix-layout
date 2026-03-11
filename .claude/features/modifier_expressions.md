# Modifier Expression System (VS Code風修飾キー表現)

**概要**: VS CodeやIDEのような読みやすい修飾キー表現（例: `Cmd + Q`）をサポート。自動的にQMK形式（`LGUI(KC_Q)`）にコンパイルし、QMKショートカット（LSG、MEH、HYPR等）を自動検出。

#### アーキテクチャ

**アプローチ**: KeycodeParserに新しいパターン検出を追加（新しいResolverは作らない）。

**理由**:
- KeycodeParserが既に全ての構文解析を集約している
- 修飾キー表現は構文糖衣であり、セマンティック参照（Macro/TapDance）ではない
- 既存のparser-firstアーキテクチャに適合: parse() → resolve() → QMK

**データフロー**:
```
ユーザー入力: "Cmd + Q"
    ↓
KeycodeParser.parse() → { type: :modifier_expression, modifiers: ['Cmd'], key: 'Q' }
    ↓
ModifierExpressionCompiler.to_qmk() → "LGUI(KC_Q)"
    ↓
layout.vil (QMK形式)
    ↓ (decompile - 変換しない)
LGUI(KC_Q) → LGUI(Q) (標準decompile)
```

**コンポーネント**:
1. **KeycodeParser**（修正） - パターン検出、parse/unparseロジック追加（+60行）
2. **ModifierExpressionCompiler**（新規） - トークン → QMKショートカット/ネスト関数に変換（~200行）
3. **Compiler**（修正） - 1行のcase追加で統合（+4行）
4. **Validator**（修正） - 修飾キー名とキーの検証追加（+16行）

#### サポート形式

**基本構文**:
```yaml
Cmd + Q               # → LGUI(KC_Q)
Shift + Cmd + Q       # → LSG(KC_Q)
Ctrl + Shift + Alt + Q # → MEH(KC_Q)
```

**特徴**:
- 順序無関係: `Cmd + Shift` = `Shift + Cmd` → `LSG`
- 柔軟なスペース: `Cmd+Q` = `Cmd + Q` = `Cmd  +  Q`
- プラットフォーム対応: `Command`, `Win`, `Option`, `Ctrl`すべてサポート
- **クォート柔軟性**: `Cmd + ]` = `Cmd + "]"` （両方サポート、unparseは常にクォート無し）

#### QMK修飾キーショートカットマップ

**単一修飾キー（左）**: LCTL, LSFT, LALT, LGUI
**単一修飾キー（右）**: RCTL, RSFT, RALT, RGUI

**2修飾キー組み合わせ（左）**:
- LCS (Ctrl+Shift)
- LCA (Ctrl+Alt)
- LCG (Ctrl+GUI)
- LSA (Shift+Alt)
- LSG (Shift+GUI)
- LAG (Alt+GUI)

**2修飾キー組み合わせ（右）**: RCS, RCA, RCG, RSA, RSG, RAG

**3修飾キー組み合わせ（左）**:
- MEH (Ctrl+Shift+Alt)
- LCSG (Ctrl+Shift+GUI)
- LCAG (Ctrl+Alt+GUI)
- LSAG (Shift+Alt+GUI)

**3修飾キー組み合わせ（右）**: RCSG, RCAG, RSAG

**特殊組み合わせ**:
- MEH (Ctrl+Shift+Alt) - 左右同じ名前
- HYPR (Ctrl+Shift+Alt+GUI) - 4修飾キー

#### 変換アルゴリズム

**ステップ1: 式のパース**
```ruby
# Pattern: /^(\w+)(\s*\+\s*(?:\w+|"[^"]*"|'[^']*'|[^\s+]))+$/
# クォート付き・クォート無しの両方をサポート
"Cmd + Shift + Q" → { type: :modifier_expression, modifiers: ['Cmd', 'Shift'], key: 'Q' }
"Cmd + ]" → { type: :modifier_expression, modifiers: ['Cmd'], key: ']' }
"Cmd + \"]\"" → { type: :modifier_expression, modifiers: ['Cmd'], key: ']' }  # クォート除去
```

**ステップ2: 修飾キーの解決**
```ruby
['Cmd', 'Shift'] → ['LGUI', 'LSFT']
```

**ステップ3: QMKショートカット検出**
```ruby
# 順序無関係（ソート後に検索）
['LGUI', 'LSFT'] → sort → ['LGUI', 'LSFT'] → SHORTCUTS lookup → 'LSG'
```

**ステップ4: ネスト関数へのフォールバック**
```ruby
# ショートカットが存在しない場合
modifiers: ['LGUI', 'LALT'], key: 'Space'
→ LGUI(LALT(KC_SPACE))  # 最初の修飾キー = 最外部
```

**ステップ5: キーの解決**
```ruby
# KeycodeConverterに委譲
'Q' → 'KC_Q'
'Space' → 'KC_SPACE'
'KC_ENTER' → 'KC_ENTER'（既にQMK形式）
```

#### 修飾キーエイリアス定義

**左側（L/R省略時のデフォルト）**:
- `Shift` → LSFT
- `Ctrl`, `Control` → LCTL
- `Alt`, `Option` → LALT
- `Cmd`, `Command`, `Win`, `Gui` → LGUI

**右側（R接頭辞を明示）**:
- `RShift` → RSFT
- `RCtrl`, `RControl` → RCTL
- `RAlt`, `ROption` → RALT
- `RCmd`, `RCommand`, `RWin`, `RGui` → RGUI

#### 実装詳細

**KeycodeParser変更**（lib/cornix/keycode_parser.rb, +60行）:
```ruby
# Pattern 3: Modifier expressions - Cmd + Q, Shift + Ctrl + A
if keycode_str.match?(/^(\w+)(\s*\+\s*\w+)+$/)
  return parse_modifier_expression(keycode_str)
end

def self.parse_modifier_expression(expr)
  parts = expr.split(/\s*\+\s*/).map(&:strip)
  modifiers = parts[0..-2]
  key = parts[-1]
  { type: :modifier_expression, modifiers: modifiers, key: key }
end
```

**ModifierExpressionCompiler**（lib/cornix/modifier_expression_compiler.rb, ~200行）:
```ruby
SHORTCUTS = {
  ['LALT', 'LCTL', 'LGUI', 'LSFT'] => 'HYPR',
  ['LALT', 'LCTL', 'LSFT'] => 'MEH',
  ['LCTL', 'LGUI', 'LSFT'] => 'LCSG',
  # ... 20+ shortcuts
}.freeze

MODIFIER_TO_FUNCTION = {
  'Shift' => 'LSFT', 'Cmd' => 'LGUI', 'Command' => 'LGUI',
  # ... all modifier aliases
}.freeze

def self.to_qmk(token, keycode_resolver)
  mod_functions = token[:modifiers].map { |m| resolve_modifier(m) }
  resolved_key = resolve_key(token[:key], keycode_resolver)
  shortcut = find_shortcut(mod_functions)
  shortcut ? "#{shortcut}(#{resolved_key})" : nest_modifiers(mod_functions, resolved_key)
end

def self.find_shortcut(mod_functions)
  sorted_mods = mod_functions.sort
  SHORTCUTS[sorted_mods]
end
```

**Compiler統合**（lib/cornix/compiler.rb, +4行）:
```ruby
when :modifier_expression
  ModifierExpressionCompiler.to_qmk(parsed, @keycode_resolver)
```

**Validator統合**（lib/cornix/validator.rb, +16行）:
```ruby
when :modifier_expression
  parsed[:modifiers].each do |mod|
    unless valid_modifier?(mod)
      @errors << "Invalid modifier name: #{mod} in expression '#{keycode}'"
      return false
    end
  end
  return valid_simple_keycode?(parsed[:key])

def valid_modifier?(modifier)
  Cornix::ModifierExpressionCompiler::MODIFIER_TO_FUNCTION.key?(modifier)
end
```

#### テストカバレッジ

**新規テスト**: 合計79テスト（全479テスト中）
- KeycodeParser: +21テスト（修飾キー表現パース、unparse、round-trip）
- ModifierExpressionCompiler: 52テスト（全機能カバレッジ）
  - シンプル式、2/3/4修飾キー、QMKショートカット全組み合わせ
  - 順序無関係、修飾キーエイリアス、キー解決
  - エラーハンドリング
- Compiler統合: +8テスト
- Validator統合: +8テスト
- Integration: +2テスト（round-trip、QMK形式保持）

**実行結果**: 全479テスト成功（0 failures）

#### よくある使用例

**アプリケーション操作**:
```yaml
Q: Cmd + Q          # アプリ終了
W: Cmd + W          # ウィンドウを閉じる
T: Cmd + T          # 新規タブ
```

**エディタショートカット**:
```yaml
C: Cmd + C          # コピー
V: Cmd + V          # ペースト
S: Cmd + S          # 保存
F: Ctrl + Shift + F # プロジェクト検索 → LCS(KC_F)
```

**ウィンドウ管理**:
```yaml
Left: Ctrl + Shift + Alt + Left   # MEH(KC_LEFT)
Right: Ctrl + Shift + Alt + Right # MEH(KC_RIGHT)
```

#### よくある間違い

1. ❌ プラス記号をキーとして使用
   - `Shift + +` は構文解析できない
   - ✅ `LSFT(KC_PLUS)` または `Plus`エイリアス使用

2. ❌ 関数をキーとして使用
   - `Cmd + LT(1, Space)` は構文解析できない
   - ✅ `LGUI(LT(1, Space))` QMK構文で記述

3. ❌ Decompile後に修飾キー表現に戻ると期待
   - Decompilerは QMK形式を保持（`LGUI(Q)`）
   - ✅ 意図的な設計（QMK関数は様々な方法で記述可能なため）

4. ❌ 修飾キー表現とQMK構文を混同
   - `Cmd + Q` は YAML専用（ユーザー入力）
   - layout.vilには必ず`LGUI(KC_Q)`形式（QMK標準）

#### Decompile動作の理由

**原則**: Decompilerは修飾キー表現に自動変換しない（QMK形式を保持）

**理由**:
1. **曖昧性**: QMK関数は様々な方法で記述可能
   - `LGUI(KC_Q)` = `Cmd + Q` = `LGUI_T(KC_Q)`?
   - 元の意図を正確に復元できない

2. **情報損失**: layout.vilにはQMK形式のみ（修飾キー表現は含まれない）
   - Compile: `Cmd + Q` → `LGUI(KC_Q)` (OK)
   - Decompile: `LGUI(KC_Q)` → `?` (どちらに戻すべき？)

3. **ユーザー選択の尊重**: 修飾キー表現を使うかはユーザーの選択
   - 明示的に記述した場合のみ維持
   - 既存のQMK構文を勝手に変換しない

#### Round-trip Check

**期待動作**:
```bash
# 1. 修飾キー表現を含むYAML作成
cat > config/layers/0_base.yaml <<EOF
mapping:
  Q: Cmd + Q
EOF

# 2. Compile
ruby bin/compile  # → layout.vilに LGUI(KC_Q)

# 3. Decompile
mv config config.backup
ruby bin/decompile  # → config/layers/*.yamlに LGUI(Q)

# 4. Recompile
ruby bin/compile

# 5. 検証
ruby bin/diff_layouts  # ✓ FILES ARE IDENTICAL
```

**重要**: 修飾キー表現は元に戻らないが、QMK形式は完全に一致する。

#### 制限事項とエスケープハッチ

**制限事項**:
1. プラス記号をキーとして使用不可: `Shift + +`
2. 関数をキーとして使用不可: `Cmd + LT(1, Space)`
3. パターンは単語文字のみ: `/^(\w+)(\s*\+\s*\w+)+$/`

**エスケープハッチ**: QMK構文を直接記述
```yaml
Q: LGUI(KC_PLUS)         # プラス記号
W: LGUI(LT(1, Space))    # ネストした関数
E: Cmd + Q               # 修飾キー表現（推奨）
```

