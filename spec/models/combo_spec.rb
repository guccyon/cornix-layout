# frozen_string_literal: true

require_relative '../spec_helper'
require_relative '../../lib/cornix/models/combo'
require_relative '../../lib/cornix/converters/keycode_converter'
require 'tempfile'
require 'yaml'

RSpec.describe Cornix::Models::Combo do
  let(:sample_qmk_array) { [20, 8, 0, 0, 47] } # Q + E → [

  describe '.from_qmk' do
    it 'QMK配列からComboを生成' do
      combo = described_class.from_qmk(3, sample_qmk_array)

      expect(combo.index).to eq(3)
      expect(combo.name).to eq('Combo 3')
      expect(combo.description).to eq('')
      expect(combo.trigger_keys).to eq([20, 8])
      expect(combo.output_key).to eq(47)
    end

    it '空配列（全ゼロ）を許容' do
      combo = described_class.from_qmk(0, [0, 0, 0, 0, 0])

      expect(combo.trigger_keys).to eq([])
      expect(combo.output_key).to eq(0)
      expect(combo.empty?).to be true
    end

    it '4つのトリガーキーを処理' do
      combo = described_class.from_qmk(5, [20, 8, 11, 9, 47]) # Q + E + R + F → [

      expect(combo.trigger_keys).to eq([20, 8, 11, 9])
      expect(combo.output_key).to eq(47)
    end
  end

  describe '#to_qmk' do
    it 'ComboをQMK配列に変換' do
      combo = described_class.from_qmk(3, sample_qmk_array)
      qmk_array = combo.to_qmk

      expect(qmk_array).to eq(sample_qmk_array)
    end

    it 'ゼロ配列を返す' do
      combo = described_class.from_qmk(0, [0, 0, 0, 0, 0])
      qmk_array = combo.to_qmk

      expect(qmk_array).to eq([0, 0, 0, 0, 0])
    end

    it 'トリガーキーが2つの場合はパディング' do
      combo = described_class.new(
        index: 0,
        name: 'Test',
        description: '',
        trigger_keys: [20, 8],
        output_key: 47
      )

      expect(combo.to_qmk).to eq([20, 8, 0, 0, 47])
    end

    it 'トリガーキーが4つの場合はそのまま' do
      combo = described_class.new(
        index: 0,
        name: 'Test',
        description: '',
        trigger_keys: [20, 8, 11, 9],
        output_key: 47
      )

      expect(combo.to_qmk).to eq([20, 8, 11, 9, 47])
    end
  end

  describe '.from_yaml_hash' do
    let(:yaml_hash) do
      {
        'index' => 5,
        'name' => 'Bracket Pair',
        'description' => 'Q + E for opening bracket',
        'trigger_keys' => [20, 8],
        'output_key' => 47
      }
    end

    it 'YAML HashからComboを生成' do
      combo = described_class.from_yaml_hash(yaml_hash)

      expect(combo.index).to eq(5)
      expect(combo.name).to eq('Bracket Pair')
      expect(combo.description).to eq('Q + E for opening bracket')
      expect(combo.trigger_keys).to eq([20, 8])
      expect(combo.output_key).to eq(47)
    end

    it 'descriptionがnilの場合は空文字列' do
      yaml_hash_no_desc = yaml_hash.dup
      yaml_hash_no_desc.delete('description')

      combo = described_class.from_yaml_hash(yaml_hash_no_desc)

      expect(combo.description).to eq('')
    end

    it 'trigger_keysがnilの場合は空配列' do
      yaml_hash_no_triggers = yaml_hash.dup
      yaml_hash_no_triggers.delete('trigger_keys')

      combo = described_class.from_yaml_hash(yaml_hash_no_triggers)

      expect(combo.trigger_keys).to eq([])
    end
  end

  describe '#to_yaml_hash' do
    it 'ComboをYAML Hashに変換' do
      combo = described_class.new(
        index: 5,
        name: 'Bracket Pair',
        description: 'Q + E for opening bracket',
        trigger_keys: [20, 8],
        output_key: 47
      )
      yaml_hash = combo.to_yaml_hash

      expect(yaml_hash['index']).to eq(5)
      expect(yaml_hash['name']).to eq('Bracket Pair')
      expect(yaml_hash['description']).to eq('Q + E for opening bracket')
      expect(yaml_hash['trigger_keys']).to eq([20, 8])
      expect(yaml_hash['output_key']).to eq(47)
    end
  end

  describe '#empty?' do
    it 'トリガーキーが空＆output_keyがゼロの場合はtrue' do
      combo = described_class.new(
        index: 0,
        name: 'Empty',
        description: '',
        trigger_keys: [],
        output_key: 0
      )

      expect(combo.empty?).to be true
    end

    it 'トリガーキーがnil＆output_keyがnilの場合はtrue' do
      combo = described_class.new(
        index: 0,
        name: 'Nil',
        description: '',
        trigger_keys: nil,
        output_key: nil
      )

      expect(combo.empty?).to be true
    end

    it 'トリガーキーがある場合はfalse' do
      combo = described_class.new(
        index: 0,
        name: 'Non-empty',
        description: '',
        trigger_keys: [20, 8],
        output_key: 0
      )

      expect(combo.empty?).to be false
    end

    it 'output_keyがある場合はfalse' do
      combo = described_class.new(
        index: 0,
        name: 'Non-empty',
        description: '',
        trigger_keys: [],
        output_key: 47
      )

      expect(combo.empty?).to be false
    end
  end

  describe 'round-trip conversion' do
    it 'QMK → Combo → QMK の往復変換' do
      original_array = [20, 8, 11, 9, 47]
      combo = described_class.from_qmk(7, original_array)
      qmk_array = combo.to_qmk

      expect(qmk_array).to eq(original_array)
    end

    it 'YAML → Combo → YAML の往復変換' do
      original_hash = {
        'index' => 8,
        'name' => 'Test Combo',
        'description' => 'Test description',
        'trigger_keys' => [20, 8, 11],
        'output_key' => 47
      }
      combo = described_class.from_yaml_hash(original_hash)
      yaml_hash = combo.to_yaml_hash

      expect(yaml_hash).to eq(original_hash)
    end
  end

  describe 'edge cases' do
    it '単一のトリガーキーを許容' do
      combo = described_class.new(
        index: 0,
        name: 'Single',
        description: '',
        trigger_keys: [20],
        output_key: 47
      )

      expect(combo.trigger_keys.size).to eq(1)
      expect(combo.to_qmk).to eq([20, 0, 0, 0, 47])
    end

    it '空文字列の名前を許容' do
      combo = described_class.new(
        index: 0,
        name: '',
        description: '',
        trigger_keys: [],
        output_key: 0
      )

      expect(combo.name).to eq('')
    end

    it '大きなキーコード値を許容' do
      combo = described_class.new(
        index: 0,
        name: 'Large',
        description: '',
        trigger_keys: [65535, 65534],
        output_key: 65533
      )

      expect(combo.to_qmk).to eq([65535, 65534, 0, 0, 65533])
    end
  end

  describe 'validation' do
    let(:test_aliases) do
      {
        'aliases' => {
          'A' => 'KC_A',
          'B' => 'KC_B',
          'C' => 'KC_C',
          'Enter' => 'KC_ENT'
        }
      }
    end

    let(:yaml_file) do
      file = Tempfile.new(['keycode_aliases', '.yaml'])
      file.write(YAML.dump(test_aliases))
      file.close
      file
    end

    let(:keycode_converter) { Cornix::Converters::KeycodeConverter.new(yaml_file.path) }
    let(:context) { { keycode_converter: keycode_converter } }

    after do
      yaml_file.unlink
    end

    describe 'structural validations' do
      it 'output_key が nil の場合にエラー' do
        combo = described_class.new(
          index: 0,
          name: 'Test',
          description: '',
          trigger_keys: ['A', 'B'],
          output_key: nil
        )
        errors = combo.structural_errors
        expect(errors).not_to be_empty
        expect(errors.join).to include('output_key')
        expect(errors.join).to match(/cannot be (blank|nil)/i)
      end

      it 'output_key が存在する場合は構造検証合格' do
        combo = described_class.new(
          index: 0,
          name: 'Test',
          description: '',
          trigger_keys: ['A', 'B'],
          output_key: 'Enter'
        )
        errors = combo.structural_errors
        expect(errors).to be_empty
      end

      it 'trigger_keys が空配列の場合にエラー' do
        combo = described_class.new(
          index: 0,
          name: 'Test',
          description: '',
          trigger_keys: [],
          output_key: 'Enter'
        )
        errors = combo.structural_errors
        expect(errors).not_to be_empty
        expect(errors.join).to include('trigger_keys')
        expect(errors.join).to match(/cannot be (blank|empty)/i)
      end
    end

    describe 'semantic validations' do
      it '有効なキーコードを持つComboを検証' do
        combo = described_class.new(
          index: 0,
          name: 'Test',
          description: '',
          trigger_keys: ['A', 'B'],
          output_key: 'Enter'
        )
        errors = combo.semantic_errors(context)
        expect(errors).to be_empty
      end

      it '無効なキーコードを含むComboでエラー（trigger_keys）' do
        combo = described_class.new(
          index: 0,
          name: 'Test',
          description: '',
          trigger_keys: ['A', 'InvalidKey', 'C'],
          output_key: 'Enter'
        )
        errors = combo.semantic_errors(context)
        expect(errors).not_to be_empty
        expect(errors.join).to include("Invalid keycode 'InvalidKey'")
        expect(errors.join).to include('trigger_keys[1]')
      end

      it '無効なキーコードを含むComboでエラー（output_key）' do
        combo = described_class.new(
          index: 0,
          name: 'Test',
          description: '',
          trigger_keys: ['A', 'B'],
          output_key: 'BadKey'
        )
        errors = combo.semantic_errors(context)
        expect(errors).not_to be_empty
        expect(errors.join).to include("Invalid keycode 'BadKey'")
        expect(errors.join).to include('output_key')
      end

      it '空値（0, -1, nil）は許可' do
        combo = described_class.new(
          index: 0,
          name: 'Test',
          description: '',
          trigger_keys: ['A', 0, -1],
          output_key: nil
        )
        errors = combo.semantic_errors(context)
        expect(errors).to be_empty
      end

      it '複数の無効なキーコードでエラー' do
        combo = described_class.new(
          index: 0,
          name: 'Test',
          description: '',
          trigger_keys: ['Invalid1', 'B', 'Invalid2'],
          output_key: 'BadOutput'
        )
        errors = combo.semantic_errors(context)
        expect(errors).not_to be_empty
        expect(errors.join).to include("Invalid keycode 'Invalid1'")
        expect(errors.join).to include("Invalid keycode 'Invalid2'")
        expect(errors.join).to include("Invalid keycode 'BadOutput'")
      end
    end
  end
end
