# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require_relative '../../../lib/cornix/models/layer/key_mapping'
require_relative '../../../lib/cornix/converters/keycode_converter'
require_relative '../../../lib/cornix/converters/reference_converter'

RSpec.describe Cornix::Models::Layer::KeyMapping do
  let(:aliases_path) { File.join(__dir__, '../../../lib/cornix/keycode_aliases.yaml') }
  let(:keycode_converter) { Cornix::Converters::KeycodeConverter.new(aliases_path) }
  let(:config_dir) { File.join(__dir__, '../../fixtures/config') }
  let(:reference_converter) { Cornix::Converters::ReferenceConverter.new(config_dir) }

  before do
    FileUtils.mkdir_p("#{config_dir}/macros")
    File.write("#{config_dir}/macros/00_test_macro.yml", <<~YAML)
      name: Test Macro
      index: 0
      sequence: [{delay: 0, keycodes: [KC_H, KC_I]}]
    YAML
  end

  after do
    FileUtils.rm_rf(config_dir)
  end

  describe '#initialize' do
    it 'creates KeyMapping with String keycode' do
      key_mapping = described_class.new(
        symbol: 'Q',
        keycode: 'Tab',
        logical_coord: { hand: :left, row: 0, col: 1 }
      )

      expect(key_mapping.symbol).to eq('Q')
      expect(key_mapping.keycode).to be_a(Cornix::Models::Layer::KeycodeValue)
      expect(key_mapping.logical_coord).to eq({ hand: :left, row: 0, col: 1 })
    end

    it 'creates KeyMapping with KeycodeValue' do
      keycode_value = Cornix::Models::Layer::KeycodeValue.from_yaml('Tab')
      key_mapping = described_class.new(
        symbol: 'Q',
        keycode: keycode_value,
        logical_coord: { hand: :left, row: 0, col: 1 }
      )

      expect(key_mapping.keycode).to eq(keycode_value)
    end

    it 'automatically converts String to PlainKeycode' do
      key_mapping = described_class.new(symbol: 'Q', keycode: 'Tab', logical_coord: {})
      expect(key_mapping.keycode).to be_a(Cornix::Models::Layer::KeycodeValue::PlainKeycode)
    end

    it 'automatically converts String to ReferenceKeycode' do
      key_mapping = described_class.new(symbol: 'Q', keycode: "Macro('Test')", logical_coord: {})
      expect(key_mapping.keycode).to be_a(Cornix::Models::Layer::KeycodeValue::ReferenceKeycode)
    end

    it 'automatically converts String to FunctionKeycode' do
      key_mapping = described_class.new(symbol: 'Q', keycode: 'MO(1)', logical_coord: {})
      expect(key_mapping.keycode).to be_a(Cornix::Models::Layer::KeycodeValue::FunctionKeycode)
    end
  end

  describe '#to_qmk' do
    it 'converts PlainKeycode to QMK' do
      key_mapping = described_class.new(symbol: 'Q', keycode: 'Tab', logical_coord: {})
      qmk_code = key_mapping.to_qmk(keycode_converter)
      expect(qmk_code).to eq('KC_TAB')
    end

    it 'converts ReferenceKeycode to QMK' do
      key_mapping = described_class.new(symbol: 'Q', keycode: "Macro('Test Macro')", logical_coord: {})
      qmk_code = key_mapping.to_qmk(keycode_converter, reference_converter: reference_converter)
      expect(qmk_code).to eq('M0')
    end

    it 'converts FunctionKeycode to QMK' do
      key_mapping = described_class.new(symbol: 'Q', keycode: 'MO(1)', logical_coord: {})
      qmk_code = key_mapping.to_qmk(keycode_converter)
      expect(qmk_code).to eq('MO(1)')
    end

    it 'handles nested functions' do
      key_mapping = described_class.new(symbol: 'Q', keycode: 'LSFT(A)', logical_coord: {})
      qmk_code = key_mapping.to_qmk(keycode_converter)
      expect(qmk_code).to eq('LSFT(KC_A)')
    end
  end

  describe '#to_yaml' do
    it 'returns keycode string for PlainKeycode' do
      key_mapping = described_class.new(symbol: 'Q', keycode: 'Tab', logical_coord: {})
      expect(key_mapping.to_yaml).to eq('Tab')
    end

    it 'returns keycode string for ReferenceKeycode' do
      key_mapping = described_class.new(symbol: 'Q', keycode: "Macro('Test')", logical_coord: {})
      expect(key_mapping.to_yaml).to eq("Macro('Test')")
    end

    it 'returns keycode string for FunctionKeycode' do
      key_mapping = described_class.new(symbol: 'Q', keycode: 'MO(1)', logical_coord: {})
      expect(key_mapping.to_yaml).to eq('MO(1)')
    end
  end

  describe 'KeyMappable compliance' do
    it 'includes KeyMappable module' do
      expect(described_class.ancestors).to include(Cornix::Models::Layer::KeyMappable)
    end

    it 'responds to all KeyMappable methods' do
      key_mapping = described_class.new(symbol: 'Q', keycode: 'Tab', logical_coord: {})
      expect(key_mapping).to respond_to(:symbol)
      expect(key_mapping).to respond_to(:to_qmk)
      expect(key_mapping).to respond_to(:to_yaml)
      expect(key_mapping).to respond_to(:logical_coord)
    end

    it 'has correct symbol' do
      key_mapping = described_class.new(symbol: 'Q', keycode: 'Tab', logical_coord: {})
      expect(key_mapping.symbol).to eq('Q')
    end

    it 'has correct logical_coord' do
      coord = { hand: :left, row: 0, col: 1 }
      key_mapping = described_class.new(symbol: 'Q', keycode: 'Tab', logical_coord: coord)
      expect(key_mapping.logical_coord).to eq(coord)
    end
  end

  describe 'round-trip' do
    it 'maintains PlainKeycode through round-trip' do
      key_mapping = described_class.new(symbol: 'Q', keycode: 'Tab', logical_coord: {})
      qmk = key_mapping.to_qmk(keycode_converter)
      yaml = key_mapping.to_yaml

      expect(qmk).to eq('KC_TAB')
      expect(yaml).to eq('Tab')
    end

    it 'maintains FunctionKeycode through round-trip' do
      key_mapping = described_class.new(symbol: 'Q', keycode: 'LSFT(A)', logical_coord: {})
      qmk = key_mapping.to_qmk(keycode_converter)
      yaml = key_mapping.to_yaml

      expect(qmk).to eq('LSFT(KC_A)')
      expect(yaml).to eq('LSFT(A)')
    end
  end

  describe 'validation' do
    describe '#structurally_valid?' do
      it 'returns true for valid KeyMapping' do
        key_mapping = described_class.new(
          symbol: 'Q',
          keycode: 'Tab',
          logical_coord: { hand: :left, row: 0, col: 1 }
        )
        expect(key_mapping.structurally_valid?).to be true
      end

      it 'returns false when symbol is empty' do
        key_mapping = described_class.new(
          symbol: '',
          keycode: 'Tab',
          logical_coord: { hand: :left, row: 0, col: 1 }
        )
        expect(key_mapping.structurally_valid?).to be false
      end

      it 'validates symbol format' do
        # 有効なシンボル
        valid_key = described_class.new(
          symbol: 'valid_symbol-123',
          keycode: 'Tab',
          logical_coord: { hand: :left, row: 0, col: 1 }
        )
        expect(valid_key.structurally_valid?).to be true

        # 無効なシンボル（スペースを含む）
        invalid_key = described_class.new(
          symbol: 'invalid symbol',
          keycode: 'Tab',
          logical_coord: { hand: :left, row: 0, col: 1 }
        )
        expect(invalid_key.structurally_valid?).to be false
      end

      it 'validates logical_coord structure' do
        # 有効な座標
        valid_key = described_class.new(
          symbol: 'Q',
          keycode: 'Tab',
          logical_coord: { hand: :left, row: 0, col: 5 }
        )
        expect(valid_key.structurally_valid?).to be true

        # 無効な手
        invalid_hand = described_class.new(
          symbol: 'Q',
          keycode: 'Tab',
          logical_coord: { hand: :center, row: 0, col: 1 }
        )
        expect(invalid_hand.structurally_valid?).to be false

        # 無効な行（範囲外）
        invalid_row = described_class.new(
          symbol: 'Q',
          keycode: 'Tab',
          logical_coord: { hand: :left, row: 5, col: 1 }
        )
        expect(invalid_row.structurally_valid?).to be false

        # 無効な列（範囲外）
        invalid_col = described_class.new(
          symbol: 'Q',
          keycode: 'Tab',
          logical_coord: { hand: :left, row: 0, col: 10 }
        )
        expect(invalid_col.structurally_valid?).to be false
      end
    end

    describe '#structural_errors' do
      it 'returns empty array for valid KeyMapping' do
        key_mapping = described_class.new(
          symbol: 'Q',
          keycode: 'Tab',
          logical_coord: { hand: :left, row: 0, col: 1 }
        )
        expect(key_mapping.structural_errors).to be_empty
      end

      it 'includes error for empty symbol' do
        key_mapping = described_class.new(
          symbol: '',
          keycode: 'Tab',
          logical_coord: { hand: :left, row: 0, col: 1 }
        )
        errors = key_mapping.structural_errors
        expect(errors.size).to be > 0
        expect(errors.join(' ')).to include('cannot be nil or empty')
      end

      it 'includes error for invalid symbol format' do
        key_mapping = described_class.new(
          symbol: 'invalid!symbol',
          keycode: 'Tab',
          logical_coord: { hand: :left, row: 0, col: 1 }
        )
        errors = key_mapping.structural_errors
        expect(errors.size).to be > 0
        expect(errors.join(' ')).to include('invalid characters')
      end

      it 'includes error for invalid logical_coord' do
        key_mapping = described_class.new(
          symbol: 'Q',
          keycode: 'Tab',
          logical_coord: { hand: :invalid, row: 10, col: 20 }
        )
        errors = key_mapping.structural_errors
        expect(errors.size).to be > 0
        expect(errors.join(' ')).to match(/hand|row|col/)
      end
    end

    describe '#semantic_errors' do
      it 'returns empty array for valid keycode' do
        key_mapping = described_class.new(
          symbol: 'Q',
          keycode: 'Tab',
          logical_coord: { hand: :left, row: 0, col: 1 }
        )
        context = {
          keycode_converter: keycode_converter,
          reference_converter: reference_converter
        }
        errors = key_mapping.semantic_errors(context)
        expect(errors).to be_empty
      end

      it 'detects unresolvable keycode' do
        # 明確に解決不可能なキーコード（参照エラー）
        key_mapping = described_class.new(
          symbol: 'Q',
          keycode: "Macro('NonExistentMacro')",
          logical_coord: { hand: :left, row: 0, col: 1 }
        )
        context = {
          keycode_converter: keycode_converter,
          reference_converter: reference_converter
        }
        errors = key_mapping.semantic_errors(context)
        expect(errors.size).to be > 0
        expect(errors.join(' ')).to include('cannot be resolved')
      end
    end

    describe '#validate!' do
      it 'does not raise for valid KeyMapping' do
        key_mapping = described_class.new(
          symbol: 'Q',
          keycode: 'Tab',
          logical_coord: { hand: :left, row: 0, col: 1 }
        )
        expect { key_mapping.validate! }.not_to raise_error
      end

      it 'raises ValidationError for invalid KeyMapping' do
        key_mapping = described_class.new(
          symbol: '',
          keycode: 'Tab',
          logical_coord: { hand: :invalid, row: 0, col: 1 }
        )
        expect { key_mapping.validate! }.to raise_error(Cornix::Models::Concerns::ValidationError)
      end
    end
  end
end
