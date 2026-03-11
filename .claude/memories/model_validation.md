# Model Validation Memory - Validatable実装の知見

Validatableモジュール実装時に得られた重要な知見を記録します。

## Overview

Validatableモジュールは、全モデルに自己検証機能を提供するConcernです。2段階検証（structural + semantic）により、依存関係のある複雑なバリデーションにも対応しています。

**実装ファイル**: `lib/cornix/models/concerns/validatable.rb` (260行)
**テストファイル**: `spec/models/concerns/validatable_spec.rb` (34テスト)

## Architecture

### 2段階検証パターン

```ruby
class Model
  include Validatable

  # Step 1: Structural Validations（依存なし）
  structural_validations do
    validate :field1, presence: true, type: String
    validate :field2, format: /^[A-Z]+$/
  end

  # Step 2: Semantic Validations（依存あり）
  semantic_validations do
    validate :field1, custom: ->(value, options) {
      context = options[:context]
      # contextを使った検証
      context[:other_model].valid_reference?(value)
    }
  end

  def initialize(field1:, field2:)
    @field1 = field1
    @field2 = field2
    validate!  # 両方の検証を実行
  end
end
```

### なぜ2段階？

1. **structural**: モデル単体で完結する検証
   - 必須チェック（presence）
   - 型チェック（type）
   - フォーマットチェック（format）
   - 依存なし → 高速、テストしやすい

2. **semantic**: 他モデルとの関係を含む検証
   - 参照整合性チェック
   - コンテキスト依存の検証
   - 依存あり → 遅い、統合テストが必要

## DSL Syntax

### Basic Validations

```ruby
structural_validations do
  # 必須チェック
  validate :name, presence: true

  # 型チェック
  validate :count, type: Integer

  # フォーマットチェック（正規表現）
  validate :vendor_id, format: /^0x[0-9A-Fa-f]{4}$/

  # 複数条件
  validate :field, presence: true, type: String, format: /^[A-Z]/
end
```

### Custom Validator

```ruby
structural_validations do
  # 1引数版（valueのみ）
  validate :matrix, custom: ->(value) {
    value.is_a?(Hash) &&
    value[:rows].is_a?(Integer) &&
    value[:cols].is_a?(Integer)
  }

  # 2引数版（value + options）
  validate :field, custom: ->(value, options) {
    context = options[:context]
    # contextアクセス可能
    value.start_with?(context[:prefix])
  }
end
```

### Nested Object Validation

```ruby
structural_validations do
  # ネストオブジェクトの検証
  validate :hand_mapping, custom: ->(value) {
    value.is_a?(HandMapping) && value.valid?
  }

  # 配列の検証
  validate :sequences, custom: ->(value) {
    value.is_a?(Array) &&
    value.all? { |seq| seq.is_a?(Sequence) && seq.valid? }
  }
end
```

## Custom Validator Arity Detection

Validatableモジュールは、Custom Validatorの引数数を自動判定します。

### 実装

```ruby
def run_custom_validator(validator, value, field_name, options)
  arity = validator.arity
  result = case arity
           when 1
             validator.call(value)
           when 2
             validator.call(value, options)
           else
             raise ArgumentError, "Custom validator must accept 1 or 2 arguments"
           end

  unless result
    @errors << "#{field_name} failed custom validation"
  end
end
```

### 使い分け

**1引数版**（推奨）:
- valueのみで検証が完結する場合
- 例: 型チェック、フォーマットチェック、簡単な構造検証

**2引数版**（必要時のみ）:
- contextが必要な場合
- 例: 他モデルとの参照整合性チェック

### よくある間違い

❌ **間違い**: 常に2引数版を使う
```ruby
validate :field, custom: ->(value, options) {
  value.is_a?(String)  # contextを使わないのに2引数
}
```

✅ **正しい**: contextが不要なら1引数版
```ruby
validate :field, custom: ->(value) {
  value.is_a?(String)
}
```

## ValidationError vs ArgumentError

### ValidationError（ユーザーエラー）

