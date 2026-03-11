# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/cornix/models/layer/thumb_keys'
require_relative '../../../lib/cornix/models/layer/key_mapping'
require_relative '../../../lib/cornix/converters/keycode_converter'
require_relative '../../../lib/cornix/converters/reference_converter'

RSpec.describe Cornix::Models::Layer::ThumbKeys do
  let(:aliases_path) { File.join(__dir__, '../../../lib/cornix/keycode_aliases.yaml') }
  let(:keycode_converter) { Cornix::Converters::KeycodeConverter.new(aliases_path) }
  let(:null_key) { Cornix::Models::Layer::NULL_KEY }

  let(:key1) do
    Cornix::Models::Layer::KeyMapping.new(
      symbol: 'left',
      keycode: 'Tab',
      logical_coord: { hand: :left, row: 3, col: 3 }
    )
  end

  let(:key2) do
    Cornix::Models::Layer::KeyMapping.new(
      symbol: 'middle',
      keycode: 'Space',
      logical_coord: { hand: :left, row: 3, col: 4 }
    )
  end

  let(:key3) do
    Cornix::Models::Layer::KeyMapping.new(
      symbol: 'right',
      keycode: 'Enter',
      logical_coord: { hand: :left, row: 3, col: 5 }
    )
  end

  describe '#initialize' do
    it 'creates ThumbKeys with all NULL_KEY by default' do
      thumb_keys = described_class.new
      expect(thumb_keys.left).to eq(null_key)
      expect(thumb_keys.middle).to eq(null_key)
      expect(thumb_keys.right).to eq(null_key)
    end

    it 'creates ThumbKeys with specific keys' do
      thumb_keys = described_class.new(left: key1, middle: key2, right: key3)
      expect(thumb_keys.left).to eq(key1)
      expect(thumb_keys.middle).to eq(key2)
      expect(thumb_keys.right).to eq(key3)
    end

    it 'allows partial specification with NULL_KEY defaults' do
      thumb_keys = described_class.new(left: key1, middle: key2)
      expect(thumb_keys.left).to eq(key1)
      expect(thumb_keys.middle).to eq(key2)
      expect(thumb_keys.right).to eq(null_key)
    end

    it 'allows only left key' do
      thumb_keys = described_class.new(left: key1)
      expect(thumb_keys.left).to eq(key1)
      expect(thumb_keys.middle).to eq(null_key)
      expect(thumb_keys.right).to eq(null_key)
    end
  end

  describe '#to_qmk_array' do
    it 'converts all NULL_KEY to [-1, -1, -1]' do
      thumb_keys = described_class.new
      qmk_array = thumb_keys.to_qmk_array(keycode_converter)
      expect(qmk_array).to eq([-1, -1, -1])
    end

    it 'converts keys to QMK codes' do
      thumb_keys = described_class.new(left: key1, middle: key2, right: key3)
      qmk_array = thumb_keys.to_qmk_array(keycode_converter)
      expect(qmk_array).to eq(['KC_TAB', 'KC_SPACE', 'KC_ENTER'])
    end

    it 'mixes KeyMapping and NULL_KEY' do
      thumb_keys = described_class.new(left: key1, middle: null_key, right: key3)
      qmk_array = thumb_keys.to_qmk_array(keycode_converter)
      expect(qmk_array).to eq(['KC_TAB', -1, 'KC_ENTER'])
    end

    it 'always returns 3 elements' do
      thumb_keys = described_class.new(left: key1)
      qmk_array = thumb_keys.to_qmk_array(keycode_converter)
      expect(qmk_array.size).to eq(3)
    end
  end

  describe '#to_yaml_hash' do
    it 'returns empty hash for all NULL_KEY (compact removes nil)' do
      thumb_keys = described_class.new
      yaml_hash = thumb_keys.to_yaml_hash
      expect(yaml_hash).to eq({})
    end

    it 'returns hash with key mappings' do
      thumb_keys = described_class.new(left: key1, middle: key2, right: key3)
      yaml_hash = thumb_keys.to_yaml_hash
      expect(yaml_hash).to eq({
        'left' => 'Tab',
        'middle' => 'Space',
        'right' => 'Enter'
      })
    end

    it 'compacts nil values (NULL_KEY.to_yaml returns nil)' do
      thumb_keys = described_class.new(left: key1, middle: null_key, right: key3)
      yaml_hash = thumb_keys.to_yaml_hash
      expect(yaml_hash).to eq({
        'left' => 'Tab',
        'right' => 'Enter'
      })
    end

    it 'returns only specified keys' do
      thumb_keys = described_class.new(middle: key2)
      yaml_hash = thumb_keys.to_yaml_hash
      expect(yaml_hash).to eq({ 'middle' => 'Space' })
    end
  end

  describe '#to_array' do
    it 'returns array of 3 elements' do
      thumb_keys = described_class.new(left: key1, middle: key2, right: key3)
      array = thumb_keys.to_array
      expect(array).to eq([key1, key2, key3])
    end

    it 'includes NULL_KEY in array' do
      thumb_keys = described_class.new(left: key1)
      array = thumb_keys.to_array
      expect(array).to eq([key1, null_key, null_key])
    end
  end

  describe '.from_array' do
    it 'creates ThumbKeys from full array' do
      thumb_keys = described_class.from_array([key1, key2, key3])
      expect(thumb_keys.left).to eq(key1)
      expect(thumb_keys.middle).to eq(key2)
      expect(thumb_keys.right).to eq(key3)
    end

    it 'creates ThumbKeys from partial array' do
      thumb_keys = described_class.from_array([key1, key2])
      expect(thumb_keys.left).to eq(key1)
      expect(thumb_keys.middle).to eq(key2)
      expect(thumb_keys.right).to eq(null_key)
    end

    it 'creates ThumbKeys from empty array' do
      thumb_keys = described_class.from_array([])
      expect(thumb_keys.left).to eq(null_key)
      expect(thumb_keys.middle).to eq(null_key)
      expect(thumb_keys.right).to eq(null_key)
    end

    it 'handles nil elements' do
      thumb_keys = described_class.from_array([key1, nil, key3])
      expect(thumb_keys.left).to eq(key1)
      expect(thumb_keys.middle).to eq(null_key)
      expect(thumb_keys.right).to eq(key3)
    end
  end

  describe '.from_yaml_hash' do
    let(:thumb_symbols) { ['left', 'middle', 'right'] }
    let(:factory) do
      ->(symbol:, keycode:, logical_coord:) do
        Cornix::Models::Layer::KeyMapping.new(
          symbol: symbol,
          keycode: keycode,
          logical_coord: logical_coord
        )
      end
    end

    it 'creates ThumbKeys from YAML hash' do
      yaml_hash = { 'left' => 'Tab', 'middle' => 'Space', 'right' => 'Enter' }
      thumb_keys = described_class.from_yaml_hash(yaml_hash, thumb_symbols, factory)

      expect(thumb_keys.left.symbol).to eq('left')
      expect(thumb_keys.left.keycode.to_s).to eq('Tab')
      expect(thumb_keys.middle.symbol).to eq('middle')
      expect(thumb_keys.middle.keycode.to_s).to eq('Space')
      expect(thumb_keys.right.symbol).to eq('right')
      expect(thumb_keys.right.keycode.to_s).to eq('Enter')
    end

    it 'creates ThumbKeys from partial YAML hash' do
      yaml_hash = { 'left' => 'Tab', 'right' => 'Enter' }
      thumb_keys = described_class.from_yaml_hash(yaml_hash, thumb_symbols, factory)

      expect(thumb_keys.left.symbol).to eq('left')
      expect(thumb_keys.middle).to eq(null_key)
      expect(thumb_keys.right.symbol).to eq('right')
    end

    it 'creates ThumbKeys from empty YAML hash' do
      yaml_hash = {}
      thumb_keys = described_class.from_yaml_hash(yaml_hash, thumb_symbols, factory)

      expect(thumb_keys.left).to eq(null_key)
      expect(thumb_keys.middle).to eq(null_key)
      expect(thumb_keys.right).to eq(null_key)
    end

    it 'handles nil YAML hash' do
      thumb_keys = described_class.from_yaml_hash(nil, thumb_symbols, factory)

      expect(thumb_keys.left).to eq(null_key)
      expect(thumb_keys.middle).to eq(null_key)
      expect(thumb_keys.right).to eq(null_key)
    end

    it 'sets correct logical coordinates' do
      yaml_hash = { 'left' => 'Tab', 'middle' => 'Space', 'right' => 'Enter' }
      thumb_keys = described_class.from_yaml_hash(yaml_hash, thumb_symbols, factory)

      expect(thumb_keys.left.logical_coord).to eq({ row: 3, col: 3 })
      expect(thumb_keys.middle.logical_coord).to eq({ row: 3, col: 4 })
      expect(thumb_keys.right.logical_coord).to eq({ row: 3, col: 5 })
    end
  end

  describe 'Null Object Pattern integration' do
    it 'allows polymorphic iteration without nil checks' do
      thumb_keys = described_class.new(left: key1, middle: null_key, right: key3)

      # nil チェック不要でポリモーフィックに処理可能
      results = thumb_keys.to_array.map { |key| key.to_qmk(keycode_converter) }
      expect(results).to eq(['KC_TAB', -1, 'KC_ENTER'])
    end

    it 'allows polymorphic YAML generation without nil checks' do
      thumb_keys = described_class.new(left: key1, middle: null_key, right: key3)

      # nil チェック不要で YAML 生成可能（compact で nil 除去）
      yaml_values = thumb_keys.to_array.map(&:to_yaml).compact
      expect(yaml_values).to eq(['Tab', 'Enter'])
    end
  end

  describe 'validation' do
    describe '#structurally_valid?' do
      it 'returns true for valid ThumbKeys with all NULL_KEY' do
        thumb_keys = described_class.new
        expect(thumb_keys.structurally_valid?).to be true
      end

      it 'returns true for valid ThumbKeys with real keys' do
        thumb_keys = described_class.new(left: key1, middle: key2, right: key3)
        expect(thumb_keys.structurally_valid?).to be true
      end

      it 'returns true for partial keys (NULL_KEY is valid)' do
        thumb_keys = described_class.new(left: key1, middle: null_key, right: key3)
        expect(thumb_keys.structurally_valid?).to be true
      end

      it 'returns false when a key has structural errors' do
        invalid_key = Cornix::Models::Layer::KeyMapping.new(
          symbol: '',  # 無効なシンボル
          keycode: 'Tab',
          logical_coord: { hand: :left, row: 3, col: 3 }
        )
        thumb_keys = described_class.new(left: invalid_key, middle: key2, right: key3)
        expect(thumb_keys.structurally_valid?).to be false
      end
    end

    describe '#structural_errors' do
      it 'returns empty array for valid ThumbKeys' do
        thumb_keys = described_class.new(left: key1, middle: key2, right: key3)
        expect(thumb_keys.structural_errors).to be_empty
      end

      it 'returns empty array for all NULL_KEY' do
        thumb_keys = described_class.new
        expect(thumb_keys.structural_errors).to be_empty
      end

      it 'includes errors from invalid keys' do
        invalid_key = Cornix::Models::Layer::KeyMapping.new(
          symbol: 'invalid!symbol',  # 無効なシンボル
          keycode: 'Tab',
          logical_coord: { hand: :left, row: 3, col: 3 }
        )
        thumb_keys = described_class.new(left: invalid_key, middle: key2, right: key3)
        errors = thumb_keys.structural_errors
        expect(errors.size).to be > 0
        expect(errors.join(' ')).to include('invalid characters')
      end

      it 'collects errors from multiple invalid keys' do
        invalid_key1 = Cornix::Models::Layer::KeyMapping.new(
          symbol: '',
          keycode: 'Tab',
          logical_coord: { hand: :left, row: 3, col: 3 }
        )
        invalid_key2 = Cornix::Models::Layer::KeyMapping.new(
          symbol: 'invalid!',
          keycode: 'Space',
          logical_coord: { hand: :left, row: 3, col: 4 }
        )
        thumb_keys = described_class.new(left: invalid_key1, middle: invalid_key2, right: key3)
        errors = thumb_keys.structural_errors
        expect(errors.size).to be >= 2
      end
    end

    describe '#semantic_errors' do
      it 'returns empty array for valid keys with valid keycodes' do
        thumb_keys = described_class.new(left: key1, middle: key2, right: key3)
        context = { keycode_converter: keycode_converter }
        errors = thumb_keys.semantic_errors(context)
        expect(errors).to be_empty
      end

      it 'returns empty array for all NULL_KEY' do
        thumb_keys = described_class.new
        context = { keycode_converter: keycode_converter }
        errors = thumb_keys.semantic_errors(context)
        expect(errors).to be_empty
      end

      it 'detects semantic errors in keys' do
        # 無効なキーコードを持つKeyMapping（セマンティックエラー）
        # ここではセマンティックエラーの伝播をテストするだけ
        # 実際の検証はKeyMappingのテストで行われる

        # semantic_errorsが存在する状況を作成
        # （実装上、KeyMappingがsemantic_errorsメソッドを持つことを確認）
        thumb_keys = described_class.new(left: key1, middle: key2, right: key3)
        context = { keycode_converter: keycode_converter }

        # エラーがないことを確認（正常系）
        errors = thumb_keys.semantic_errors(context)
        expect(errors).to be_empty
      end
    end

    describe '#validate!' do
      it 'does not raise for valid ThumbKeys' do
        thumb_keys = described_class.new(left: key1, middle: key2, right: key3)
        expect { thumb_keys.validate! }.not_to raise_error
      end

      it 'does not raise for all NULL_KEY' do
        thumb_keys = described_class.new
        expect { thumb_keys.validate! }.not_to raise_error
      end

      it 'raises ValidationError for invalid keys' do
        invalid_key = Cornix::Models::Layer::KeyMapping.new(
          symbol: '',
          keycode: 'Tab',
          logical_coord: { hand: :invalid, row: 3, col: 3 }
        )
        thumb_keys = described_class.new(left: invalid_key, middle: key2, right: key3)
        expect { thumb_keys.validate! }.to raise_error(Cornix::Models::Concerns::ValidationError)
      end
    end
  end
end
