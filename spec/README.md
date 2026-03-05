# RSpec Test Suite

Cornix Keyboard Layout Managerの包括的なテストスイートです。

## テストファイル一覧

### 1. compiler_spec.rb (415行, 30テスト)

Compilerクラスの機能テスト。

**テスト項目**:
- layout.vilファイルの生成
- 10レイヤーの生成
- エンコーダーレイアウトの生成
- キーコード解決:
  - エイリアス → QMK変換
  - Trans/NoKey等の特殊エイリアス
  - レイヤー番号の保持 (MO(3) → MO(3), not MO(KC_3))
  - 修飾キーの引数変換 (LSFT(1) → LSFT(KC_1))
  - ネストされた関数呼び出し (LT(1, Space) → LT(1, KC_SPACE))
- レイヤーコンパイル:
  - ベースレイヤーの完全な定義
  - オーバーライドレイヤーの差分
  - ロータリープッシュボタンの処理
- エンコーダーコンパイル
- マクロコンパイル:
  - インデックス管理
  - タップアクション
  - テキストアクション
  - 無効化されたマクロのスキップ
- タップダンスコンパイル:
  - インデックス管理
  - レイヤー番号の保持
- コンボコンパイル
- 設定コンパイル:
  - QMK設定
  - boolean → integer変換
  - デフォルト値の使用
- エッジケース:
  - 空のオーバーライドレイヤー
  - KC_NOの処理
  - 特殊文字の処理
  - 複数引数関数

### 2. decompiler_spec.rb (453行, 27テスト)

Decompilerクラスの機能テスト。

**テスト項目**:
- config/ディレクトリ構造の生成
- メタデータ抽出
- ポジションマップ抽出
- QMK設定抽出
- キーコード解決:
  - QMK → エイリアス変換
  - KC_TRNS → Trans
  - LSFT(KC_1) → LSFT(1)
  - レイヤー番号の保持
- レイヤー抽出:
  - ベースレイヤー (完全なマッピング)
  - オーバーライドレイヤー (差分のみ)
  - 空レイヤーのスキップ
  - 全10レイヤーの処理
- マクロ抽出:
  - 構造の整合性
  - シーケンスの保持
  - インデックス管理
  - 空スロットのスキップ
- タップダンス抽出:
  - アクション構造
  - レイヤー番号の保持
  - 空スロットのスキップ
- コンボ抽出:
  - トリガーと出力の構造
  - 空スロットのスキップ
- エッジケース:
  - オプションフィールドの欠落
  - 特殊文字の処理
  - keycode_aliases.yamlの非コピー
- ラウンドトリップ互換性

### 3. keycode_resolver_spec.rb (174行, 21テスト)

KeycodeResolverクラスのエイリアス解決テスト。

**テスト項目**:
- resolve (エイリアス → QMK):
  - 基本エイリアス解決
  - 未知のキーコード
  - Transparent系エイリアス
  - NoKey
  - 大文字小文字の区別
- reverse_resolve (QMK → エイリアス):
  - 基本的な逆解決
  - 未知のキーコード
  - 複数エイリアスがある場合の優先順位
  - KC_NO
- システムエイリアスファイル:
  - lib/cornix/keycode_aliases.yamlの読み込み
  - 一般的なキーコードの解決
  - 修飾キーの処理
- エッジケース:
  - nil処理
  - 空文字列
  - 数値入力
  - 既に解決済みのQMKキーコード
  - 関数形式のキーコード
- 初期化:
  - 存在しないファイルのエラー処理
  - 不正なYAML
  - aliasesキーの欠落

### 4. position_map_spec.rb (154行, 17テスト)

PositionMapクラスの物理位置マッピングテスト。

**テスト項目**:
- symbol_at (位置 → シンボル):
  - 左手の位置
  - 右手の位置
  - エンコーダーシンボル
  - 範囲外の位置
  - 文字列handパラメータ