**用途**: バリデーション失敗時に使用

```ruby
def initialize(name:)
  @name = name
  validate!  # ValidationErrorをraiseする可能性
end

# 使用例
begin
  model = Model.new(name: nil)
rescue Cornix::Models::ValidationError => e
  puts e.errors  # ["name is required"]
end
```

### ArgumentError（プログラミングエラー）

**用途**: プログラムのバグを示す場合に使用

```ruby
def initialize(name:)
  raise ArgumentError, "name must be provided" if name.nil?
  @name = name
end
```

### 使い分けルール

| エラー | 用途 | 例 |
|-------|------|-----|
| ValidationError | ユーザーデータの検証失敗 | 必須フィールドが空、フォーマット不正 |
| ArgumentError | プログラムのバグ | 必須引数の欠落、型の不一致 |

### 実装パターン

```ruby
def initialize(data)
  # Step 1: ArgumentError（プログラムエラー）
  raise ArgumentError, "data must be a Hash" unless data.is_a?(Hash)

  # Step 2: フィールド設定
  @name = data['name']
  @count = data['count']

  # Step 3: ValidationError（ユーザーエラー）
  validate!
end
```

## Nested Object Validation Pattern

親モデルが子モデルを持つ場合の検証パターン。

### Pattern 1: 子モデルのvalidate!を呼ぶ

```ruby
class Layer
  include Validatable

  attr_accessor :name, :hand_mapping

  structural_validations do
    validate :name, presence: true, type: String
    validate :hand_mapping, presence: true, type: HandMapping
    validate :hand_mapping, custom: ->(value) {
      value.valid?  # 子モデルの検証を実行
    }
  end

  def initialize(data)
    @name = data['name']
    @hand_mapping = HandMapping.new(data['hand_mapping'])
    validate!
  end
end
```

### Pattern 2: 親のinitializeで子のvalidate!を実行しない

```ruby
class HandMapping
  include Validatable

  attr_accessor :row0, :row1

  structural_validations do
    validate :row0, presence: true, type: RowMapping
    validate :row1, presence: true, type: RowMapping
  end

  def initialize(data)
    @row0 = RowMapping.new(data['row0'])
    @row1 = RowMapping.new(data['row1'])
    # ここではvalidate!を呼ばない（親が呼ぶ）
  end

  # 親が呼ぶタイミングでvalidate!実行
end
```

### Pattern 3: 配列の検証

```ruby
class Macro
  include Validatable

  attr_accessor :sequences

  structural_validations do
    validate :sequences, presence: true
    validate :sequences, custom: ->(value) {
      value.is_a?(Array) &&
      value.all? { |seq| seq.is_a?(Sequence) && seq.valid? }
    }
  end

  def initialize(data)
    @sequences = data['sequences'].map { |s| Sequence.new(s) }
    validate!
  end
end
```

## Testing Patterns

### Basic Test

```ruby
RSpec.describe Model do
  describe '#initialize' do
    it 'creates valid instance with correct data' do
      model = described_class.new(name: 'Test', count: 10)
      expect(model.valid?).to be true
    end

    it 'raises ValidationError for missing required field' do
      expect {
        described_class.new(name: nil, count: 10)
      }.to raise_error(Cornix::Models::ValidationError) do |error|
        expect(error.errors).to include('name is required')
      end
    end
  end
end
```

### Custom Validator Test

```ruby
RSpec.describe Model do
  describe 'custom validation' do
    it 'validates complex structure' do
      expect {
        described_class.new(matrix: { rows: 'invalid' })
      }.to raise_error(Cornix::Models::ValidationError)
    end

    it 'accepts valid structure' do
      model = described_class.new(matrix: { rows: 8, cols: 6 })
      expect(model.valid?).to be true
    end
  end
end
```

### Nested Object Test

