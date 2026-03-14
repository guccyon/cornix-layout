# frozen_string_literal: true

require_relative '../../../lib/cornix/models/concerns/validatable'

RSpec.describe Cornix::Models::Concerns::Validatable do
  # テスト用のダミーモデル
  class TestModel
    include Cornix::Models::Concerns::Validatable

    attr_reader :name, :value

    def initialize(name:, value:)
      @name = name
      @value = value
    end

    validates :name, :presence, message: "cannot be blank"
    validates :value, :range, min: 1, max: 100, message: "must be 1-100"
    validates :value, :type, is: Integer, message: "must be an integer"

    validates :name, :custom, phase: :semantic, with: ->(value, options) {
      return { valid: true } if value.nil? || value.empty?
      return { valid: true } unless options[:forbidden_names]

      if options[:forbidden_names].include?(value)
        { valid: false, error: "name is forbidden" }
      else
        { valid: true }
      end
    }
  end

  describe '#structurally_valid?' do
    it 'returns true when no structural errors' do
      model = TestModel.new(name: 'valid', value: 50)
      expect(model.structurally_valid?).to be true
    end

    it 'returns false when structural errors exist' do
      model = TestModel.new(name: '', value: 50)
      expect(model.structurally_valid?).to be false
    end

    it 'detects type errors' do
      model = TestModel.new(name: 'valid', value: 'not an integer')
      expect(model.structurally_valid?).to be false
    end
  end

  describe '#structural_errors' do
    it 'returns empty array when valid' do
      model = TestModel.new(name: 'valid', value: 50)
      expect(model.structural_errors).to be_empty
    end

    it 'detects presence violations' do
      model = TestModel.new(name: '', value: 50)
      errors = model.structural_errors
      expect(errors).to include(include('cannot be blank'))
    end

    it 'detects range violations' do
      model = TestModel.new(name: 'valid', value: 150)
      errors = model.structural_errors
      expect(errors.size).to be > 0
      # カスタムメッセージが優先される
      expect(errors.join(' ')).to include('must be 1-100')
    end

    it 'detects type violations' do
      model = TestModel.new(name: 'valid', value: 'invalid')
      errors = model.structural_errors
      expect(errors.size).to be > 0
      # 型エラーまたは範囲エラー（値が数値でない）
      expect(errors.join(' ')).to match(/integer|number/i)
    end
  end

  describe '#semantically_valid?' do
    it 'returns true when no semantic errors' do
      model = TestModel.new(name: 'allowed', value: 50)
      context = { forbidden_names: ['forbidden', 'banned'] }
      expect(model.semantically_valid?(context)).to be true
    end

    it 'returns false when semantic errors exist' do
      model = TestModel.new(name: 'forbidden', value: 50)
      context = { forbidden_names: ['forbidden', 'banned'] }
      expect(model.semantically_valid?(context)).to be false
    end

    it 'returns true when no context is provided' do
      model = TestModel.new(name: 'forbidden', value: 50)
      # contextなしの場合、semantic_validationsは実行されない（またはcontextが空）
      expect(model.semantically_valid?).to be true
    end
  end

  describe '#semantic_errors' do
    it 'validates against provided context' do
      model = TestModel.new(name: 'forbidden', value: 50)
      context = { forbidden_names: ['forbidden', 'banned'] }
      errors = model.semantic_errors(context)
      expect(errors).not_to be_empty
      expect(errors.first).to include('forbidden')
    end

    it 'returns empty when name is allowed' do
      model = TestModel.new(name: 'allowed', value: 50)
      context = { forbidden_names: ['forbidden', 'banned'] }
      errors = model.semantic_errors(context)
      expect(errors).to be_empty
    end
  end

  describe '#valid?' do
    it 'returns true when both structural and semantic validations pass' do
      model = TestModel.new(name: 'valid', value: 50)
      context = { forbidden_names: ['forbidden'] }
      expect(model.valid?(context)).to be true
    end

    it 'returns false when structural validation fails' do
      model = TestModel.new(name: '', value: 50)
      context = { forbidden_names: ['forbidden'] }
      expect(model.valid?(context)).to be false
    end

    it 'returns false when semantic validation fails' do
      model = TestModel.new(name: 'forbidden', value: 50)
      context = { forbidden_names: ['forbidden'] }
      expect(model.valid?(context)).to be false
    end
  end

  describe '#all_errors' do
    it 'returns both structural and semantic errors' do
      model = TestModel.new(name: 'forbidden', value: 150)
      context = { forbidden_names: ['forbidden'] }
      errors = model.all_errors(context)
      expect(errors.size).to be >= 2
    end
  end

  describe '#validate!' do
    context 'without mode parameter (default: :strict)' do
      it 'does not raise when valid' do
        model = TestModel.new(name: 'valid', value: 50)
        expect { model.validate! }.not_to raise_error
      end

      it 'raises ValidationError when invalid' do
        model = TestModel.new(name: '', value: 150)
        expect { model.validate! }.to raise_error(
          Cornix::Models::Concerns::ValidationError
        ) do |error|
          expect(error.errors).not_to be_empty
        end
      end

      it 'includes all errors in exception message' do
        model = TestModel.new(name: '', value: 150)
        expect { model.validate! }.to raise_error do |error|
          message = error.message
          expect(message).to include('cannot be blank')
          expect(message).to include('must be')
        end
      end
    end

    context 'with mode: :strict' do
      it 'returns true when valid' do
        model = TestModel.new(name: 'valid', value: 50)
        result = model.validate!({}, mode: :strict)
        expect(result).to be true
      end

      it 'raises ValidationError when invalid (fail-fast)' do
        model = TestModel.new(name: '', value: 150)
        expect { model.validate!({}, mode: :strict) }.to raise_error(
          Cornix::Models::Concerns::ValidationError
        ) do |error|
          expect(error.errors).not_to be_empty
        end
      end

      it 'includes metadata in ValidationError' do
        model = TestModel.new(name: '', value: 150)
        model.instance_variable_set(:@metadata, { file_path: 'config/test.yaml' })

        expect { model.validate!({}, mode: :strict) }.to raise_error(
          Cornix::Models::Concerns::ValidationError
        ) do |error|
          expect(error.metadata).to eq({ file_path: 'config/test.yaml' })
          expect(error.message).to include('config/test.yaml')
        end
      end
    end

    context 'with mode: :collect' do
      it 'returns empty array when valid' do
        model = TestModel.new(name: 'valid', value: 50)
        errors = model.validate!({}, mode: :collect)
        expect(errors).to be_empty
        expect(errors).to be_an(Array)
      end

      it 'returns all errors without raising (collect mode)' do
        model = TestModel.new(name: '', value: 150)
        errors = model.validate!({}, mode: :collect)
        expect(errors).not_to be_empty
        expect(errors).to be_an(Array)
        expect(errors.join(' ')).to include('cannot be blank')
        expect(errors.join(' ')).to include('must be')
      end

      it 'collects semantic errors as well' do
        model = TestModel.new(name: 'forbidden', value: 50)
        context = { forbidden_names: ['forbidden'] }
        errors = model.validate!(context, mode: :collect)
        expect(errors).not_to be_empty
        expect(errors.first).to include('forbidden')
      end

      it 'does not raise exception in collect mode' do
        model = TestModel.new(name: '', value: 150)
        expect { model.validate!({}, mode: :collect) }.not_to raise_error
      end
    end

    context 'with invalid mode' do
      it 'raises ArgumentError' do
        model = TestModel.new(name: 'valid', value: 50)
        expect { model.validate!({}, mode: :invalid) }.to raise_error(
          ArgumentError,
          /Invalid mode: invalid/
        )
      end
    end
  end

  describe 'ValidationError' do
    context 'without metadata' do
      it 'stores errors' do
        errors = ['Error 1', 'Error 2', 'Error 3']
        exception = Cornix::Models::Concerns::ValidationError.new(errors)
        expect(exception.errors).to eq(errors)
      end

      it 'formats message with bullet points' do
        errors = ['Error 1', 'Error 2']
        exception = Cornix::Models::Concerns::ValidationError.new(errors)
        expected = "Validation Error:\n  - Error 1\n  - Error 2"
        expect(exception.message).to eq(expected)
      end

      it 'handles single error string' do
        exception = Cornix::Models::Concerns::ValidationError.new('Single error')
        expect(exception.errors).to eq(['Single error'])
        expected = "Validation Error:\n  - Single error"
        expect(exception.message).to eq(expected)
      end
    end

    context 'with metadata' do
      it 'stores metadata' do
        errors = ['Error 1', 'Error 2']
        metadata = { file_path: 'config/test.yaml' }
        exception = Cornix::Models::Concerns::ValidationError.new(errors, metadata: metadata)
        expect(exception.metadata).to eq(metadata)
      end

      it 'prefixes errors with file_path' do
        errors = ['name: cannot be blank', 'value: must be 1-100']
        metadata = { file_path: 'config/layers/0_base.yaml' }
        exception = Cornix::Models::Concerns::ValidationError.new(errors, metadata: metadata)

        expected_message = "Error in config/layers/0_base.yaml:\n  - name: cannot be blank\n  - value: must be 1-100"
        expect(exception.message).to eq(expected_message)
      end

      it 'handles empty metadata hash' do
        errors = ['Error 1', 'Error 2']
        exception = Cornix::Models::Concerns::ValidationError.new(errors, metadata: {})
        expected = "Validation Error:\n  - Error 1\n  - Error 2"
        expect(exception.message).to eq(expected)
      end

      it 'uses validation error format when no file_path' do
        errors = ['Error 1', 'Error 2']
        metadata = { other_key: 'value' }
        exception = Cornix::Models::Concerns::ValidationError.new(errors, metadata: metadata)
        expected = "Validation Error:\n  - Error 1\n  - Error 2"
        expect(exception.message).to eq(expected)
      end
    end
  end

  describe 'ClassMethods' do
    it 'collects structural validations' do
      validations = TestModel.structural_validations
      expect(validations).not_to be_empty
      expect(validations.map { |v| v[:field] }).to include(:name, :value)
    end

    it 'collects semantic validations' do
      validations = TestModel.semantic_validations
      expect(validations).not_to be_empty
      expect(validations.map { |v| v[:field] }).to include(:name)
    end
  end

  describe 'Validators module' do
    describe '.run' do
      it 'dispatches to correct validator' do
        result = Cornix::Models::Concerns::Validators.run(:presence, 'value', {})
        expect(result[:valid]).to be true

        result = Cornix::Models::Concerns::Validators.run(:presence, '', {})
        expect(result[:valid]).to be false
      end

      it 'returns error for unknown validator type' do
        result = Cornix::Models::Concerns::Validators.run(:unknown, 'value', {})
        expect(result[:valid]).to be false
        expect(result[:error]).to include('Unknown')
      end
    end

    describe 'presence validator' do
      it 'validates presence' do
        result = Cornix::Models::Concerns::Validators.run(:presence, 'value', {})
        expect(result[:valid]).to be true

        result = Cornix::Models::Concerns::Validators.run(:presence, '', {})
        expect(result[:valid]).to be false

        result = Cornix::Models::Concerns::Validators.run(:presence, nil, {})
        expect(result[:valid]).to be false
      end

      it 'allows nil when option is set' do
        result = Cornix::Models::Concerns::Validators.run(:presence, nil, allow_nil: true)
        expect(result[:valid]).to be true
      end
    end

    describe 'type validator' do
      it 'validates type' do
        result = Cornix::Models::Concerns::Validators.run(:type, 42, is: Integer)
        expect(result[:valid]).to be true

        result = Cornix::Models::Concerns::Validators.run(:type, '42', is: Integer)
        expect(result[:valid]).to be false
      end
    end

    describe 'format validator' do
      it 'validates format' do
        result = Cornix::Models::Concerns::Validators.run(:format, 'abc123', with: /^[a-z0-9]+$/)
        expect(result[:valid]).to be true

        result = Cornix::Models::Concerns::Validators.run(:format, 'ABC', with: /^[a-z]+$/)
        expect(result[:valid]).to be false
      end
    end

    describe 'range validator' do
      it 'validates range' do
        result = Cornix::Models::Concerns::Validators.run(:range, 5, min: 0, max: 10)
        expect(result[:valid]).to be true

        result = Cornix::Models::Concerns::Validators.run(:range, 15, min: 0, max: 10)
        expect(result[:valid]).to be false
      end
    end

    describe 'inclusion validator' do
      it 'validates inclusion' do
        result = Cornix::Models::Concerns::Validators.run(:inclusion, 'a', in: ['a', 'b', 'c'])
        expect(result[:valid]).to be true

        result = Cornix::Models::Concerns::Validators.run(:inclusion, 'd', in: ['a', 'b', 'c'])
        expect(result[:valid]).to be false
      end
    end

    describe 'length validator' do
      it 'validates length' do
        result = Cornix::Models::Concerns::Validators.run(:length, 'abc', min: 1, max: 5)
        expect(result[:valid]).to be true

        result = Cornix::Models::Concerns::Validators.run(:length, 'abcdef', min: 1, max: 5)
        expect(result[:valid]).to be false
      end
    end

    describe 'custom validator' do
      it 'executes custom validation proc' do
        validator = ->(value) { { valid: value > 0 } }
        result = Cornix::Models::Concerns::Validators.run(:custom, 5, with: validator)
        expect(result[:valid]).to be true

        result = Cornix::Models::Concerns::Validators.run(:custom, -5, with: validator)
        expect(result[:valid]).to be false
      end

      it 'raises error when proc is missing' do
        expect {
          Cornix::Models::Concerns::Validators.run(:custom, 5, {})
        }.to raise_error(ArgumentError)
      end
    end
  end
end