- find_position (シンボル → 位置):
  - 左手シンボルの検索
  - 右手シンボルの検索
  - 特殊キーの検索
  - 存在しないシンボル
  - 大文字小文字の区別
  - position_map内の全シンボルの検索
- 初期化:
  - YAMLファイルの読み込み
  - 存在しないファイルのエラー
  - 不正なYAML
- エッジケース:
  - 負のインデックス
  - 全位置の検索

### 5. validator_spec.rb (366行, 25テスト)

Validatorクラスの設定ファイル検証テスト。

**テスト項目**:
- validate:
  - 有効な設定
- レイヤー検証:
  - 無効なファイル名
  - 範囲外のインデックス (10+)
  - 重複インデックス
  - 有効なインデックス (0-9)
- マクロ検証:
  - nameフィールドの欠落
  - 重複名
  - 一意な名前
- タップダンス検証:
  - nameフィールドの欠落
  - 重複名
- コンボ検証:
  - nameフィールドの欠落
  - 重複名
- レイヤー参照検証:
  - 未知のマクロ参照
  - 未知のタップダンス参照
  - 名前による有効な参照
  - インデックスによる有効な参照
- エラーレポート:
  - 複数エラーの報告
  - 成功メッセージ
- エッジケース:
  - 空ディレクトリ
  - レイヤー0のみ
  - レイヤーインデックスのギャップ
  - .ymlと.yamlの混在

### 6. integration_spec.rb (160行, 6テスト)

Compiler + Decompilerの統合テスト。

**テスト項目**:
- ラウンドトリップ変換:
  - データ損失なし
  - フルラウンドトリップでのデータ整合性
- レイヤーコンパイル:
  - Layer 0の完全性
  - オーバーライドレイヤーの処理
- マクロコンパイル:
  - 正しいインデックス順序
- エイリアス解決:
  - レイヤー番号引数の処理

## 実行方法

### 全テストの実行

```bash
bundle exec rspec
```

### 特定のテストファイルの実行

```bash
bundle exec rspec spec/compiler_spec.rb
bundle exec rspec spec/decompiler_spec.rb
bundle exec rspec spec/keycode_resolver_spec.rb
bundle exec rspec spec/position_map_spec.rb
bundle exec rspec spec/validator_spec.rb
bundle exec rspec spec/integration_spec.rb
```

### 詳細出力での実行

```bash
bundle exec rspec --format documentation
```

### 特定のテストのみ実行

```bash
# describeブロックで絞り込み
bundle exec rspec spec/compiler_spec.rb --example "keycode resolution"

# itブロックで絞り込み
bundle exec rspec spec/compiler_spec.rb --example "converts basic aliases"
```

## テストカバレッジ統計

- **総テストケース数**: 126
- **総行数**: 1,722行
- **カバー範囲**:
  - Compiler: キーコード変換、レイヤー生成、マクロ/タップダンス/コンボ処理
  - Decompiler: QMK→エイリアス変換、YAML生成、ラウンドトリップ
  - KeycodeResolver: 双方向エイリアス解決
  - PositionMap: 物理位置マッピング
  - Validator: 設定ファイル妥当性検証
  - Integration: エンドツーエンドのラウンドトリップ

## テスト設計原則

1. **ユニットテスト**: 各クラスの機能を独立してテスト
2. **統合テスト**: Compiler→Decompiler→Compilerの完全なフローをテスト
3. **エッジケースカバレッジ**: nil、空文字列、範囲外値、不正入力
4. **エラーハンドリング**: 例外処理と適切なエラーメッセージ
5. **データ整合性**: ラウンドトリップでデータが失われないことを保証

## 継続的な改善

新機能の追加時には、対応するテストケースも追加してください：

1. 新しいキーコードタイプ → keycode_resolver_spec.rbに追加
2. 新しいレイヤー機能 → compiler_spec.rb, decompiler_spec.rbに追加
3. 新しい検証ルール → validator_spec.rbに追加
4. 統合機能の変更 → integration_spec.rbで検証