```ruby
RSpec.describe ParentModel do
  describe 'nested validation' do
    it 'validates child model' do
      expect {
        described_class.new(
          name: 'Parent',
          child: { invalid: 'data' }
        )
      }.to raise_error(Cornix::Models::ValidationError)
    end

    it 'accepts valid child' do
      model = described_class.new(
        name: 'Parent',
        child: { name: 'Child', count: 5 }
      )
      expect(model.valid?).to be true
    end
  end
end
```

## Common Mistakes

### 1. initialize内でvalidate!を呼び忘れ

❌ **間違い**:
```ruby
def initialize(name:)
  @name = name
  # validate!を呼んでいない
end
```

✅ **正しい**:
```ruby
def initialize(name:)
  @name = name
  validate!
end
```

### 2. ArgumentErrorとValidationErrorの混同

❌ **間違い**:
```ruby
def initialize(data)
  @name = data['name']
  raise ValidationError, "name required" if @name.nil?
  validate!
end
```

✅ **正しい**:
```ruby
def initialize(data)
  @name = data['name']
  validate!  # ValidationErrorはvalidate!が投げる
end

structural_validations do
  validate :name, presence: true
end
```

### 3. Custom Validatorの返り値忘れ

❌ **間違い**:
```ruby
validate :field, custom: ->(value) {
  if value.valid?
    # 何も返さない → nil → false扱い
  end
}
```

✅ **正しい**:
```ruby
validate :field, custom: ->(value) {
  value.valid?  # booleanを返す
}
```

### 4. Nested Objectの検証忘れ

❌ **間違い**:
```ruby
structural_validations do
  validate :child, presence: true, type: ChildModel
  # valid?を呼んでいない
end
```

✅ **正しい**:
```ruby
structural_validations do
  validate :child, presence: true, type: ChildModel
  validate :child, custom: ->(value) { value.valid? }
end
```

## Performance Considerations

### Lazy Validation

現在の実装では、initialize時に必ず検証を実行します。将来的にLazy Validationが必要な場合は、以下のパターンを検討：

```ruby
def initialize(name:, validate: true)
  @name = name
  validate! if validate
end

# 使用例
model = Model.new(name: 'Test', validate: false)  # 検証スキップ
model.validate!  # 後で手動検証
```

### Validation Cache

現在の実装では、毎回検証を実行します。パフォーマンスが問題になる場合は、キャッシュを検討：

```ruby
def valid?
  @validation_cache ||= begin
    run_structural_validations
    run_semantic_validations
    @errors.empty?
  end
end

def invalidate_cache!
  @validation_cache = nil
end
```

## Future Enhancements

### 1. Validator Library

よく使うCustom Validatorをライブラリ化：

```ruby
module Cornix::Models::Validators
  def self.hash_with_keys(value, required_keys)
    value.is_a?(Hash) && required_keys.all? { |k| value.key?(k) }
  end

  def self.array_of_type(value, type)
    value.is_a?(Array) && value.all? { |item| item.is_a?(type) }
  end
end

# 使用例
validate :matrix, custom: ->(value) {
  Validators.hash_with_keys(value, [:rows, :cols])
}
```

### 2. Error Message Customization

```ruby
structural_validations do
  validate :name,
    presence: { message: "Name must be provided" },
    format: { pattern: /^[A-Z]/, message: "Name must start with uppercase" }
end
```

### 3. Conditional Validation

```ruby
structural_validations do
  validate :field, presence: true, if: :condition_met?
end

def condition_met?
  @type == 'special'
end
```

## References

- **実装**: `lib/cornix/models/concerns/validatable.rb`
- **テスト**: `spec/models/concerns/validatable_spec.rb`
- **使用例**:
  - `lib/cornix/models/metadata.rb`
  - `lib/cornix/models/layer.rb`
  - `lib/cornix/models/layer/hand_mapping.rb`
  - `lib/cornix/models/layer/key_mapping.rb`
  - `lib/cornix/models/layer/thumb_keys.rb`

## Related Documentation

- [Current Architecture](../architecture/architecture.md) - アーキテクチャ概要
- [Models Documentation](../architecture/models.md) - モデル層詳細
- [Refactor Progress](../implementation/refactor_progress.md) - 実装進捗
